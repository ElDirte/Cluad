# The System — Windows Setup Script
# Right-click this file and choose "Run with PowerShell"
# Or open PowerShell and run: .\setup\setup.ps1

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path $PSScriptRoot -Parent

Write-Host "`n=== The System — Setup ===" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot`n"

# ── 1. Python check ────────────────────────────────────────────────────────────
Write-Host "Checking Python..." -ForegroundColor Yellow
try {
    $pyVersion = python --version 2>&1
    Write-Host "  Found: $pyVersion" -ForegroundColor Green
} catch {
    Write-Host "  Python not found. Download from https://python.org (3.11 or newer)" -ForegroundColor Red
    Write-Host "  IMPORTANT: Check 'Add Python to PATH' during install" -ForegroundColor Red
    Start-Process "https://www.python.org/downloads/"
    Read-Host "Press Enter after installing Python, then re-run this script"
    exit 1
}

# ── 2. Create virtual environment ─────────────────────────────────────────────
Write-Host "`nCreating Python virtual environment..." -ForegroundColor Yellow
Set-Location $ProjectRoot

if (-not (Test-Path "venv")) {
    python -m venv venv
    Write-Host "  Created venv" -ForegroundColor Green
} else {
    Write-Host "  venv already exists" -ForegroundColor Green
}

# ── 3. Install dependencies ────────────────────────────────────────────────────
Write-Host "`nInstalling Python packages..." -ForegroundColor Yellow
& "$ProjectRoot\venv\Scripts\pip.exe" install --upgrade pip -q
& "$ProjectRoot\venv\Scripts\pip.exe" install -r requirements.txt
Write-Host "  Packages installed" -ForegroundColor Green

# ── 4. .env file ──────────────────────────────────────────────────────────────
Write-Host "`nChecking .env file..." -ForegroundColor Yellow
if (-not (Test-Path "$ProjectRoot\.env")) {
    Copy-Item "$ProjectRoot\.env.example" "$ProjectRoot\.env"
    Write-Host "  Created .env from template" -ForegroundColor Green
    Write-Host "  ACTION NEEDED: Open .env and add your ANTHROPIC_API_KEY" -ForegroundColor Magenta
    notepad "$ProjectRoot\.env"
} else {
    Write-Host "  .env already exists" -ForegroundColor Green
}

# ── 5. Ollama check ────────────────────────────────────────────────────────────
Write-Host "`nChecking Ollama..." -ForegroundColor Yellow
try {
    $ollamaCheck = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 3
    Write-Host "  Ollama is running" -ForegroundColor Green

    Write-Host "  Pulling vision model (llava:7b — ~4GB, first time only)..."
    ollama pull llava:7b
    Write-Host "  Pulling fast model (llama3.2:3b — ~2GB, first time only)..."
    ollama pull llama3.2:3b
    Write-Host "  Models ready" -ForegroundColor Green
} catch {
    Write-Host "  Ollama not running or not installed" -ForegroundColor Yellow
    Write-Host "  Download from https://ollama.com and install, then re-run this script" -ForegroundColor Yellow
    Write-Host "  Skipping model pull for now (agent will use Claude API only until Ollama is set up)" -ForegroundColor Yellow
}

# ── 6. Docker / n8n ────────────────────────────────────────────────────────────
Write-Host "`nChecking Docker..." -ForegroundColor Yellow
try {
    $dockerCheck = docker ps 2>&1
    Write-Host "  Docker is running" -ForegroundColor Green

    Write-Host "  Starting n8n (the neuronet backbone)..."
    Set-Location "$ProjectRoot\setup"
    docker compose up -d
    Set-Location $ProjectRoot
    Write-Host "  n8n started at http://localhost:5678" -ForegroundColor Green
    Write-Host "  Default login: admin / changeme (change this!)" -ForegroundColor Magenta
} catch {
    Write-Host "  Docker not running — open Docker Desktop first, then re-run" -ForegroundColor Yellow
}

# ── 7. Eagle API check ────────────────────────────────────────────────────────
Write-Host "`nChecking Eagle..." -ForegroundColor Yellow
try {
    $eagleCheck = Invoke-RestMethod -Uri "http://localhost:41595/api/application/info" -TimeoutSec 3
    Write-Host "  Eagle is running and API is accessible" -ForegroundColor Green
} catch {
    Write-Host "  Eagle not running — open Eagle, then verify API works:" -ForegroundColor Yellow
    Write-Host "  http://localhost:41595/api/application/info" -ForegroundColor Yellow
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host "`n=== Setup Complete ===" -ForegroundColor Cyan
Write-Host @"

Next steps:
  1. Make sure .env has your ANTHROPIC_API_KEY
  2. Open Eagle (The System needs it running)
  3. Double-click start.bat to launch the agent

URLs when running:
  Agent chat  →  http://localhost:8000
  n8n flows   →  http://localhost:5678

"@ -ForegroundColor White
