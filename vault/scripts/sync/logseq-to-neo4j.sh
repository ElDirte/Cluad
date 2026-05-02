#!/usr/bin/env bash
# Parses Logseq pages for [[wikilinks]] and YAML frontmatter,
# generates Cypher files, and loads them into Neo4j.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
[ -f "$VAULT_ROOT/.env" ] && source "$VAULT_ROOT/.env"

LOGSEQ_PAGES="$VAULT_ROOT/01-logseq/pages"
LOGSEQ_JOURNALS="$VAULT_ROOT/01-logseq/journals"
NEO4J_EXPORTS="$VAULT_ROOT/02-neo4j/exports"
LOG_FILE="$VAULT_ROOT/logs/intake.log"
MANIFEST="$VAULT_ROOT/data/neo4j-synced.txt"

NEO4J_URI="${NEO4J_URI:-bolt://localhost:7687}"
NEO4J_USER="${NEO4J_USER:-neo4j}"
NEO4J_PASSWORD="${NEO4J_PASSWORD:-changeme}"
HTTP_HOST=$(echo "$NEO4J_URI" | sed 's|bolt://||' | cut -d: -f1)
HTTP_PORT=7474

mkdir -p "$NEO4J_EXPORTS" "$VAULT_ROOT/logs" "$VAULT_ROOT/data"
touch "$MANIFEST"

# Step 1: Parse all Logseq markdown → generate Cypher
CYPHER_FILE="$NEO4J_EXPORTS/$(date '+%Y-%m-%d_%H%M%S')_sync.cypher"

python3 - "$LOGSEQ_PAGES" "$LOGSEQ_JOURNALS" "$CYPHER_FILE" "$MANIFEST" <<'PYEOF'
import sys, re, json, hashlib
from pathlib import Path

pages_dir  = Path(sys.argv[1])
journals_dir = Path(sys.argv[2])
cypher_out = Path(sys.argv[3])
manifest   = Path(sys.argv[4])

synced = set(manifest.read_text().splitlines()) if manifest.exists() else set()

statements = []

def parse_frontmatter(text):
    fm = {}
    if text.startswith('---'):
        parts = text.split('---', 2)
        if len(parts) >= 3:
            for line in parts[1].splitlines():
                if ':' in line:
                    k, _, v = line.partition(':')
                    fm[k.strip()] = v.strip().strip('"')
    return fm

def extract_wikilinks(text):
    return re.findall(r'\[\[([^\]]+)\]\]', text)

def slug(name):
    return re.sub(r'[^a-z0-9-]', '-', name.lower()).strip('-')[:80]

def esc(s):
    return s.replace('\\', '\\\\').replace("'", "\\'").replace('"', '\\"')[:200]

new_synced = []

for md_file in list(pages_dir.glob('*.md')) + list(journals_dir.glob('*.md')):
    file_hash = hashlib.md5(md_file.read_bytes()).hexdigest()
    if file_hash in synced:
        continue

    content = md_file.read_text(encoding='utf-8', errors='ignore')
    fm = parse_frontmatter(content)
    links = extract_wikilinks(content)

    node_id = slug(md_file.stem)
    label   = 'Journal' if md_file.parent == journals_dir else 'Note'
    props = {
        'id':      node_id,
        'title':   md_file.stem.replace('-', ' ').title(),
        'date':    fm.get('date', ''),
        'use':     fm.get('use', ''),
        'topic':   fm.get('topic', ''),
        'src':     fm.get('src', ''),
        'proj':    fm.get('proj', ''),
        'summary': fm.get('summary', '')[:200],
    }
    prop_str = ', '.join(f'n.{k} = "{esc(v)}"' for k, v in props.items() if v)
    statements.append(f'MERGE (n:{label} {{id: "{node_id}"}}) SET {prop_str};')

    for link_text in links:
        target_id = slug(link_text)
        statements.append(
            f'MERGE (t:Note {{id: "{target_id}"}}) '
            f'ON CREATE SET t.title = "{esc(link_text)}", t.stub = true;'
        )
        statements.append(
            f'MATCH (a {{id: "{node_id}"}}), (b {{id: "{target_id}"}}) '
            f'MERGE (a)-[:LINKS_TO]->(b);'
        )

    new_synced.append(file_hash)

if statements:
    cypher_out.write_text('\n'.join(statements) + '\n', encoding='utf-8')
    print(f"[logseq-to-neo4j] Generated {len(statements)} Cypher statements → {cypher_out.name}")
    with open(manifest, 'a') as f:
        f.write('\n'.join(new_synced) + '\n')
else:
    print("[logseq-to-neo4j] Nothing new to sync")
    cypher_out.unlink(missing_ok=True)
PYEOF

# Step 2: Load generated Cypher into Neo4j via HTTP API
if [ ! -f "$CYPHER_FILE" ]; then
  echo "[logseq-to-neo4j] No new Cypher to load"
  exit 0
fi

python3 - "$CYPHER_FILE" "$HTTP_HOST" "$HTTP_PORT" "$NEO4J_USER" "$NEO4J_PASSWORD" <<'PYEOF'
import sys, json
import urllib.request, urllib.error
from base64 import b64encode
from pathlib import Path

cypher_file = Path(sys.argv[1])
host, port, user, pw = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
token = b64encode(f"{user}:{pw}".encode()).decode()

statements = [s.strip() for s in cypher_file.read_text().splitlines() if s.strip()]
batch = [{"statement": s} for s in statements]

payload = json.dumps({"statements": batch}).encode()
req = urllib.request.Request(
    f"http://{host}:{port}/db/neo4j/tx/commit",
    data=payload,
    headers={"Authorization": f"Basic {token}", "Content-Type": "application/json"}
)
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        resp = json.loads(r.read())
        errors = resp.get('errors', [])
        if errors:
            print(f"[logseq-to-neo4j] {len(errors)} errors: {errors[0]['message'][:200]}")
        else:
            print(f"[logseq-to-neo4j] Loaded {len(statements)} statements into Neo4j — OK")
except urllib.error.HTTPError as e:
    print(f"[logseq-to-neo4j] HTTP error {e.code}: {e.read().decode()[:300]}")
    sys.exit(1)
PYEOF

echo "$(date -Iseconds) NEO4J_SYNC $CYPHER_FILE" >> "$LOG_FILE"
echo "[logseq-to-neo4j] Sync complete"
