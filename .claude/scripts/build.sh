#!/bin/bash
# build.sh — fast, conflict-safe builds for parallel dev/QA agents.
#
# Why this exists (Apple M1 / 16 GB): a fresh per-worktree build recompiles
# Realm-core from source (~10 min, multi-GB RAM spike). Run a few of those at
# once and the machine OOM-thrashes and xcodebuild dies "BUILD INTERRUPTED".
#
# This wrapper fixes that:
#   1. SHARED SwiftPM cache  — Realm is downloaded once for all worktrees.
#   2. PREWARMED template DD — 'prewarm' compiles Realm into a template ONCE; each
#      worktree's DerivedData is seeded by an APFS copy-on-write clone of it, which
#      preserves most Realm objects + the module cache. A fresh worktree builds
#      ~4x faster (~2.5 min vs ~10 min cold), then later builds in it are fully
#      incremental (~30s). NOTE: a fresh worktree still PARTIALLY recompiles Realm
#      (build records are path-specific); for zero Realm recompiles, move the
#      project to Realm's prebuilt XCFramework. App target builds in isolation so
#      there are no cross-worktree product collisions.
#   3. BUILD SEMAPHORE       — at most MT_MAX_BUILDS (default 2) xcodebuilds run
#      at once; the rest queue. This is the anti-thrash control.
#   4. Uses 'generic/platform=iOS Simulator' for builds, so the missing
#      'iPhone 17' simulator no longer breaks every build.
#
# Usage:
#   build.sh prewarm     # one-time (or after Realm version bump): compile the template
#   build.sh build       # build this worktree's app (CoW-seeded + semaphored)
#   build.sh test        # build + run unit tests on an available simulator
#   build.sh status      # show cache + semaphore state
#   build.sh clean       # prune per-worktree DerivedData + stale locks
#   build.sh selftest [secs]   # exercise the semaphore without building
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
TEMPLATE_DD="$BASE/template-dd"
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

resolve_pkgs(){
  log "resolving SwiftPM packages into shared cache…"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -clonedSourcePackagesDirPath "$SPM_CACHE" \
    -resolvePackageDependencies >/dev/null 2>&1 || true
}

cmd_prewarm(){
  resolve_pkgs
  log "compiling Realm + app into TEMPLATE DerivedData (one-time, slow)…"
  rm -rf "$TEMPLATE_DD"
  acquire
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -clonedSourcePackagesDirPath "$SPM_CACHE" \
    -derivedDataPath "$TEMPLATE_DD" \
    build || { log "prewarm FAILED"; exit 1; }
  log "template ready: $TEMPLATE_DD"
}

seed_dd(){
  [ -d "$WT_DD" ] && return
  if [ -d "$TEMPLATE_DD" ]; then
    log "seeding '$WT_NAME' DerivedData from template (APFS clone)…"
    cp -c -R "$TEMPLATE_DD" "$WT_DD" 2>/dev/null || cp -R "$TEMPLATE_DD" "$WT_DD"
  else
    log "no template yet — first build will be slow. Run 'build.sh prewarm' once."
    mkdir -p "$WT_DD"
  fi
}

cmd_build(){
  seed_dd; acquire
  log "building $SCHEME (worktree: $WT_NAME)…"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -clonedSourcePackagesDirPath "$SPM_CACHE" \
    -derivedDataPath "$WT_DD" \
    build
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
  seed_dd; acquire
  local sim; sim="$(pick_sim)"; log "testing on simulator: $sim"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -destination "platform=iOS Simulator,name=$sim" \
    -clonedSourcePackagesDirPath "$SPM_CACHE" \
    -derivedDataPath "$WT_DD" \
    test
}

cmd_status(){
  echo "cache base : $BASE"
  echo "template   : $([ -d "$TEMPLATE_DD" ] && du -sh "$TEMPLATE_DD" 2>/dev/null | cut -f1 || echo 'NOT BUILT — run prewarm')"
  echo "spm cache  : $(du -sh "$SPM_CACHE" 2>/dev/null | cut -f1 || echo '-')"
  echo "worktree DDs:"; du -sh "$BASE"/dd/* 2>/dev/null || echo "  (none)"
  echo "max builds : $MAX_BUILDS   slots in use: $(ls -d "$SEM_DIR"/slot.* 2>/dev/null | wc -l | tr -d ' ')"
}

cmd_clean(){
  log "pruning per-worktree DerivedData and stale locks…"
  rm -rf "$BASE"/dd/* "$SEM_DIR"/slot.* 2>/dev/null
  log "kept template + spm cache. Done."
}

cmd_selftest(){
  local secs="${1:-8}"
  acquire
  log "selftest holding $SLOT for ${secs}s (pid $$)"
  sleep "$secs"
  log "selftest releasing (pid $$)"
}

case "${1:-build}" in
  prewarm) cmd_prewarm ;;
  build)   cmd_build ;;
  test)    cmd_test ;;
  status)  cmd_status ;;
  clean)   cmd_clean ;;
  selftest) shift; cmd_selftest "${1:-8}" ;;
  *) echo "usage: build.sh [prewarm|build|test|status|clean|selftest]"; exit 2 ;;
esac
