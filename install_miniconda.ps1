#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Clean,
    [string]$Path,
    [switch]$Help,
    [switch]$Version
)

$ErrorActionPreference = "Stop"

$SCRIPT_VERSION = "1.0.0"
$MIRROR_BASE_URL = "https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda"
$DEFAULT_INSTALL_PATH = Join-Path $env:USERPROFILE "miniconda3"
$LOCAL_INSTALLER = Join-Path $env:TEMP "Miniconda3-latest-installer.exe"
$TOTAL_STEPS = 5

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

Install Miniconda (latest) from Tsinghua mirror.

Options:
  -Force       Skip checks for existing conda and install path
  -Path PATH   Custom installation path (default: %USERPROFILE%\miniconda3)
  -DryRun      Print detection info and download URL without executing
  -Clean       Remove downloaded installer file and exit
  -Help        Show this help message
  -Version     Print script version

Environment variables:
  CONDA_INSTALL_PATH  Override default install path (same as -Path)
"@
    exit 0
}

if ($Version) {
    Write-Host $SCRIPT_VERSION
    exit 0
}

# Resolve install path: CLI arg > env var > default
$INSTALL_PATH = if ($Path) { $Path } elseif ($env:CONDA_INSTALL_PATH) { $env:CONDA_INSTALL_PATH } else { $DEFAULT_INSTALL_PATH }

# --- Clean mode ---
if ($Clean) {
    if (Test-Path $LOCAL_INSTALLER) {
        Remove-Item $LOCAL_INSTALLER -Force
        Write-Info "Removed installer: $LOCAL_INSTALLER"
    } else {
        Write-Info "No installer file found at $LOCAL_INSTALLER"
    }
    exit 0
}

# --- Cleanup trap ---
try {

# ============================================================
# Step 1: Detect environment
# ============================================================
Write-Step 1 $TOTAL_STEPS "Detecting environment..."

$CONDA_OS = "Windows"

# Architecture: AMD64 -> x86_64, x86 -> x86
$ARCH = $env:PROCESSOR_ARCHITECTURE
switch ($ARCH) {
    "AMD64"  { $CONDA_ARCH = "x86_64" }
    "x86"    { $CONDA_ARCH = "x86" }
    "ARM64"  { $CONDA_ARCH = "x86_64"; Write-Warn "ARM64 Windows detected. Miniconda uses x86_64 emulation. Native ARM64 not yet available." }
    default  { Die "Unsupported architecture: $ARCH" }
}

$INSTALLER_FILENAME = "Miniconda3-latest-${CONDA_OS}-${CONDA_ARCH}.exe"
$DOWNLOAD_URL = "${MIRROR_BASE_URL}/${INSTALLER_FILENAME}"

Write-Info "OS: ${CONDA_OS}  |  Arch: ${CONDA_ARCH}  |  Installer: ${INSTALLER_FILENAME}"

# ============================================================
# Step 2: Pre-flight checks
# ============================================================
Write-Step 2 $TOTAL_STEPS "Running pre-flight checks..."

# Check existing conda
$existingConda = Get-Command conda -ErrorAction SilentlyContinue
if ($existingConda) {
    $existingVer = try { & conda --version 2>$null } catch { "unknown" }
    if ($Force) {
        Write-Warn "Existing conda found ($existingVer at $($existingConda.Source)), but -Force is set. Continuing."
    } else {
        Die "Conda is already installed ($existingVer at $($existingConda.Source)). Use -Force to override."
    }
}

# Check install path
if ((Test-Path $INSTALL_PATH) -and (Get-ChildItem $INSTALL_PATH -ErrorAction SilentlyContinue)) {
    if ($Force) {
        Write-Warn "Install path $INSTALL_PATH exists and is non-empty, but -Force is set. Continuing."
    } else {
        Die "Install path $INSTALL_PATH already exists and is non-empty. Use -Force to override."
    }
}

# Check parent directory writable
$parentDir = Split-Path $INSTALL_PATH -Parent
try {
    $testFile = Join-Path $parentDir ".conda_write_test_$(Get-Random)"
    New-Item $testFile -ItemType File -Force | Out-Null
    Remove-Item $testFile -Force
} catch {
    Die "Parent directory $parentDir is not writable. Choose a different path with -Path."
}

# Disk space check (soft)
$drive = (Split-Path $INSTALL_PATH -Qualifier)
if ($drive) {
    $disk = Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction SilentlyContinue
    if ($disk -and $disk.Free -lt 3GB) {
        Write-Warn "Less than 3 GB free disk space on ${drive}. Installation may fail."
    }
}

# ============================================================
# Step 3: Download installer
# ============================================================
Write-Step 3 $TOTAL_STEPS "Downloading Miniconda installer..."

if ($DryRun) {
    Write-Host ""
    Write-Info "[DRY-RUN] Would download: $DOWNLOAD_URL"
    Write-Info "[DRY-RUN] Install to: $INSTALL_PATH"
    Write-Info "[DRY-RUN] Command: $LOCAL_INSTALLER /S /D=$INSTALL_PATH"
    exit 0
}

Write-Info "Downloading from: $DOWNLOAD_URL"
try {
    # Use TLS 1.2 for modern HTTPS
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $LOCAL_INSTALLER -UseBasicParsing
} catch {
    Die "Download failed. URL: $DOWNLOAD_URL`nError: $_"
}

if (-not (Test-Path $LOCAL_INSTALLER) -or (Get-Item $LOCAL_INSTALLER).Length -eq 0) {
    Die "Downloaded installer is empty. The download may have failed."
}
Write-Info "Download complete."

# ============================================================
# Step 4: Install Miniconda
# ============================================================
Write-Step 4 $TOTAL_STEPS "Installing Miniconda..."

Write-Info "Install path: $INSTALL_PATH"

# NSIS silent install: /S for silent, /D for install dir (must be last, no quotes)
$installArgs = "/S /D=$INSTALL_PATH"
try {
    $proc = Start-Process -FilePath $LOCAL_INSTALLER -ArgumentList "/S","/D=$INSTALL_PATH" -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Die "Miniconda installation failed with exit code $($proc.ExitCode)."
    }
} catch {
    Die "Miniconda installation failed: $_"
}

