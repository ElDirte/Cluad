#!/usr/bin/env bash
# Routes tagged inbox items into the Logseq vault (pages/ or journals/)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
[ -f "$VAULT_ROOT/.env" ] && source "$VAULT_ROOT/.env"

INBOX="$VAULT_ROOT/00-inbox"
LOGSEQ_PAGES="$VAULT_ROOT/01-logseq/pages"
LOGSEQ_JOURNALS="$VAULT_ROOT/01-logseq/journals"
LOG_FILE="$VAULT_ROOT/logs/intake.log"

mkdir -p "$LOGSEQ_PAGES" "$LOGSEQ_JOURNALS" "$VAULT_ROOT/logs"

route_file() {
  local file="$1"

  python3 - "$file" "$LOGSEQ_PAGES" "$LOGSEQ_JOURNALS" <<'PYEOF'
import sys, re
from pathlib import Path

src_path = Path(sys.argv[1])
pages_dir = Path(sys.argv[2])
journals_dir = Path(sys.argv[3])

content = src_path.read_text(encoding='utf-8', errors='ignore')

# Parse frontmatter
fm = {}
if content.startswith('---'):
    parts = content.split('---', 2)
    if len(parts) >= 3:
        for line in parts[1].splitlines():
            if ':' in line:
                k, _, v = line.partition(':')
                fm[k.strip()] = v.strip()

# Skip untagged
if not fm.get('tagged'):
    sys.exit(0)

src_type = fm.get('src', '')
date_val = fm.get('date', '')
use_val = fm.get('use', '')
topic_val = fm.get('topic', '')

# Decide: journal or atomic page
is_journal = src_type in ('transcript', 'email') or use_val in ('memory-trigger', 'reminder')

if is_journal and date_val:
    # Append as a block to the daily journal page
    journal_file = journals_dir / f"{date_val}.md"
    stem = src_path.stem.replace('_', ' ').title()
    summary = fm.get('summary', stem)
    tags = ' '.join(f'[[{v}]]' for k, v in fm.items()
                    if k in ('use','topic','proj') and v not in ('', 'none'))

    block = f"\n## {summary}\n{tags}\n\n"
    # Include body (skip frontmatter)
    body_parts = content.split('---', 2)
    body = body_parts[2].strip() if len(body_parts) >= 3 else content
    block += body[:3000] + "\n"

    with open(journal_file, 'a', encoding='utf-8') as f:
        f.write(block)
    print(f"[route-logseq] Appended to journal: {journal_file.name}")

else:
    # Create atomic page
    slug = re.sub(r'[^a-z0-9-]', '-', src_path.stem.lower())
    slug = re.sub(r'-+', '-', slug).strip('-')[:80]
    dest_file = pages_dir / f"{slug}.md"

    # Add Logseq-style wikilinks to frontmatter tags
    body_parts = content.split('---', 2)
    body = body_parts[2].strip() if len(body_parts) >= 3 else content

    # Build Logseq page with tags block
    tag_links = ' '.join(f'[[{v}]]' for k, v in fm.items()
                         if k in ('use','topic','proj') and v not in ('', 'none'))
    logseq_content = f"{content.split('---',2)[0]}---{body_parts[1]}---\n\ntags:: {tag_links}\n\n{body}"

    dest_file.write_text(logseq_content, encoding='utf-8')
    print(f"[route-logseq] Created page: {dest_file.name}")

# Mark source as processed
lines = content.splitlines()
new_lines = []
for line in lines:
    if line.startswith('status:'):
        new_lines.append('status: reviewed')
    else:
        new_lines.append(line)
src_path.write_text('\n'.join(new_lines), encoding='utf-8')
PYEOF
}

routed=0

find "$INBOX" -name "*.md" | while read -r file; do
  # Only route tagged, not-yet-reviewed items
  if grep -q "^tagged: true" "$file" 2>/dev/null && ! grep -q "^status: reviewed" "$file" 2>/dev/null; then
    route_file "$file"
    echo "$(date -Iseconds) ROUTE $(basename "$file")" >> "$LOG_FILE"
    routed=$((routed + 1))
  fi
done

echo "[route-logseq] Done. Logseq vault updated at $VAULT_ROOT/01-logseq"
