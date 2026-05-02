# setup.ps1 — Run this on a FRESH Windows install to rebuild everything
# Run in PowerShell as Administrator

param(
    [string]$Username = "Allen Watts",
    [string]$RepoUrl  = "https://github.com/ElDirte/Cluad.git"
)

$SetupDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   THE SYSTEM — Fresh PC Setup" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Install winget if missing ────────────────────────────────────────
Write-Host "[1/8] Checking winget..." -ForegroundColor Yellow
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing winget..." -ForegroundColor Gray
    $url = "https://aka.ms/getwinget"
    $out = "$env:TEMP\winget.msixbundle"
    Invoke-WebRequest -Uri $url -OutFile $out
    Add-AppxPackage $out
}
Write-Host "  OK" -ForegroundColor Green

# ── Step 2: Install all apps from snapshot ────────────────────────────────────
Write-Host "[2/8] Installing apps from snapshot..." -ForegroundColor Yellow
$appsFile = "$SetupDir\winget-apps.json"
if (Test-Path $appsFile) {
    winget import -i $appsFile --accept-source-agreements --accept-package-agreements
    Write-Host "  OK - apps installed" -ForegroundColor Green
} else {
    Write-Host "  No winget-apps.json found. Installing core apps manually..." -ForegroundColor Gray

    $apps = @(
        "Git.Git",                      # Git + Git Bash
        "Python.Python.3.11",           # Python
        "Docker.DockerDesktop",         # Docker
        "Logseq.Logseq",               # Knowledge base
        "Obsidian.Obsidian",           # Backup note app
        "Microsoft.VisualStudioCode",   # Code editor
        "Google.Chrome",               # Browser
        "Notion.NotionDesktop",        # Notion
        "AFFiNE.AFFiNE"               # Visual canvas
    )

    foreach ($app in $apps) {
        Write-Host "  Installing $app..." -ForegroundColor Gray
        winget install --id $app --accept-source-agreements --accept-package-agreements --silent
    }
    Write-Host "  OK" -ForegroundColor Green
}

# ── Step 3: Restore git config ────────────────────────────────────────────────
Write-Host "[3/8] Restoring git config..." -ForegroundColor Yellow
$gitConfigSrc = "$SetupDir\configs\.gitconfig"
if (Test-Path $gitConfigSrc) {
    Copy-Item $gitConfigSrc "$env:USERPROFILE\.gitconfig"
    Write-Host "  OK" -ForegroundColor Green
} else {
    git config --global user.name $Username
    Write-Host "  Set git user.name to '$Username'" -ForegroundColor Gray
    Write-Host "  NOTE: Set your email: git config --global user.email you@example.com" -ForegroundColor Yellow
}

# ── Step 4: Restore Git Bash profile ─────────────────────────────────────────
Write-Host "[4/8] Restoring Git Bash profile..." -ForegroundColor Yellow
$bashSrc = "$SetupDir\configs\.bashrc"
if (Test-Path $bashSrc) {
    Copy-Item $bashSrc "$env:USERPROFILE\.bashrc"
    Write-Host "  OK" -ForegroundColor Green
}

# ── Step 5: Clone the Cluad repo ─────────────────────────────────────────────
Write-Host "[5/8] Cloning Cluad repo..." -ForegroundColor Yellow
$repoPath = "$env:USERPROFILE\Cluad"
if (-not (Test-Path $repoPath)) {
    git clone $RepoUrl $repoPath
    Push-Location $repoPath
    git checkout claude/second-brain-architecture-s1ffb
    Pop-Location
    Write-Host "  OK - cloned to $repoPath" -ForegroundColor Green
} else {
    Write-Host "  SKIP - already exists at $repoPath" -ForegroundColor Gray
}

# ── Step 6: Set up Python venv ───────────────────────────────────────────────
Write-Host "[6/8] Setting up Python environment..." -ForegroundColor Yellow
Push-Location $repoPath
python -m venv venv
.\venv\Scripts\pip install -r requirements.txt --quiet
Pop-Location
Write-Host "  OK" -ForegroundColor Green

# ── Step 7: Create .env ──────────────────────────────────────────────────────
Write-Host "[7/8] Creating .env..." -ForegroundColor Yellow
$envFile = "$repoPath\.env"
if (-not (Test-Path $envFile)) {
    Copy-Item "$repoPath\.env.example" $envFile
    $key = Read-Host "  Enter your ANTHROPIC_API_KEY (or press Enter to skip)"
    if ($key) {
        (Get-Content $envFile) -replace "ANTHROPIC_API_KEY=.*", "ANTHROPIC_API_KEY=$key" |
            Set-Content $envFile
    }
    Write-Host "  OK - edit $envFile to complete setup" -ForegroundColor Green
} else {
    Write-Host "  SKIP - .env already exists" -ForegroundColor Gray
}

# ── Step 8: Start Docker stack ───────────────────────────────────────────────
Write-Host "[8/8] Starting Docker stack..." -ForegroundColor Yellow
Write-Host "  NOTE: Docker Desktop must be running first." -ForegroundColor Gray
$startDocker = Read-Host "  Is Docker Desktop running? Start the stack now? (y/n)"
if ($startDocker -eq "y") {
    Push-Location $repoPath
    docker-compose up -d
    Pop-Location
    Write-Host "  OK - stack started" -ForegroundColor Green
} else {
    Write-Host "  SKIP - run 'docker-compose up -d' in ~/Cluad when ready" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   Setup complete!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Services (once Docker stack is up):" -ForegroundColor White
Write-Host "  Pipeline API  → http://localhost:8001/health"
Write-Host "  n8n           → http://localhost:5678  (admin/changeme)"
Write-Host "  Neo4j         → http://localhost:7474"
Write-Host ""
Write-Host "Open Logseq → Add Graph → ~/SecondBrain/01-logseq"
Write-Host ""
