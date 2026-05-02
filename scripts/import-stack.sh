#!/usr/bin/env bash
# Restores the stack on a new PC from an export folder.
# Run this from inside the stack-export/ folder on the new PC.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "=== Importing The System stack ==="
echo ""

# Check Docker is installed
if ! command -v docker &>/dev/null; then
  echo "ERROR: Docker not installed. Install Docker Desktop first."
  exit 1
fi

# Pull all images first
echo "[1/5] Pulling Docker images..."
docker-compose pull

# Restore vault data
echo "[2/5] Restoring vault data..."
docker run --rm \
  -v cluad_vault_data:/data \
  -v "$(pwd)":/backup \
  alpine sh -c "cd /data && tar xzf /backup/vault_data.tar.gz"

# Restore n8n
echo "[3/5] Restoring n8n workflows..."
docker run --rm \
  -v cluad_n8n_data:/data \
  -v "$(pwd)":/backup \
  alpine sh -c "cd /data && tar xzf /backup/n8n_data.tar.gz"

# Restore Neo4j
echo "[4/5] Restoring Neo4j graph..."
docker run --rm \
  -v cluad_neo4j_data:/data \
  -v "$(pwd)":/backup \
  alpine sh -c "cd /data && tar xzf /backup/neo4j_data.tar.gz"

# Start everything
echo "[5/5] Starting all services..."
docker-compose up -d

echo ""
echo "=== Import complete ==="
echo ""
echo "Services:"
echo "  Pipeline API  → http://localhost:8001"
echo "  n8n           → http://localhost:5678"
echo "  Neo4j         → http://localhost:7474"
echo "  Ollama        → http://localhost:11434"
echo ""
echo "Next: run 'docker exec brain-ollama ollama pull llama3.2:3b' to restore AI models"
