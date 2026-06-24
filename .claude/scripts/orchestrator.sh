#!/bin/bash
# Local orchestrator — polls the GitHub Projects board and dispatches agents.
# Run manually or via cron: .claude/scripts/orchestrator.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

PROJECT_ID="PVT_kwHOARlJks4Bbias"
STATE_FILE=".claude/project-state.json"
TMP_PREV=$(mktemp)
TMP_CURR=$(mktemp)
TMP_CHANGES=$(mktemp)
trap "rm -f $TMP_PREV $TMP_CURR $TMP_CHANGES" EXIT

# ── Fetch current board state ─────────────────────────────────────────
fetch_board() {
  gh api graphql -f query="
  query {
    node(id: \"$PROJECT_ID\") {
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
              ... on Issue { title number url state }
              ... on PullRequest { title number url state }
              ... on DraftIssue { title }
            }
          }
        }
      }
    }
  }"
}

# ── Normalize items to a clean JSON array ─────────────────────────────
normalize() {
  python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data['data']['node']['items']['nodes']
result = []
for i in items:
    status = None
    for f in i.get('fieldValues', {}).get('nodes', []):
        if f and f.get('field', {}).get('name') == 'Status':
            status = f.get('name')
            break
    content = i.get('content') or {}
    result.append({
        'id': i['id'],
        'type': i.get('type', ''),
        'status': status,
        'title': content.get('title', 'Untitled'),
        'url': content.get('url', ''),
        'number': content.get('number'),
        'state': content.get('state', '')
    })
print(json.dumps(result))
"
}

echo "=== Orchestrator check $(date) ==="

RAW=$(fetch_board)
echo "$RAW" | normalize > "$TMP_CURR"

# Load previous state
if [ -f "$STATE_FILE" ]; then
  cp "$STATE_FILE" "$TMP_PREV"
else
  echo "[]" > "$TMP_PREV"
fi

# Save current state
cp "$TMP_CURR" "$STATE_FILE"

# ── Compare and detect changes ────────────────────────────────────────
python3 -c "
import json

with open('$TMP_PREV') as f:
    prev = json.load(f)
with open('$TMP_CURR') as f:
    curr = json.load(f)

prev_map = {i['id']: i for i in prev}
curr_map = {i['id']: i for i in curr}
changes = []

# Status transitions
for cid, c in curr_map.items():
    prev_status = prev_map.get(cid, {}).get('status')
    curr_status = c.get('status')
    if prev_status != curr_status:
        changes.append({
            'id': cid,
            'from': prev_status,
            'to': curr_status,
            'title': c.get('title', ''),
            'url': c.get('url', ''),
            'is_new': cid not in prev_map
        })

# New items not in Backlog are still worth noting
for cid in curr_map:
    if cid not in prev_map and curr_map[cid].get('status') != 'Backlog':
        pass  # Already caught by the status transition check above

with open('$TMP_CHANGES', 'w') as f:
    json.dump(changes, f)
"

CHANGES=$(cat "$TMP_CHANGES")

if [ "$(python3 -c "import json; print(len(json.load(open('$TMP_CHANGES'))))")" = "0" ]; then
  echo "No transitions detected."
  exit 0
fi

echo "Changes detected:"
python3 -m json.tool "$TMP_CHANGES"

# ── Dispatch ──────────────────────────────────────────────────────────
python3 -c "
import json

with open('$TMP_CHANGES') as f:
    changes = json.load(f)

for c in changes:
    to_status = c.get('to', '')
    title = c.get('title', 'Unknown')
    url = c.get('url', '')

    if c.get('is_new') and to_status == 'Backlog':
        print(f'🔍 SCOPING: {title}')
        print(f'   URL: {url}')
        print(f'   Run: /scope {url}')
        print()

    elif to_status == 'In Progress':
        print(f'🛠  DEVELOP: {title}')
        print(f'   URL: {url}')
        print(f'   Run: /dev {url}')
        print()

    elif to_status == 'In Review':
        print(f'🧪 QA: {title}')
        print(f'   URL: {url}')
        print(f'   Run: /qa {url}')
        print()

    elif to_status == 'Done':
        print(f'✅ DONE: {title}')
        print()

    else:
        print(f'📋 {title}: {c.get(\"from\", \"?\")} → {to_status}')
        if url:
            print(f'   URL: {url}')
        print()
"

echo "=== Orchestrator done ==="
