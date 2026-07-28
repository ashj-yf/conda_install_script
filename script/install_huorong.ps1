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

# Huorong official download redirect (always points to latest version)
$HUORONG_DOWNLOAD_URL = if (-not [string]::IsNullOrWhiteSpace($DownloadUrl)) {
    $DownloadUrl
} else {
    "https://www.huorong.cn/product/downloadHr60.php?pro=hr60&plat=x64UrlAll"
}

$HUORONG_SETUP = Join-Path $env:TEMP "HuorongSetup.exe"
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

Install Huorong Security (latest) from official CDN.

Options:
  -Force           Force reinstall even if Huorong is already detected
  -DryRun          Print detection info and download URL without executing
  -Clean           Remove cached installer and exit
  -DownloadUrl URL Custom download URL (default: Huorong CDN latest)
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
    if (Test-Path $HUORONG_SETUP) {
        Remove-Item $HUORONG_SETUP -Force
        Write-Info "Removed: $HUORONG_SETUP"
    } else {
        Write-Info "No cached installer found at $HUORONG_SETUP"
    }
    exit 0
}

# --- Cleanup trap ---
try {

# ============================================================
# Step 1: Detect existing Huorong
# ============================================================
Write-Step 1 $TOTAL_STEPS "Detecting Huorong Security..."

$huorongInstalled = $false
$huorongPath = $null

# Check via service
$service = Get-Service -Name "HipsDaemon" -ErrorAction SilentlyContinue
if ($service) {
    Write-Info "Huorong service (HipsDaemon) detected: $($service.Status)"
    $huorongInstalled = $true
}

# Check common install path for main executable
if (-not $huorongInstalled) {
    $commonPaths = @(
        "$env:ProgramFiles\Huorong\ESEndpoint\bin\HipsMain.exe",
        "${env:ProgramFiles(x86)}\Huorong\ESEndpoint\bin\HipsMain.exe",
        "C:\Program Files\Huorong\ESEndpoint\bin\HipsMain.exe",
        "C:\Program Files (x86)\Huorong\ESEndpoint\bin\HipsMain.exe"
    )
    foreach ($p in $commonPaths) {
        if (Test-Path $p) { 
            $huorongPath = $p
            $huorongInstalled = $true
            Write-Info "Huorong detected at: $p"
            break
        }
    }
}

# Check registry uninstall key
if (-not $huorongInstalled) {
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Huorong",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Huorong"
    )
    foreach ($key in $uninstallKeys) {
        $entry = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if ($entry -and $entry.DisplayName -match "火绒") {
            Write-Info "Huorong detected via registry: $($entry.DisplayName)"
            $huorongInstalled = $true
            break
        }
    }
}

if ($huorongInstalled) {
    if (-not $Force) {
        Write-Info "Huorong Security is already installed. Use -Force to reinstall."
        if ($DryRun) { Write-Info "[DRY-RUN] Would skip installation." }
        exit 0
    }
    Write-Warn "Force flag set. Will reinstall Huorong."
} else {
    Write-Info "Huorong Security not detected. Proceeding with installation."
}

# ============================================================
# Step 2: Dry run / Download
# ============================================================
Write-Step 2 $TOTAL_STEPS "Downloading Huorong Security..."

if ($DryRun) {
    Write-Host ""
    Write-Info "[DRY-RUN] Download URL: $HUORONG_DOWNLOAD_URL"
    Write-Info "[DRY-RUN] Installer cache: $HUORONG_SETUP"
    Write-Info "[DRY-RUN] Install command: $HUORONG_SETUP /S"
    exit 0
}

