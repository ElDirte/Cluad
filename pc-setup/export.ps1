# export.ps1 — Run this on your CURRENT PC to snapshot everything
# It captures your installed apps and configs into this folder
# Run in PowerShell as Administrator

$SetupDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "=== Exporting PC Setup Snapshot ===" -ForegroundColor Cyan
Write-Host ""

# 1. Export all installed apps via winget
Write-Host "[1/4] Exporting installed apps..." -ForegroundColor Yellow
try {
    winget export -o "$SetupDir\winget-apps.json" --accept-source-agreements
    Write-Host "  OK - winget-apps.json saved" -ForegroundColor Green
} catch {
    Write-Host "  WARN: winget not available - skipping app export" -ForegroundColor Red
}

# 2. Export git config
Write-Host "[2/4] Exporting git config..." -ForegroundColor Yellow
$gitConfig = "$env:USERPROFILE\.gitconfig"
if (Test-Path $gitConfig) {
    Copy-Item $gitConfig "$SetupDir\configs\.gitconfig"
    Write-Host "  OK - .gitconfig saved" -ForegroundColor Green
} else {
    Write-Host "  SKIP - no .gitconfig found" -ForegroundColor Gray
}

# 3. Export Git Bash profile
Write-Host "[3/4] Exporting Git Bash profile..." -ForegroundColor Yellow
$bashProfile = "$env:USERPROFILE\.bashrc"
if (Test-Path $bashProfile) {
    Copy-Item $bashProfile "$SetupDir\configs\.bashrc"
    Write-Host "  OK - .bashrc saved" -ForegroundColor Green
} else {
    # Create a sensible default
    @"
# Git Bash profile — Allen Watts
alias ll='ls -la'
alias cluad='cd ~/Cluad'
alias brain='cd ~/SecondBrain'
alias start-agent='cd ~/Cluad && bash start-api.sh'
alias brief='curl -s http://localhost:8001/brief | python3 -m json.tool'
export PATH="$PATH:/c/Users/$USERNAME/AppData/Local/Programs/Ollama"
"@ | Out-File -FilePath "$SetupDir\configs\.bashrc" -Encoding utf8
    Write-Host "  OK - default .bashrc created" -ForegroundColor Green
}

# 4. Save system info
Write-Host "[4/4] Saving system info..." -ForegroundColor Yellow
@{
    ExportDate    = (Get-Date -Format "yyyy-MM-dd HH:mm")
    ComputerName  = $env:COMPUTERNAME
    Username      = $env:USERNAME
    WindowsVersion = (Get-WinSystemInformation).WindowsVersion 2>$null
    RAM_GB        = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
} | ConvertTo-Json | Out-File "$SetupDir\configs\system-info.json" -Encoding utf8

Write-Host ""
Write-Host "=== Snapshot complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next: git add pc-setup/ && git commit -m 'snapshot: pc setup' && git push" -ForegroundColor White
Write-Host "Then on fresh PC: run pc-setup\setup.ps1 as Administrator" -ForegroundColor White
Write-Host ""
