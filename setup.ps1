# ========================================
# SLIME TRADES — WINDOWS SETUP SCRIPT
# One-click install: Python, pip, dependencies, SQLite option
# Run in PowerShell as Administrator
# ========================================

Write-Host "🧪 Slime Trades Setup Script" -ForegroundColor Green
Write-Host "=============================" -ForegroundColor Green
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "⚠️  Please run this script as Administrator!" -ForegroundColor Yellow
    Write-Host "Right-click PowerShell → 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# ========================================
# STEP 1: Install Chocolatey (Package Manager)
# ========================================
Write-Host "📦 Checking Chocolatey..." -ForegroundColor Cyan

$choco = Get-Command choco -ErrorAction SilentlyContinue
if (-not $choco) {
    Write-Host "Installing Chocolatey..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    # Refresh environment
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "✅ Chocolatey installed!" -ForegroundColor Green
} else {
    Write-Host "✅ Chocolatey already installed" -ForegroundColor Green
}

# ========================================
# STEP 2: Install Python 3.11
# ========================================
Write-Host ""
Write-Host "🐍 Checking Python..." -ForegroundColor Cyan

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Host "Installing Python 3.11..." -ForegroundColor Yellow
    choco install python --version=3.11.9 -y --force

    # Refresh environment
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "✅ Python installed!" -ForegroundColor Green
} else {
    $pyVersion = python --version 2>&1
    Write-Host "✅ Python found: $pyVersion" -ForegroundColor Green
}

# Verify pip
$pip = Get-Command pip -ErrorAction SilentlyContinue
if (-not $pip) {
    Write-Host "Installing pip..." -ForegroundColor Yellow
    python -m ensurepip --upgrade
    Write-Host "✅ pip installed!" -ForegroundColor Green
} else {
    Write-Host "✅ pip already installed" -ForegroundColor Green
}

# Upgrade pip
Write-Host "Upgrading pip..." -ForegroundColor Yellow
python -m pip install --upgrade pip

# ========================================
# STEP 3: Install Docker Desktop
# ========================================
Write-Host ""
Write-Host "🐳 Checking Docker..." -ForegroundColor Cyan

$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    Write-Host "Installing Docker Desktop..." -ForegroundColor Yellow
    choco install docker-desktop -y
    Write-Host "✅ Docker Desktop installed!" -ForegroundColor Green
    Write-Host "⚠️  Please restart your computer after this script finishes!" -ForegroundColor Yellow
    $needsRestart = $true
} else {
    Write-Host "✅ Docker already installed" -ForegroundColor Green
    $needsRestart = $false
}

# ========================================
# STEP 4: Install Git
# ========================================
Write-Host ""
Write-Host "📁 Checking Git..." -ForegroundColor Cyan

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Write-Host "Installing Git..." -ForegroundColor Yellow
    choco install git -y
    Write-Host "✅ Git installed!" -ForegroundColor Green
} else {
    Write-Host "✅ Git already installed" -ForegroundColor Green
}

# ========================================
# STEP 5: Install Python Dependencies
# ========================================
Write-Host ""
Write-Host "📚 Installing Python packages..." -ForegroundColor Cyan

$projectPath = "E:\Slime Websiteackend"
if (Test-Path "$projectPathequirements.txt") {
    Set-Location $projectPath
    Write-Host "Installing from requirements.txt..." -ForegroundColor Yellow
    pip install -r requirements.txt
    Write-Host "✅ Dependencies installed!" -ForegroundColor Green
} else {
    Write-Host "⚠️  requirements.txt not found at $projectPath" -ForegroundColor Yellow
    Write-Host "Installing core packages manually..." -ForegroundColor Yellow
    pip install fastapi uvicorn sqlalchemy asyncpg pydantic-settings python-jose passlib python-multipart aiosqlite
    Write-Host "✅ Core packages installed!" -ForegroundColor Green
}

# ========================================
# STEP 6: Setup SQLite (No Docker needed)
# ========================================
Write-Host ""
Write-Host "🗄️  Setting up SQLite for local testing..." -ForegroundColor Cyan

$configPath = "E:\Slime Websiteackendpp\config.py"
if (Test-Path $configPath) {
    $configContent = Get-Content $configPath -Raw

    # Check if already SQLite
    if ($configContent -match "sqlite") {
        Write-Host "✅ SQLite already configured" -ForegroundColor Green
    } else {
        Write-Host "Updating config to use SQLite..." -ForegroundColor Yellow

        # Backup original
        Copy-Item $configPath "$configPath.backup"

        # Replace PostgreSQL with SQLite
        $newConfig = $configContent -replace 'postgresql\+asyncpg://.*?"', 'sqlite+aiosqlite:///./slimetrades.db"'
        Set-Content $configPath $newConfig

        Write-Host "✅ Config updated to SQLite!" -ForegroundColor Green
        Write-Host "   (Backup saved as config.py.backup)" -ForegroundColor Gray
    }
} else {
    Write-Host "⚠️  config.py not found. You'll need to update it manually." -ForegroundColor Yellow
}

# ========================================
# STEP 7: Create __init__.py files
# ========================================
Write-Host ""
Write-Host "📂 Creating Python package files..." -ForegroundColor Cyan

$initPaths = @(
    "E:\Slime Websiteackendpp",
    "E:\Slime Websiteackendpp\core",
    "E:\Slime Websiteackendpp\models",
    "E:\Slime Websiteackendpp\schemas",
    "E:\Slime Websiteackendppouters",
    "E:\Slime Websiteackend\services",
    "E:\Slime Websiteackend\services\emotional_engine",
    "E:\Slime Websiteackend\servicesi_coach",
    "E:\Slime Websiteackend\services\guardian",
    "E:\Slime Websiteackend\integrations",
    "E:\Slime Websiteackend\integrations\mt5"
)

foreach ($path in $initPaths) {
    $initFile = Join-Path $path "__init__.py"
    if (-not (Test-Path $initFile)) {
        New-Item -ItemType File -Path $initFile -Force | Out-Null
        Write-Host "  Created: $initFile" -ForegroundColor Gray
    }
}
Write-Host "✅ Package files ready!" -ForegroundColor Green

# ========================================
# STEP 8: Summary
# ========================================
Write-Host ""
Write-Host "=============================" -ForegroundColor Green
Write-Host "🎉 SETUP COMPLETE!" -ForegroundColor Green
Write-Host "=============================" -ForegroundColor Green
Write-Host ""

if ($needsRestart) {
    Write-Host "⚠️  IMPORTANT: Please restart your computer now!" -ForegroundColor Red
    Write-Host "   Docker Desktop needs a restart to work properly." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. cd 'E:\Slime Websiteackend'" -ForegroundColor White
Write-Host "  2. python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000" -ForegroundColor White
Write-Host "  3. Open http://localhost:8000/docs in your browser" -ForegroundColor White
Write-Host ""
Write-Host "If you get any errors, try:" -ForegroundColor Yellow
Write-Host "  pip install -r requirements.txt" -ForegroundColor White
Write-Host ""
Write-Host "To switch back to PostgreSQL later:" -ForegroundColor Gray
Write-Host "  1. Restore config.py.backup" -ForegroundColor Gray
Write-Host "  2. Install Docker Desktop" -ForegroundColor Gray
Write-Host "  3. Run: docker-compose up -d postgres redis" -ForegroundColor Gray
Write-Host ""

Read-Host "Press Enter to exit"
