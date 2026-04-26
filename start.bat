@echo off
title The System - Agent

echo.
echo === The System ===
echo.

REM Check .env exists
if not exist ".env" (
    echo ERROR: .env file not found.
    echo Run setup\setup.ps1 first.
    pause
    exit /b 1
)

REM Load .env into environment using PowerShell
FOR /F "tokens=*" %%i IN ('PowerShell -Command "Get-Content .env | Where-Object { $_ -notmatch '^#' -and $_ -match '=' } | ForEach-Object { $_ }"') DO (
    SET "%%i"
)

REM Check Eagle is running
curl -s http://localhost:41595/api/application/info >nul 2>&1
if %errorlevel% neq 0 (
    echo WARNING: Eagle does not appear to be running.
    echo Open Eagle, then press any key to continue...
    pause >nul
)

REM Activate venv and launch Chainlit
echo Starting agent at http://localhost:8000
echo.

call venv\Scripts\activate.bat
chainlit run agent.py --port 8000

pause
