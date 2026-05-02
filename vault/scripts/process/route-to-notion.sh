#!/usr/bin/env bash
# Mirrors reviewed Logseq pages to Notion (public-facing / legacy store)
# Requires NOTION_TOKEN and NOTION_DATABASE_ID in .env

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
[ -f "$VAULT_ROOT/.env" ] && source "$VAULT_ROOT/.env"

LOGSEQ_PAGES="$VAULT_ROOT/01-logseq/pages"
LOG_FILE="$VAULT_ROOT/logs/intake.log"
MANIFEST="$VAULT_ROOT/data/notion-synced.txt"

touch "$MANIFEST"

if [ -z "${NOTION_TOKEN:-}" ] || [ -z "${NOTION_DATABASE_ID:-}" ]; then
  echo "[route-notion] NOTION_TOKEN or NOTION_DATABASE_ID not set in .env — skipping"
  exit 0
fi

push_to_notion() {
  python3 - "$1" "$NOTION_TOKEN" "$NOTION_DATABASE_ID" <<'PYEOF'
import sys, json, re
import urllib.request, urllib.error
from pathlib import Path

filepath = Path(sys.argv[1])
token, db_id = sys.argv[2], sys.argv[3]

content = filepath.read_text(encoding='utf-8', errors='ignore')

# Parse frontmatter
fm = {}
body = content
if content.startswith('---'):
    parts = content.split('---', 2)
    if len(parts) >= 3:
        for line in parts[1].splitlines():
            if ':' in line:
                k, _, v = line.partition(':')
                fm[k.strip()] = v.strip().strip('"')
        body = parts[2].strip()

title = filepath.stem.replace('-', ' ').title()
tags = [fm[k] for k in ('use','topic','proj') if fm.get(k) and fm[k] != 'none']
date_val = fm.get('date', '')

# Build Notion page payload
page = {
    "parent": {"database_id": db_id},
    "properties": {
        "Name": {"title": [{"text": {"content": title[:100]}}]},
        "Tags": {"multi_select": [{"name": t} for t in tags[:5]]},
        "Source": {"rich_text": [{"text": {"content": fm.get('src', '')}}]},
        "Summary": {"rich_text": [{"text": {"content": fm.get('summary', '')[:200]}}]},
    },
    "children": [
        {
            "object": "block",
            "type": "paragraph",
            "paragraph": {
                "rich_text": [{"type": "text", "text": {"content": body[:2000]}}]
            }
        }
    ]
}
if date_val:
    page["properties"]["Date"] = {"date": {"start": date_val}}

payload = json.dumps(page).encode()
req = urllib.request.Request(
    "https://api.notion.com/v1/pages",
    data=payload,
    headers={
        "Authorization": f"Bearer {token}",
        "Notion-Version": "2022-06-28",
        "Content-Type": "application/json"
    }
)
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        resp = json.loads(r.read())
        print(f"[route-notion] Created: {resp.get('id','?')} — {title}")
except urllib.error.HTTPError as e:
    print(f"[route-notion] ERROR {e.code}: {e.read().decode()[:200]}")
PYEOF
}

find "$LOGSEQ_PAGES" -name "*.md" | while read -r file; do
  file_hash=$(md5sum "$file" | cut -d' ' -f1)
  grep -qF "$file_hash" "$MANIFEST" 2>/dev/null && continue

  push_to_notion "$file"
  echo "$file_hash  $file" >> "$MANIFEST"
  echo "$(date -Iseconds) NOTION $(basename "$file")" >> "$LOG_FILE"
done

echo "[route-notion] Done."
