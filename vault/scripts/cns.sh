#!/usr/bin/env bash
# Central Nervous System — master dispatcher
# Usage: ./cns.sh [brief|intake|process|sync|snapshot|all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load env
[ -f "$VAULT_ROOT/.env" ] && source "$VAULT_ROOT/.env"
export VAULT_ROOT

log() { echo "[$(date '+%H:%M:%S')] $*"; }

run_brief()    { bash "$SCRIPT_DIR/utils/morning-brief.sh"; }
run_intake()   {
  log "--- INTAKE ---"
  bash "$SCRIPT_DIR/intake/ingest-claude.sh"
  bash "$SCRIPT_DIR/intake/ingest-transcripts.sh"
  bash "$SCRIPT_DIR/intake/ingest-gmail.sh"
}
run_process()  {
  log "--- PROCESS ---"
  bash "$SCRIPT_DIR/process/tag-agent.sh"
  bash "$SCRIPT_DIR/process/route-to-logseq.sh"
}
run_sync()     {
  log "--- SYNC ---"
  bash "$SCRIPT_DIR/sync/neo4j-health.sh" && bash "$SCRIPT_DIR/sync/logseq-to-neo4j.sh" || log "[warn] Neo4j unavailable — skipping graph sync"
}
run_snapshot() { bash "$SCRIPT_DIR/utils/git-snapshot.sh"; }

CMD="${1:-brief}"

case "$CMD" in
  brief)    run_brief ;;
  intake)   run_intake ;;
  process)  run_process ;;
  sync)     run_sync ;;
  snapshot) run_snapshot ;;
  all)
    run_brief
    run_intake
    run_process
    run_sync
    run_snapshot
    log "=== Full pipeline complete ==="
    ;;
  *)
    echo "Usage: $0 [brief|intake|process|sync|snapshot|all]"
    exit 1
    ;;
esac
