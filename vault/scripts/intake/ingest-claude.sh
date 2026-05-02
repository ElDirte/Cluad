#!/usr/bin/env bash
# Ingests Claude Code session transcripts from ~/.claude/projects into 00-inbox/claude-sessions/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
[ -f "$VAULT_ROOT/.env" ] && source "$VAULT_ROOT/.env"

SRC_DIR="${CLAUDE_SESSIONS_DIR:-$HOME/.claude/projects}"
DEST_DIR="$VAULT_ROOT/00-inbox/claude-sessions"
LOG_FILE="$VAULT_ROOT/logs/intake.log"
MANIFEST="$VAULT_ROOT/data/claude-ingested.txt"

mkdir -p "$DEST_DIR" "$VAULT_ROOT/logs" "$VAULT_ROOT/data"
touch "$MANIFEST"

ingested=0

# Claude stores sessions as .jsonl files under ~/.claude/projects/<project-hash>/
find "$SRC_DIR" -name "*.jsonl" 2>/dev/null | while read -r session_file; do
  file_hash=$(md5sum "$session_file" | cut -d' ' -f1)

  # Skip already ingested files
  if grep -qF "$file_hash" "$MANIFEST" 2>/dev/null; then
    continue
  fi

  # Build a human-readable markdown file from the session
  session_date=$(date -r "$session_file" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
  session_id=$(basename "$(dirname "$session_file")")
  out_file="$DEST_DIR/${session_date}_claude-session_${session_id:0:8}.md"

  {
    echo "---"
    echo "src: claude-session"
    echo "date: $session_date"
    echo "session_id: $session_id"
    echo "status: staged"
    echo "---"
    echo ""
    echo "# Claude Session — $session_date"
    echo ""

    # Extract human/assistant turns from jsonl
    python3 -c "
import sys, json
for line in open(sys.argv[1]):
    try:
        obj = json.loads(line)
        role = obj.get('type', obj.get('role', ''))
        if role in ('human', 'user'):
            msg = obj.get('message', obj.get('content', ''))
            if isinstance(msg, list):
                msg = ' '.join(b.get('text','') for b in msg if isinstance(b,dict))
            print(f'**You:** {str(msg)[:500]}')
            print()
        elif role in ('assistant',):
            msg = obj.get('message', obj.get('content', ''))
            if isinstance(msg, list):
                msg = ' '.join(b.get('text','') for b in msg if isinstance(b,dict))
            print(f'**Claude:** {str(msg)[:500]}')
            print()
    except:
        pass
" "$session_file" 2>/dev/null || echo "_[Could not parse session content]_"

  } > "$out_file"

  echo "$file_hash  $session_file" >> "$MANIFEST"
  echo "$(date -Iseconds) INGEST claude-session $out_file" >> "$LOG_FILE"
  ingested=$((ingested + 1))
  echo "[ingest-claude] $session_date — $(basename "$out_file")"
done

echo "[ingest-claude] Done. New sessions ingested from $SRC_DIR"
