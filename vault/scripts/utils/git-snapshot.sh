#!/usr/bin/env bash
# Auto-commits the vault state with a timestamped message.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
[ -f "$VAULT_ROOT/.env" ] && source "$VAULT_ROOT/.env"

cd "$VAULT_ROOT"

if [ ! -d ".git" ]; then
  echo "[git-snapshot] No git repo at $VAULT_ROOT — run init.sh first"
  exit 1
fi

# Stage all vault changes (exclude .gitignored paths like data/, logs/, .env)
git add -A

if git diff --cached --quiet; then
  echo "[git-snapshot] Nothing to commit — vault is clean"
  exit 0
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PAGE_COUNT=$(find 01-logseq/pages -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
JOURNAL_COUNT=$(find 01-logseq/journals -name "*.md" 2>/dev/null | wc -l | tr -d ' ')

git commit -m "snapshot: $TIMESTAMP — ${PAGE_COUNT}p ${JOURNAL_COUNT}j"
echo "[git-snapshot] Committed: $TIMESTAMP ($PAGE_COUNT pages, $JOURNAL_COUNT journals)"
