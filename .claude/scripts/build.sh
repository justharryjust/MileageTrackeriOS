#!/bin/bash
# build.sh — conflict-safe parallel builds for dev/QA agents.
#
# Realm ships as a prebuilt binary (LocalPackages/RealmBinary), so builds no
# longer compile realm-core from source. This wrapper still does two useful things
# on this Apple M1 / 16 GB machine:
#   1. BUILD SEMAPHORE — at most MT_MAX_BUILDS (default 2) xcodebuilds run at once;
#      the rest queue. Stops parallel app-builds + simulators from OOM-thrashing.
#   2. SHARED SwiftPM cache — the Realm binary (and any package) is downloaded once
#      into a shared cache and reused by every worktree, not re-fetched per build.
#   Builds use 'generic/platform=iOS Simulator' so a specific device name is never
#   required (there is no 'iPhone 17' simulator).
#
# Usage:
#   build.sh build           # build the app
#   build.sh test            # build + run unit tests on an available simulator
#   build.sh status          # show cache + semaphore state
#   build.sh clean           # prune per-worktree DerivedData + stale locks
#   build.sh selftest [secs] # exercise the semaphore without building
#
# Env: MT_MAX_BUILDS (default 2), MT_SCHEME, MT_PROJECT, MT_SIM

set -uo pipefail

SCHEME="${MT_SCHEME:-MileageTrackeriOS}"
PROJECT="${MT_PROJECT:-MileageTrackeriOS.xcodeproj}"
MAX_BUILDS="${MT_MAX_BUILDS:-2}"
STALE_MIN=45   # a held build slot older than this is considered stale and stealable

# Shared cache lives outside the repo so the orchestrator's branch-churn can't disturb it.
BASE="$HOME/Library/Caches/MileageTrackerBuild"
SPM_CACHE="$BASE/spm"
SEM_DIR="$BASE/sem"
mkdir -p "$SPM_CACHE" "$SEM_DIR" "$BASE/dd"

GIT_TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "[build.sh] not in a git repo"; exit 1; }
WT_NAME="$(basename "$GIT_TOP")"
WT_DD="$BASE/dd/$WT_NAME"

log(){ echo "[build.sh] $*"; }

# ---- global N-slot semaphore (mkdir is atomic; steals stale slots) ----
SLOT=""
acquire(){
  local waited=0
  while :; do
    local i
    for i in $(seq 1 "$MAX_BUILDS"); do
      local s="$SEM_DIR/slot.$i"
      if mkdir "$s" 2>/dev/null; then
        echo "$$" > "$s/pid"; SLOT="$s"; trap release EXIT INT TERM
        log "acquired build slot $i/$MAX_BUILDS"; return
      fi
      if [ -d "$s" ] && [ -n "$(find "$s" -maxdepth 0 -mmin +$STALE_MIN 2>/dev/null)" ]; then
        rm -rf "$s" 2>/dev/null && log "reclaimed stale slot $i"
      fi
    done
    [ "$waited" = 0 ] && log "all $MAX_BUILDS build slots busy — queuing…"
    waited=$((waited+1)); sleep 5
  done
}
release(){ [ -n "$SLOT" ] && rm -rf "$SLOT" 2>/dev/null; SLOT=""; }

# Run xcodebuild under the semaphore, with the shared SwiftPM cache + this
# worktree's own isolated (persistent, incremental) DerivedData.
xcb(){
  acquire
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -clonedSourcePackagesDirPath "$SPM_CACHE" \
    -derivedDataPath "$WT_DD" \
    "$@"
}

cmd_build(){
  log "building $SCHEME (worktree: $WT_NAME)…"
  xcb -destination 'generic/platform=iOS Simulator' build
}

pick_sim(){
  if [ -n "${MT_SIM:-}" ]; then echo "$MT_SIM"; return; fi
  local n
  for n in "iPhone 16" "iPhone 16 Pro" "iPhone 17 Pro" "iPhone 15" "iPhone 16e"; do
    if xcrun simctl list devices available | grep -q "    $n ("; then echo "$n"; return; fi
  done
  xcrun simctl list devices available | grep -E "iPhone .*\(" | head -1 | sed -E 's/^ *//; s/ \(.*//'
}

cmd_test(){
  local sim; sim="$(pick_sim)"; log "testing on simulator: $sim"
  xcb -destination "platform=iOS Simulator,name=$sim" test
}

cmd_status(){
  echo "cache base : $BASE"
  echo "spm cache  : $(du -sh "$SPM_CACHE" 2>/dev/null | cut -f1 || echo '-')"
  echo "worktree DDs:"; du -sh "$BASE"/dd/* 2>/dev/null || echo "  (none)"
  echo "max builds : $MAX_BUILDS   slots in use: $(ls -d "$SEM_DIR"/slot.* 2>/dev/null | wc -l | tr -d ' ')"
}

cmd_clean(){
  log "pruning per-worktree DerivedData and stale locks…"
  rm -rf "$BASE"/dd/* "$SEM_DIR"/slot.* 2>/dev/null
  log "done."
}

cmd_selftest(){
  local secs="${1:-8}"
  acquire
  log "selftest holding $SLOT for ${secs}s (pid $$)"
  sleep "$secs"
  log "selftest releasing (pid $$)"
}

case "${1:-build}" in
  build)   cmd_build ;;
  test)    cmd_test ;;
  status)  cmd_status ;;
  clean)   cmd_clean ;;
  selftest) shift; cmd_selftest "${1:-8}" ;;
  *) echo "usage: build.sh [build|test|status|clean|selftest]"; exit 2 ;;
esac
