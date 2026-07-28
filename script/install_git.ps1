#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Clean,
    [string]$DownloadUrl,
    [switch]$Help,
    [switch]$Version
)

$ErrorActionPreference = "Stop"

$SCRIPT_VERSION = "1.0.0"

# Huaweicloud mirror (official Git-for-Windows)
$DEFAULT_DOWNLOAD_URL = "https://mirrors.huaweicloud.com/git-for-windows/v2.47.1.windows.1/Git-2.47.1-64-bit.exe"

# Resolve: CLI arg > default
$GIT_DOWNLOAD_URL = if (-not [string]::IsNullOrWhiteSpace($DownloadUrl)) { $DownloadUrl } else { $DEFAULT_DOWNLOAD_URL }

$GIT_SETUP = Join-Path $env:TEMP "GitSetup.exe"
$TOTAL_STEPS = 3

# --- Logging ---
function Write-Info($msg)  { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Die($msg)         { Write-Err $msg; exit 1 }
function Write-Step($n, $t, $msg) { Write-Host "[$n/$t] " -ForegroundColor Cyan -NoNewline; Write-Host $msg -ForegroundColor White }

# --- Help ---
if ($Help) {
    $name = Split-Path $PSCommandPath -Leaf
    Write-Host @"
Usage: $name [OPTIONS]

Install Git for Windows from Huawei mirror.

Options:
  -Force           Force reinstall even if Git is already detected
  -DryRun          Print detection info and download URL without executing
  -Clean           Remove cached installer and exit
  -DownloadUrl URL Custom download URL (default: Huawei Git mirror)
  -Help            Show this help message
  -Version         Print script version
"@
    exit 0
}

if ($Version) {
    Write-Host $SCRIPT_VERSION
    exit 0
}

# --- Clean mode ---
if ($Clean) {
    if (Test-Path $GIT_SETUP) {
        Remove-Item $GIT_SETUP -Force
        Write-Info "Removed: $GIT_SETUP"
    } else {
        Write-Info "No cached installer found at $GIT_SETUP"
    }
    exit 0
}

# --- Cleanup trap ---
try {

# ============================================================
# Step 1: Detect existing Git
# ============================================================
Write-Step 1 $TOTAL_STEPS "Detecting Git..."

$gitCmd = $null
$gitAlreadyInstalled = $false

# Check via Get-Command
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    # Check common install paths
    foreach ($p in @(
        "$env:ProgramFiles\Git\cmd\git.exe",
        "${env:ProgramFiles(x86)}\Git\cmd\git.exe"
    )) {
        if ($p -and (Test-Path $p)) { $gitCmd = $p; break }
    }
}

if ($gitCmd) {
    $gitVersion = try { 
        if ($gitCmd -is [string]) { & $gitCmd --version 2>&1 } 
        else { & git --version 2>&1 }
    } catch { "unknown" }
    Write-Info "Git detected: $gitVersion"
    if (-not $Force) {
        Write-Info "Git is already installed. Use -Force to reinstall."
        $gitAlreadyInstalled = $true
    } else {
        Write-Warn "Force flag set. Will reinstall Git."
    }
} else {
    Write-Info "Git not detected. Proceeding with installation."
}

# ============================================================
# Step 2: Dry run / Download
# ============================================================
Write-Step 2 $TOTAL_STEPS "Downloading Git..."

if ($DryRun) {
    Write-Host ""
    Write-Info "[DRY-RUN] Download URL: $GIT_DOWNLOAD_URL"
    Write-Info "[DRY-RUN] Installer cache: $GIT_SETUP"
    if ($gitAlreadyInstalled) { Write-Info "[DRY-RUN] Would skip (already installed)." }
    exit 0
}

if ($gitAlreadyInstalled) {
    Write-Info "Skipping download (Git already installed)."
} elseif ((Test-Path $GIT_SETUP) -and (Get-Item $GIT_SETUP).Length -gt 0) {
    Write-Info "Installer already cached: $GIT_SETUP"
} else {
    Write-Info "Downloading from: $GIT_DOWNLOAD_URL"
    try {
        Invoke-WebRequest -Uri $GIT_DOWNLOAD_URL -OutFile $GIT_SETUP -UseBasicParsing
        Write-Info "Download complete."
    } catch {
        Die "Git download failed: $_"
    }
}

# ============================================================
# Step 3: Install Git
# ============================================================
Write-Step 3 $TOTAL_STEPS "Installing Git (silent mode)..."

if ($gitAlreadyInstalled) {
    Write-Info "Skipping installation (Git already installed)."
} else {
    # Double-check in case a prior run already installed it
    $recheck = Get-Command git -ErrorAction SilentlyContinue
    if ($recheck) {
        Write-Info "Git already available. Skipping installation."
    } else {
        try {
            $gitProc = Start-Process $GIT_SETUP -ArgumentList @(
                "/VERYSILENT",
                "/NORESTART",
                "/NOCANCEL",
                "/SP-",
                "/CLOSEAPPLICATIONS",
                "/RESTARTAPPLICATIONS",
                "/COMPONENTS=`"icons,extreg`""
            ) -Wait -PassThru

            if ($gitProc.ExitCode -ne 0) {
                Write-Warn "Git installer exited with code: $($gitProc.ExitCode)"
                Write-Info "Installer cached at: $GIT_SETUP (run manually or retry this script)"
            } else {
                Write-Info "Git installation complete."
                # Cleanup on success
                if (Test-Path $GIT_SETUP) {
                    Remove-Item $GIT_SETUP -Force -ErrorAction SilentlyContinue
                    Write-Info "Installer cleaned up."
                }
            }
        } catch {
            Die "Git installation failed: $_"
        }
    }
}

# Verify
Write-Info "Verifying Git installation..."
try {
    $gitVer = & git --version 2>&1
    Write-Info "Git version: $gitVer"
} catch {
    Write-Warn "Git verification failed. Please restart your terminal and try again."
}

# --- Success message ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Git installation finished!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Verify with:"
Write-Host "  git --version"
Write-Host ""

} finally {
    # Keep cached installer on error for retry; only clean zero-length files
    if ((Test-Path $GIT_SETUP) -and (Get-Item $GIT_SETUP).Length -eq 0) {
        Remove-Item $GIT_SETUP -Force -ErrorAction SilentlyContinue
        Write-Info "Cleaned up zero-length installer: $GIT_SETUP"
    }
}