# Verify installation
$condaExe = Join-Path $INSTALL_PATH "Scripts\conda.exe"
if (-not (Test-Path $condaExe)) {
    # Fallback: check root dir
    $condaExe = Join-Path $INSTALL_PATH "conda.exe"
}
if (-not (Test-Path $condaExe)) {
    Die "Installation failed: conda executable not found at $INSTALL_PATH"
}

$CONDA_VER = try { & $condaExe --version 2>$null } catch { "unknown" }
Write-Info "Miniconda $CONDA_VER installed successfully."

# ============================================================
# Step 5: Post-install configuration
# ============================================================
Write-Step 5 $TOTAL_STEPS "Configuring conda..."

# conda init
Write-Info "Running conda init..."
try {
    & $condaExe init powershell 2>$null
} catch {
    Write-Warn "conda init powershell reported a warning."
}
try {
    & $condaExe init cmd.exe 2>$null
} catch {
    Write-Warn "conda init cmd.exe reported a warning."
}

# Write ~/.condarc with Tsinghua mirror
$CONDARC_PATH = Join-Path $env:USERPROFILE ".condarc"
if (Test-Path $CONDARC_PATH) {
    $backup = "${CONDARC_PATH}.bak.$([int](Get-Date -UFormat %s))"
    Copy-Item $CONDARC_PATH $backup
    Write-Warn "Existing ~/.condarc backed up to $backup"
}

Write-Info "Writing Tsinghua mirror config to ~/.condarc..."
$condarcContent = @"
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
"@
Set-Content -Path $CONDARC_PATH -Value $condarcContent -Encoding UTF8

# Cleanup installer
Remove-Item $LOCAL_INSTALLER -Force -ErrorAction SilentlyContinue
Write-Info "Installer cleaned up."

# --- Success message ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Miniconda installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "  Location:  $INSTALL_PATH"
Write-Host "  Version:   $CONDA_VER"
Write-Host "  Mirror:    Tsinghua (mirrors.tuna.tsinghua.edu.cn)"
Write-Host ""
Write-Host "To activate conda, restart your terminal OR run:"
Write-Host "  PowerShell:  . `$env:USERPROFILE\Documents\WindowsPowerShell\profile.ps1"
Write-Host "  CMD:         Call conda activate from a new prompt"
Write-Host ""
Write-Host "Then verify with:"
Write-Host "  conda --version"
Write-Host "  conda config --show channels"
Write-Host "============================================================" -ForegroundColor Green

} finally {
    # Cleanup on error
    if ((Test-Path $LOCAL_INSTALLER) -and (-not $DryRun)) {
        Remove-Item $LOCAL_INSTALLER -Force -ErrorAction SilentlyContinue
        Write-Info "Cleaned up partial download: $LOCAL_INSTALLER"
    }
}
