#!/usr/bin/env bash
# Checks Neo4j connectivity and prints basic graph stats.
# Exits non-zero if Neo4j is unreachable (used by cns.sh to gate the sync step).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
[ -f "$VAULT_ROOT/.env" ] && source "$VAULT_ROOT/.env"

NEO4J_URI="${NEO4J_URI:-bolt://localhost:7687}"
NEO4J_USER="${NEO4J_USER:-neo4j}"
NEO4J_PASSWORD="${NEO4J_PASSWORD:-changeme}"

# Derive HTTP port from bolt URI (bolt:7687 → http:7474)
HTTP_HOST=$(echo "$NEO4J_URI" | sed 's|bolt://||' | cut -d: -f1)
HTTP_PORT=7474

if ! curl -sf --max-time 3 "http://$HTTP_HOST:$HTTP_PORT" -o /dev/null 2>/dev/null; then
  echo "[neo4j-health] UNAVAILABLE — Neo4j not responding at http://$HTTP_HOST:$HTTP_PORT"
  echo "[neo4j-health] Start Neo4j: docker run -d -p7474:7474 -p7687:7687 -e NEO4J_AUTH=${NEO4J_USER}/${NEO4J_PASSWORD} neo4j:latest"
  exit 1
fi

# Query node + relationship counts via HTTP API
python3 - "$HTTP_HOST" "$HTTP_PORT" "$NEO4J_USER" "$NEO4J_PASSWORD" <<'PYEOF'
import sys, json
import urllib.request, urllib.error
from base64 import b64encode

host, port, user, pw = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
token = b64encode(f"{user}:{pw}".encode()).decode()

def query(cypher):
    payload = json.dumps({"statements": [{"statement": cypher}]}).encode()
    req = urllib.request.Request(
        f"http://{host}:{port}/db/neo4j/tx/commit",
        data=payload,
        headers={"Authorization": f"Basic {token}", "Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.loads(r.read())

try:
    nodes = query("MATCH (n) RETURN count(n) AS c")["results"][0]["data"][0]["row"][0]
    rels  = query("MATCH ()-[r]->() RETURN count(r) AS c")["results"][0]["data"][0]["row"][0]
    labels = query("CALL db.labels() YIELD label RETURN collect(label) AS l")["results"][0]["data"][0]["row"][0]
    print(f"[neo4j-health] OK — {nodes} nodes | {rels} relationships | labels: {', '.join(labels) or 'none'}")
except Exception as e:
    print(f"[neo4j-health] Connected but query failed: {e}")
    sys.exit(1)
PYEOF
