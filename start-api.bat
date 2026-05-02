@echo off
REM Starts the Second Brain Pipeline API on port 8001
REM n8n calls this via http://host.docker.internal:8001

if not exist .env (
    echo ERROR: .env file not found. Copy .env.example and add your API keys.
    pause
    exit /b 1
)

call venv\Scripts\activate.bat 2>nul || (
    echo ERROR: venv not found. Run setup\setup.ps1 first.
    pause
    exit /b 1
)

echo Starting Second Brain Pipeline API on http://localhost:8001 ...
uvicorn api:app --host 0.0.0.0 --port 8001 --reload
