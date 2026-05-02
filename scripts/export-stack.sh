#!/usr/bin/env bash
# Packages the entire stack for moving to a new PC.
# Output: ./stack-export/  (copy this whole folder to the new PC)

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

EXPORT_DIR="./stack-export"
mkdir -p "$EXPORT_DIR"

echo "=== Exporting The System stack ==="
echo ""

# Stop containers gracefully
echo "[1/5] Stopping containers..."
docker-compose down

# Export each named volume as a tar archive
echo "[2/5] Exporting vault data..."
docker run --rm \
  -v cluad_vault_data:/data \
  -v "$(pwd)/$EXPORT_DIR":/backup \
  alpine tar czf /backup/vault_data.tar.gz -C /data .

echo "[3/5] Exporting n8n workflows and credentials..."
docker run --rm \
  -v cluad_n8n_data:/data \
  -v "$(pwd)/$EXPORT_DIR":/backup \
  alpine tar czf /backup/n8n_data.tar.gz -C /data .

echo "[4/5] Exporting Neo4j graph..."
docker run --rm \
  -v cluad_neo4j_data:/data \
  -v "$(pwd)/$EXPORT_DIR":/backup \
  alpine tar czf /backup/neo4j_data.tar.gz -C /data .

echo "[5/5] Copying config files..."
cp .env "$EXPORT_DIR/.env" 2>/dev/null || echo "  (no .env found — you'll need to recreate it on the new PC)"
cp docker-compose.yml "$EXPORT_DIR/docker-compose.yml"

echo ""
echo "=== Export complete ==="
echo ""
echo "To move to new PC:"
echo "  1. Copy the entire '$EXPORT_DIR' folder to the new PC"
echo "  2. Install Docker on the new PC"
echo "  3. Run: bash import-stack.sh"
echo ""
du -sh "$EXPORT_DIR"
