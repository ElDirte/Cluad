#!/usr/bin/env bash
# Starts the Second Brain Pipeline API on port 8001 (Git Bash / Linux / WSL)

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ ! -f .env ]; then
  echo "ERROR: .env not found. Copy .env.example and add your API keys."
  exit 1
fi

# Activate venv — works on both Windows Git Bash and Linux/WSL
if [ -f venv/Scripts/activate ]; then
  source venv/Scripts/activate        # Windows Git Bash
elif [ -f venv/bin/activate ]; then
  source venv/bin/activate            # Linux / WSL
else
  echo "ERROR: venv not found. Run setup/setup.ps1 (Windows) or: python3 -m venv venv && pip install -r requirements.txt"
  exit 1
fi

echo "Starting Second Brain Pipeline API on http://localhost:8001 ..."
uvicorn api:app --host 0.0.0.0 --port 8001 --reload
