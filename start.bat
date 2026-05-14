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

REM Notion connectivity is checked by the agent at startup.
REM Make sure NOTION_API_KEY is set in .env before proceeding.

REM Activate venv and launch Chainlit
echo Starting agent at http://localhost:8000
echo.

call venv\Scripts\activate.bat
chainlit run agent.py --port 8000

pause
