#!/usr/bin/env bash
# Pulls latest repo, restarts the API, and runs the full intake+process test.
# Run from ~/Cluad in Git Bash.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "=== Pulling latest ==="
git pull

echo ""
echo "=== Restarting API (killing old instance if running) ==="
# Kill any uvicorn already on 8001
powershell.exe -Command "Get-Process -Name python* | Where-Object { \$_.MainWindowTitle -eq '' } | Stop-Process -Force" 2>/dev/null || true
# Small pause then restart in background
sleep 1
bash start-api.sh &
API_PID=$!
echo "API starting (PID $API_PID)..."
sleep 4

echo ""
echo "=== Health check ==="
curl -sf http://localhost:8001/health | python3 -m json.tool

echo ""
echo "=== Running intake ==="
curl -sf -X POST http://localhost:8001/intake | python3 -m json.tool

echo ""
echo "=== Running process ==="
curl -sf -X POST http://localhost:8001/process | python3 -m json.tool

echo ""
echo "=== Vault contents ==="
echo "--- 00-inbox/transcripts ---"
ls ~/SecondBrain/00-inbox/transcripts/ 2>/dev/null || echo "(empty)"

echo "--- 01-logseq/pages ---"
ls ~/SecondBrain/01-logseq/pages/ 2>/dev/null || echo "(empty)"

echo "--- 01-logseq/journals ---"
ls ~/SecondBrain/01-logseq/journals/ 2>/dev/null || echo "(empty)"

echo ""
echo "--- First page content (if any) ---"
first=$(ls ~/SecondBrain/01-logseq/pages/*.md 2>/dev/null | head -1 || true)
[ -n "$first" ] && head -25 "$first" || echo "(no .md pages yet)"

echo ""
echo "=== Done ==="
