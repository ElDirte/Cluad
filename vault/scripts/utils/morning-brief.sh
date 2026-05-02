#!/usr/bin/env bash
# Prints a session-start brief: last decisions, inbox counts, Neo4j stats.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
[ -f "$VAULT_ROOT/.env" ] && source "$VAULT_ROOT/.env"

INBOX="$VAULT_ROOT/00-inbox"
DB="$VAULT_ROOT/data/decisions.db"
NEO4J_HEALTH_SCRIPT="$(dirname "$SCRIPT_DIR")/sync/neo4j-health.sh"

TODAY=$(date '+%Y-%m-%d')
echo ""
echo "=== SECOND BRAIN BRIEF: $TODAY ==="
echo ""

# Last Eagle agent session from decisions.db
if [ -f "$DB" ]; then
  python3 - "$DB" <<'PYEOF'
import sys, sqlite3
from pathlib import Path

db_path = sys.argv[1]
try:
    con = sqlite3.connect(db_path)
    cur = con.cursor()

    # Last session summary
    cur.execute("SELECT created_at, summary FROM sessions ORDER BY created_at DESC LIMIT 1")
    row = cur.fetchone()
    if row:
        print(f"Last Eagle session : {row[0][:16]}  —  {row[1] or '(no summary)'}")
    else:
        print("Last Eagle session : none recorded yet")

    # Recent decisions
    cur.execute("""
        SELECT COUNT(*) FROM decisions
        WHERE date(created_at) = date('now')
    """)
    today_count = cur.fetchone()[0]

    cur.execute("""
        SELECT COUNT(*) FROM decisions WHERE approved = 1
    """)
    total_approved = cur.fetchone()[0]

    cur.execute("""
        SELECT original_name, final_tags, approved
        FROM decisions ORDER BY created_at DESC LIMIT 5
    """)
    recent = cur.fetchall()

    print(f"Decisions today    : {today_count}  |  Total approved: {total_approved}")
    if recent:
        print("Recent decisions   :")
        for name, tags, approved in recent:
            status = "✓" if approved == 1 else ("✗" if approved == 0 else "~")
            print(f"  {status} {(name or '')[:40]:40s}  {(tags or '')[:30]}")
    con.close()
except Exception as e:
    print(f"decisions.db       : could not read ({e})")
PYEOF
else
  echo "decisions.db       : not found (run the Cluad agent first)"
fi

echo ""

# Inbox counts
echo "Inbox status       :"
for subdir in claude-sessions gmail transcripts agent-logs; do
  count=$(find "$INBOX/$subdir" -name "*.md" 2>/dev/null | wc -l)
  tagged=$(grep -rl "^tagged: true" "$INBOX/$subdir" 2>/dev/null | wc -l)
  untagged=$((count - tagged))
  printf "  %-20s %d files  (%d untagged)\n" "$subdir" "$count" "$untagged"
done

echo ""

# Logseq page count
pages=$(find "$VAULT_ROOT/01-logseq/pages" -name "*.md" 2>/dev/null | wc -l)
journals=$(find "$VAULT_ROOT/01-logseq/journals" -name "*.md" 2>/dev/null | wc -l)
echo "Logseq vault       : $pages pages  |  $journals journal entries"

echo ""

# Neo4j (non-blocking)
if bash "$NEO4J_HEALTH_SCRIPT" 2>/dev/null; then
  true
else
  echo "Neo4j              : offline"
fi

echo ""
echo "Commands: ./cns.sh intake | process | sync | all"
echo "========================================="
echo ""
