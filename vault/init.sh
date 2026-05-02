#!/usr/bin/env bash
# Bootstraps the Second Brain vault at the given path.
# Usage: ./init.sh [path]   (defaults to ~/SecondBrain)

set -euo pipefail

VAULT_ROOT="${1:-$HOME/SecondBrain}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUAD_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Initializing Second Brain vault at: $VAULT_ROOT ==="

# Create full directory tree
dirs=(
  "00-inbox/claude-sessions"
  "00-inbox/gmail"
  "00-inbox/transcripts"
  "00-inbox/agent-logs"
  "01-logseq/pages"
  "01-logseq/journals"
  "01-logseq/assets"
  "01-logseq/logseq"
  "02-neo4j/exports"
  "02-neo4j/schemas"
  "02-neo4j/queries"
  "03-canvas/snapshots"
  "04-notion/exports"
  "scripts"
  "data"
  "logs"
)

for d in "${dirs[@]}"; do
  mkdir -p "$VAULT_ROOT/$d"
done
echo "[ok] Directory tree created"

# Copy scripts from repo into vault
cp -r "$SCRIPT_DIR/scripts/"* "$VAULT_ROOT/scripts/"
cp "$SCRIPT_DIR/.env.example" "$VAULT_ROOT/.env.example"
cp "$SCRIPT_DIR/.gitignore" "$VAULT_ROOT/.gitignore"
chmod +x "$VAULT_ROOT/scripts/cns.sh"
chmod +x "$VAULT_ROOT/scripts/"**/*.sh
echo "[ok] Scripts copied and made executable"

# Write VAULT_ROOT into .env if not already present
ENV_FILE="$VAULT_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
  cp "$VAULT_ROOT/.env.example" "$ENV_FILE"
  sed -i "s|VAULT_ROOT=.*|VAULT_ROOT=$VAULT_ROOT|" "$ENV_FILE"
  echo "[ok] .env created — edit with your API keys"
else
  echo "[skip] .env already exists"
fi

# Symlink decisions.db from Cluad repo
DB_SOURCE="$CLUAD_DIR/data/decisions.db"
DB_LINK="$VAULT_ROOT/data/decisions.db"
if [ ! -L "$DB_LINK" ]; then
  if [ -f "$DB_SOURCE" ]; then
    ln -s "$DB_SOURCE" "$DB_LINK"
    echo "[ok] decisions.db symlinked from Cluad repo"
  else
    touch "$DB_SOURCE"
    ln -s "$DB_SOURCE" "$DB_LINK"
    echo "[ok] decisions.db created and symlinked (empty — start Cluad agent to populate)"
  fi
else
  echo "[skip] decisions.db symlink already exists"
fi

# Logseq config stub
LOGSEQ_CONFIG="$VAULT_ROOT/01-logseq/logseq/config.edn"
if [ ! -f "$LOGSEQ_CONFIG" ]; then
  cat > "$LOGSEQ_CONFIG" <<'EOF'
{:meta/version 1
 :preferred-format :markdown
 :journal/page-title-format "yyyy-MM-dd"
 :journal/file-name-format "yyyy_MM_dd"
 :feature/enable-journals? true
 :feature/enable-whiteboards? false
 :ui/enable-tooltip? true}
EOF
  echo "[ok] Logseq config.edn written"
fi

# Neo4j schema stub
NEO4J_SCHEMA="$VAULT_ROOT/02-neo4j/schemas/node-types.cypher"
if [ ! -f "$NEO4J_SCHEMA" ]; then
  cat > "$NEO4J_SCHEMA" <<'EOF'
// Node types for Kenneth's Second Brain
// Run once after connecting Neo4j

CREATE CONSTRAINT note_id IF NOT EXISTS
  FOR (n:Note) REQUIRE n.id IS UNIQUE;

CREATE CONSTRAINT person_name IF NOT EXISTS
  FOR (p:Person) REQUIRE p.name IS UNIQUE;

CREATE CONSTRAINT project_slug IF NOT EXISTS
  FOR (pr:Project) REQUIRE pr.slug IS UNIQUE;

// Relationship types: LINKS_TO, MENTIONS, TAGGED_WITH, PART_OF
EOF
  echo "[ok] Neo4j schema stub written"
fi

# Git init vault
if [ ! -d "$VAULT_ROOT/.git" ]; then
  git -C "$VAULT_ROOT" init -q
  git -C "$VAULT_ROOT" add .
  git -C "$VAULT_ROOT" commit -q -m "init: second brain vault structure"
  echo "[ok] Git repository initialized"
else
  echo "[skip] Git already initialized"
fi

echo ""
echo "=== Vault ready at $VAULT_ROOT ==="
echo ""
echo "Next steps:"
echo "  1. Edit $VAULT_ROOT/.env  (add ANTHROPIC_API_KEY, NEO4J_PASSWORD, etc.)"
echo "  2. Open $VAULT_ROOT/01-logseq in Logseq desktop"
echo "  3. Run: $VAULT_ROOT/scripts/cns.sh brief"
echo "  4. Run: $VAULT_ROOT/scripts/cns.sh all   (full intake pipeline)"
