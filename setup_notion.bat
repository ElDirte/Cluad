@echo off
title Cluad Setup — Notion File Catalog
echo.
echo === Cluad Setup ===
echo.

REM ── Check we're in the right folder ─────────────────────────────────────────
if not exist "config.py" (
    echo ERROR: Run this from C:\Users\Allen Watts\Cluad\
    pause
    exit /b 1
)

REM ── Activate venv ────────────────────────────────────────────────────────────
if not exist "venv\Scripts\activate.bat" (
    echo ERROR: venv not found. Run setup\setup.ps1 first.
    pause
    exit /b 1
)
call venv\Scripts\activate.bat

REM ── Install new dependency ───────────────────────────────────────────────────
echo Installing notion-client...
pip install "notion-client>=2.0.0" --quiet
echo Done.
echo.

REM ── Create .env if it doesn't exist ─────────────────────────────────────────
if exist ".env" (
    echo .env already exists — skipping creation. Edit it manually if needed.
    goto :check_key
)

echo Creating .env from template...
(
    echo ANTHROPIC_API_KEY=
    echo NOTION_API_KEY=
    echo FILE_CATALOG_DB_ID=9b6cec19-5e88-4369-ba46-d90283d4c61e
    echo OLLAMA_API_URL=http://localhost:11434
    echo MEM0_API_KEY=
    echo AGENT_USER_ID=kenneth
    echo INTAKE_FOLDERS=C:\Users\Allen Watts\Pictures
    echo INTAKE_BATCH_SIZE=15
    echo AUTO_SUGGEST_THRESHOLD=0.90
) > .env
echo .env created.
echo.

:check_key
REM ── Check for required keys ──────────────────────────────────────────────────
findstr /C:"ANTHROPIC_API_KEY=sk-ant" .env >nul 2>&1
if errorlevel 1 (
    echo NOTICE: ANTHROPIC_API_KEY not set in .env
    echo   Add it manually: notepad .env
    echo.
)

findstr /C:"NOTION_API_KEY=secret_" .env >nul 2>&1
if errorlevel 1 (
    echo NOTICE: NOTION_API_KEY not set in .env
    echo   1. Go to notion.so/my-integrations
    echo   2. Create integration, copy the secret_ token
    echo   3. Run: notepad .env  and paste it in
    echo   4. In Notion, share NEXUS Command Center page with your integration
    echo.
)

echo Setup complete. Run start.bat to launch the agent.
echo.
pause
