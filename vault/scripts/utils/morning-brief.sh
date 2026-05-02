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

db_path = sys.argv[1]
try:
    con = sqlite3.connect(db_path)
    cur = con.cursor()

    # Introspect actual column names so we're schema-agnostic
    def col_names(table):
        try:
            cur.execute(f"PRAGMA table_info({table})")
            return [r[1] for r in cur.fetchall()]
        except Exception:
            return []

    s_cols = col_names("sessions")
    d_cols = col_names("decisions")

    if not s_cols:
        print("Last Eagle session : no sessions table yet — start the Cluad agent first")
    else:
        ts_col  = "ts" if "ts" in s_cols else ("created_at" if "created_at" in s_cols else s_cols[1])
        sum_col = "summary" if "summary" in s_cols else s_cols[-1]
        cur.execute(f"SELECT {ts_col}, {sum_col} FROM sessions ORDER BY {ts_col} DESC LIMIT 1")
        row = cur.fetchone()
        if row:
            print(f"Last Eagle session : {str(row[0])[:16]}  —  {row[1] or '(no summary)'}")
        else:
            print("Last Eagle session : none recorded yet")

    if not d_cols:
        print("Decisions          : no decisions table yet")
    else:
        ts_col   = "ts" if "ts" in d_cols else ("created_at" if "created_at" in d_cols else d_cols[1])
        name_col = "original" if "original" in d_cols else ("original_name" if "original_name" in d_cols else d_cols[2])
        tags_col = "final_tags" if "final_tags" in d_cols else d_cols[5]

        cur.execute(f"SELECT COUNT(*) FROM decisions WHERE date({ts_col}) = date('now')")
        today_count = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM decisions WHERE approved = 1")
        total_approved = cur.fetchone()[0]
        cur.execute(f"SELECT {name_col}, {tags_col}, approved FROM decisions ORDER BY {ts_col} DESC LIMIT 5")
        recent = cur.fetchall()

        print(f"Decisions today    : {today_count}  |  Total approved: {total_approved}")
        if recent:
            print("Recent decisions   :")
            for name, tags, approved in recent:
                status = "✓" if approved == 1 else ("✗" if approved == 0 else "~")
                print(f"  {status} {str(name or '')[:40]:40s}  {str(tags or '')[:30]}")

    con.close()
except Exception as e:
    print(f"decisions.db       : could not read ({e})")
PYEOF
else
  echo "decisions.db       : not found — start the Cluad agent to populate it"
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