if ($huorongInstalled -and -not $Force) {
    Write-Info "Skipping download (Huorong already installed)."
} elseif ((Test-Path $HUORONG_SETUP) -and (Get-Item $HUORONG_SETUP).Length -gt 0) {
    Write-Info "Installer already cached: $HUORONG_SETUP"
} else {
    Write-Info "Downloading from: $HUORONG_DOWNLOAD_URL"
    if ([string]::IsNullOrWhiteSpace($HUORONG_DOWNLOAD_URL)) {
        Die "Download URL is empty. Please check your network or use -DownloadUrl to specify a custom URL."
    }
    try {
        Invoke-WebRequest -Uri $HUORONG_DOWNLOAD_URL -OutFile $HUORONG_SETUP -UseBasicParsing
        Write-Info "Download complete."
    } catch {
        Die "Huorong download failed: $_"
    }
}

# ============================================================
# Step 3: Install Huorong
# ============================================================
Write-Step 3 $TOTAL_STEPS "Installing Huorong Security (silent mode)..."

if ($huorongInstalled -and -not $Force) {
    Write-Info "Skipping installation (Huorong already installed)."
} else {
    # Double-check in case a prior run already installed it
    $recheck = Get-Service -Name "HipsDaemon" -ErrorAction SilentlyContinue
    if ($recheck) {
        Write-Info "Huorong service already running. Skipping installation."
    } else {
        # Check admin rights (NSIS manifest requires Administrator)
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Warn "Huorong installer requires Administrator privileges."
            Write-Info "Attempting to run installer (UAC prompt may appear)..."
        }

        Write-Info "Running silent installer..."
        try {
            # NSIS silent install: /S (must be uppercase)
            # Use -Verb RunAs to ensure admin elevation for the installer
            $proc = Start-Process -FilePath $HUORONG_SETUP -ArgumentList "/S" -Wait -PassThru -Verb RunAs
            if ($proc.ExitCode -ne 0) {
                Write-Warn "Huorong installer exited with code: $($proc.ExitCode)"
                if ($proc.ExitCode -eq 2) {
                    Write-Warn "Exit code 2 may indicate: UAC denied, incompatible OS, or installer self-extract failure."
                }
            } else {
                Write-Info "Huorong installation complete."
            }
        } catch {
            Die "Huorong installation failed: $_"
        }
    }
}

# Verify
Write-Info "Verifying Huorong installation..."
$huorongFound = $false

# Check service
$verifyService = Get-Service -Name "HipsDaemon" -ErrorAction SilentlyContinue
if ($verifyService) {
    Write-Info "Huorong service (HipsDaemon): $($verifyService.Status)"
    $huorongFound = $true
}

# Check common install paths
$verifyPaths = @(
    "$env:ProgramFiles\Huorong\ESEndpoint\bin\HipsMain.exe",
    "${env:ProgramFiles(x86)}\Huorong\ESEndpoint\bin\HipsMain.exe",
    "C:\Program Files\Huorong\ESEndpoint\bin\HipsMain.exe",
    "C:\Program Files (x86)\Huorong\ESEndpoint\bin\HipsMain.exe",
    "$env:ProgramFiles\Huorong\Sysdiag\bin\HipsMain.exe",
    "${env:ProgramFiles(x86)}\Huorong\Sysdiag\bin\HipsMain.exe"
)
foreach ($p in $verifyPaths) {
    if (Test-Path $p) {
        Write-Info "Huorong installed at: $p"
        $huorongFound = $true
        break
    }
}

if (-not $huorongFound) {
    Write-Warn "Huorong not detected. A system reboot may be required, or run this script as Administrator."
}

# Cleanup
if (Test-Path $HUORONG_SETUP) {
    Remove-Item $HUORONG_SETUP -Force -ErrorAction SilentlyContinue
    Write-Info "Installer cleaned up."
}

# --- Success message ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Huorong Security installation finished!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Verify with:"
Write-Host "  Get-Service HipsDaemon"
Write-Host ""

} finally {
    # Cleanup on error
    if (Test-Path $HUORONG_SETUP) {
        Remove-Item $HUORONG_SETUP -Force -ErrorAction SilentlyContinue
        Write-Info "Cleaned up: $HUORONG_SETUP"
    }
}
