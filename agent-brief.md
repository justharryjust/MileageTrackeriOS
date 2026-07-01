# Agent Brief — MileageTrackeriOS

Codebase-agnostic agents read this file for everything specific to this project.

## Overview

- **App**: MileageTrackeriOS — iOS mileage tracking with automatic trip detection
- **Language**: Swift (SwiftUI + UIKit)
- **Bundle ID**: `com.harryjust.MileageTrackeriOS`

## Build & Test

All builds and tests go through the wrapper script — **never call `xcodebuild` directly.** It enforces the build semaphore, shares the SwiftPM cache, and seeds DerivedData from the prewarmed Realm template (see *Parallel builds* below).

```bash
# Build the app
.claude/scripts/build.sh build

# Build + run unit tests
.claude/scripts/build.sh test

# One-time (orchestrator runs this before dispatching agents; also after a Realm version bump):
.claude/scripts/build.sh prewarm
```

### Parallel builds (read this)

This is an Apple M1 / 16 GB machine — naïve parallel `xcodebuild`s can OOM-thrash it. The wrapper prevents that:

- **Build semaphore** — at most `MT_MAX_BUILDS` (default **2**) builds run at once; extra builds queue. Do not bypass it.
- **Shared SwiftPM cache** — the Realm binary (below) and any package are downloaded once into a shared cache and reused by every worktree, not re-fetched per build.
- **Agent concurrency** — cap concurrent **Developer** agents to ≈2 (match `MT_MAX_BUILDS`), not just QA. Developer/Scoper agents are otherwise uncapped and will stampede.

> Realm ships as a **prebuilt binary** (`LocalPackages/RealmBinary`) — builds no longer compile realm-core from source, so a fresh worktree builds the app in ~45 s and no prewarm step is needed.

## Simulator

- **Device**: the wrapper **auto-selects an available simulator** (e.g. iPhone 16 / 16 Pro); plain builds use a generic `iOS Simulator` destination so a specific device name is never required. Override with `MT_SIM="<name>"` if needed. *(Note: there is no "iPhone 17" simulator — do not hardcode it.)*
- **App path**: `~/Library/Caches/MileageTrackerBuild/dd/<worktree>/Build/Products/Debug-iphonesimulator/MileageTrackeriOS.app`
- **Install**: `mobile_install_app` Mobile MCP tool, or `xcrun simctl install booted <path>`
- **Launch**: `mobile_launch_app` with package `com.harryjust.MileageTrackeriOS`

## GitHub Project Board

- **URL**: https://github.com/users/justharryjust/projects/2
- **Project ID**: `PVT_kwHOARlJks4Bbias`
- **Repo**: `justharryjust/MileageTrackeriOS`
- **Status field ID**: `PVTSSF_lAHOARlJks4BbiaszhWSQ5s`

### Status Columns

| Column | Option ID |
|---|---|
| Backlog | `f75ad846` |
| Refined | `51264d39` |
| Ready to Pick Up | `4eaa7776` |
| In Progress | `47fc9ee4` |
| In Review | `0e814af9` |
| Done | `98236657` |

### Moving Cards

```bash
gh api graphql -f query='
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: "PVT_kwHOARlJks4Bbias"
    itemId: "<item-id>"
    fieldId: "PVTSSF_lAHOARlJks4BbiaszhWSQ5s"
    value: {singleSelectOptionId: "<option-id>"}
  }) {
    projectV2Item { id }
  }
}'
```

### Fetching Board

```bash
gh api graphql -f query='
query {
  node(id: "PVT_kwHOARlJks4Bbias") {
    ... on ProjectV2 {
      items(first: 50) {
        nodes {
          id
          type
          fieldValues(first: 10) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field { ... on ProjectV2SingleSelectField { name } }
              }
            }
          }
          content {
            ... on Issue { title number url state body }
            ... on PullRequest { title number url state }
            ... on DraftIssue { title }
          }
        }
      }
    }
  }
}'
```

### Checking PR Review Status

```bash
gh pr view <pr-url> --json reviews,state --jq '{state: .state, latestReview: .reviews[-1].state}'
```

## Orchestrator State File

- **Path**: `.claude/project-state.json`
- **Format**: `[{id, status, title, url, type, number, dispatched, agentType}]`
- `agentType`: `"scope"`, `"dev"`, or `"qa"`

## Branch Naming

- Format: `feature/<kebab-name>` based on ticket title

## Constraints

- QA is the only agent authorized to merge to main
- Never push directly to main
- Follow patterns in CLAUDE.md
- Mobile MCP available for simulator testing (QA only)
