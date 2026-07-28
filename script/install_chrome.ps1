#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Help,
    [switch]$Version
)

$ErrorActionPreference = "Stop"

$SCRIPT_VERSION = "1.0.0"
$CHROME_DOWNLOAD_URL = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
$CHROME_SETUP = Join-Path $env:TEMP "ChromeSetup.exe"

# --- Logging ---
function Write-Info($msg)  { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Die($msg)         { Write-Err $msg; exit 1 }

# --- Help ---
if ($Help) {
    $name = Split-Path $PSCommandPath -Leaf
    Write-Host @"
Usage: $name [OPTIONS]

Install Google Chrome (latest) from Google's official download URL.

Options:
  -Force       Force reinstall even if Chrome is already detected
  -DryRun      Print detection info without executing
  -Help        Show this help message
  -Version     Print script version
"@
    exit 0
}

if ($Version) {
    Write-Host $SCRIPT_VERSION
    exit 0
}

# --- Cleanup trap ---
try {

# ============================================================
# Step 1: Detect existing Chrome
# ============================================================
Write-Host "[1/3] " -ForegroundColor Cyan -NoNewline
Write-Host "Detecting Chrome..." -ForegroundColor White

$chromePath = $null

# Check App Paths registry (HKLM system + HKCU user)
foreach ($hive in @("HKLM:", "HKCU:")) {
    $chrome = Get-ItemProperty "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction SilentlyContinue
    if ($chrome -and $chrome.'(default)' -and (Test-Path $chrome.'(default)')) {
        $chromePath = $chrome.'(default)'
        break
    }
}

# Check PATH
if (-not $chromePath) {
    $cmd = Get-Command chrome -ErrorAction SilentlyContinue
    if ($cmd) { $chromePath = $cmd.Source }
}

# Check common install paths (including user-level install)
if (-not $chromePath) {
    foreach ($p in @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )) {
        if ($p -and (Test-Path $p)) { $chromePath = $p; break }
    }
}

if ($chromePath) {
    Write-Info "Chrome detected: $chromePath"
    if (-not $Force) {
        Write-Info "Chrome is already installed. Use -Force to reinstall."
        if ($DryRun) { Write-Info "[DRY-RUN] Would skip installation." }
        exit 0
    }
    Write-Warn "Force flag set. Will reinstall Chrome."
} else {
    Write-Info "Chrome not detected. Proceeding with installation."
}

# ============================================================
# Step 2: Dry run check
# ============================================================
if ($DryRun) {
    Write-Host ""
    Write-Info "[DRY-RUN] Would download: $CHROME_DOWNLOAD_URL"
    Write-Info "[DRY-RUN] Would run: $CHROME_SETUP /silent /install"
    exit 0
}

# ============================================================
# Step 3: Download and install
# ============================================================
Write-Host "[2/3] " -ForegroundColor Cyan -NoNewline
Write-Host "Downloading Chrome..." -ForegroundColor White

if ((Test-Path $CHROME_SETUP) -and (Get-Item $CHROME_SETUP).Length -gt 0) {
    Write-Info "Installer already cached: $CHROME_SETUP"
} else {
    Write-Info "Downloading from: $CHROME_DOWNLOAD_URL"
    try {
        Invoke-WebRequest -Uri $CHROME_DOWNLOAD_URL -OutFile $CHROME_SETUP -UseBasicParsing
    } catch {
        Die "Chrome download failed: $_"
    }
    Write-Info "Download complete."
}

Write-Host "[3/3] " -ForegroundColor Cyan -NoNewline
Write-Host "Installing Chrome (silent mode)..." -ForegroundColor White

try {
    $chromeProc = Start-Process $CHROME_SETUP -ArgumentList "/silent /install" -Wait -PassThru
    if ($chromeProc.ExitCode -ne 0) {
        Write-Warn "Chrome installer exited with code: $($chromeProc.ExitCode)"
        Write-Info "Installer cached at: $CHROME_SETUP (run manually or retry this script)"
    } else {
        Write-Info "Chrome installation complete."
        # Cleanup on success
        if (Test-Path $CHROME_SETUP) {
            Remove-Item $CHROME_SETUP -Force -ErrorAction SilentlyContinue
            Write-Info "Installer cleaned up."
        }
    }
} catch {
    Die "Chrome installation failed: $_"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Chrome installation finished!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green

} finally {
    # Keep cached installer on error for retry; only clean zero-length files
    if ((Test-Path $CHROME_SETUP) -and (Get-Item $CHROME_SETUP).Length -eq 0) {
        Remove-Item $CHROME_SETUP -Force -ErrorAction SilentlyContinue
        Write-Info "Cleaned up zero-length installer: $CHROME_SETUP"
    }
}