#!/usr/bin/env bash
# Applies YAML frontmatter tags to untagged inbox items using Ollama (local) or Claude API (fallback)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
[ -f "$VAULT_ROOT/.env" ] && source "$VAULT_ROOT/.env"

INBOX="$VAULT_ROOT/00-inbox"
LOG_FILE="$VAULT_ROOT/logs/intake.log"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_TAG_MODEL:-llama3.2:3b}"
ANTHROPIC_KEY="${ANTHROPIC_API_KEY:-}"
AUTO_THRESHOLD="${AUTO_APPLY_THRESHOLD:-0.90}"
REVIEW_THRESHOLD="${REVIEW_THRESHOLD:-0.70}"

mkdir -p "$VAULT_ROOT/logs"

# Check Ollama availability
OLLAMA_OK=false
if curl -sf "$OLLAMA_URL/api/tags" -o /dev/null 2>/dev/null; then
  OLLAMA_OK=true
fi

tag_with_ollama() {
  local content="$1"
  curl -sf "$OLLAMA_URL/api/generate" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "
import json, sys
prompt = '''You are a metadata tagger for a personal knowledge system.

Given a document, output ONLY a JSON object with these fields:
{
  \"use\": one of [design-idea, ai-reference, memory-trigger, reminder, project-source, archive, research, inspiration, reference],
  \"topic\": one of [art, tech, ai, work, family, garden, personal, fandom, photography, health, home],
  \"src\": one of [screenshot, camera, web-save, scan, generated, export, transcript, email],
  \"status\": \"staged\",
  \"q\": one of [keep, maybe, low],
  \"proj\": one of [archer, grophoto, 26-org, work, garden, none],
  \"confidence\": float 0.0-1.0,
  \"summary\": one sentence describing this document
}

Document:
''' + sys.argv[1][:1500]
print(json.dumps({'model': '$OLLAMA_MODEL', 'prompt': prompt, 'stream': False}))
" "$content")" 2>/dev/null | python3 -c "
import sys, json
resp = json.load(sys.stdin)
print(resp.get('response',''))
" 2>/dev/null
}

tag_with_claude() {
  local content="$1"
  python3 - "$content" "$ANTHROPIC_KEY" <<'PYEOF'
import sys, json
import urllib.request, urllib.error

content, api_key = sys.argv[1][:2000], sys.argv[2]
if not api_key:
    print("{}")
    sys.exit(0)

prompt = f"""You are a metadata tagger for a personal knowledge system.

Given a document, output ONLY a JSON object with these fields:
{{
  "use": one of [design-idea, ai-reference, memory-trigger, reminder, project-source, archive, research, inspiration, reference],
  "topic": one of [art, tech, ai, work, family, garden, personal, fandom, photography, health, home],
  "src": one of [screenshot, camera, web-save, scan, generated, export, transcript, email],
  "status": "staged",
  "q": one of [keep, maybe, low],
  "proj": one of [archer, grophoto, 26-org, work, garden, none],
  "confidence": float 0.0-1.0,
  "summary": one sentence describing this document
}}

Document:
{content}"""

payload = json.dumps({
    "model": "claude-haiku-4-5-20251001",
    "max_tokens": 256,
    "messages": [{"role": "user", "content": prompt}]
}).encode()

req = urllib.request.Request(
    "https://api.anthropic.com/v1/messages",
    data=payload,
    headers={
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
    }
)
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        resp = json.loads(r.read())
        print(resp["content"][0]["text"])
except Exception as e:
    print("{}")
PYEOF
}

extract_json() {
  python3 -c "
import sys, json, re
text = sys.stdin.read()
# Try direct parse
try:
    obj = json.loads(text)
    print(json.dumps(obj))
    sys.exit(0)
except:
    pass
# Try finding JSON block
m = re.search(r'\{[^{}]*\}', text, re.DOTALL)
if m:
    try:
        obj = json.loads(m.group())
        print(json.dumps(obj))
        sys.exit(0)
    except:
        pass
print('{}')
"
}

update_frontmatter() {
  local file="$1"
  local tags_json="$2"

  python3 - "$file" "$tags_json" <<'PYEOF'
import sys, json, re
from pathlib import Path

filepath = Path(sys.argv[1])
tags = json.loads(sys.argv[2])
if not tags:
    sys.exit(0)

content = filepath.read_text(encoding='utf-8', errors='ignore')

# Build new frontmatter lines
lines = []
for key in ['use', 'topic', 'src', 'status', 'q']:
    val = tags.get(key, '')
    if val and val != 'none':
        lines.append(f"{key}: {val}")
proj = tags.get('proj', 'none')
if proj and proj != 'none':
    lines.append(f"proj: {proj}")
conf = tags.get('confidence', 0)
lines.append(f"confidence: {conf}")
summary = tags.get('summary', '')
if summary:
    lines.append(f"summary: \"{summary[:120]}\"")
lines.append("tagged: true")

new_fm = '\n'.join(lines)

# Replace or insert frontmatter
if content.startswith('---'):
    # Update existing frontmatter block
    parts = content.split('---', 2)
    if len(parts) >= 3:
        existing = parts[1].strip()
        # Remove keys we're about to set
        kept = [l for l in existing.splitlines()
                if not any(l.startswith(k+':') for k in ['use','topic','src','status','q','proj','confidence','summary','tagged'])]
        merged = '\n'.join(kept).strip()
        new_block = (merged + '\n' + new_fm).strip() if merged else new_fm
        content = f"---\n{new_block}\n---{parts[2]}"
    else:
        content = f"---\n{new_fm}\n---\n\n{content}"
else:
    content = f"---\n{new_fm}\n---\n\n{content}"

filepath.write_text(content, encoding='utf-8')
print(f"[tag-agent] Tagged: {filepath.name}")
PYEOF
}

processed=0

find "$INBOX" -name "*.md" | while read -r file; do
  # Skip already tagged files
  if grep -q "^tagged: true" "$file" 2>/dev/null; then
    continue
  fi

  content=$(cat "$file" 2>/dev/null | head -200 | tr -d '\000-\010\013\014\016-\037')

  if [ "$OLLAMA_OK" = true ]; then
    raw=$(tag_with_ollama "$content")
  else
    raw=$(tag_with_claude "$content")
  fi

  tags_json=$(echo "$raw" | extract_json)
  confidence=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('confidence',0))" "$tags_json" 2>/dev/null || echo "0")

  # Confidence gate
  conf_num=$(python3 -c "print(float('$confidence') >= float('$REVIEW_THRESHOLD'))")
  if [ "$conf_num" = "False" ]; then
    echo "[tag-agent] LOW CONFIDENCE ($confidence) — flagging: $(basename "$file")"
    python3 -c "
from pathlib import Path
p = Path('$file')
c = p.read_text()
if not c.startswith('---'):
    p.write_text(f'---\nstatus: needs-action\nflag: low-confidence\n---\n\n{c}')
"
    continue
  fi

  update_frontmatter "$file" "$tags_json"
  echo "$(date -Iseconds) TAG $(basename "$file") confidence=$confidence" >> "$LOG_FILE"
  processed=$((processed + 1))
done

echo "[tag-agent] Done. Backend: $([ "$OLLAMA_OK" = true ] && echo "Ollama ($OLLAMA_MODEL)" || echo "Claude API fallback")"
