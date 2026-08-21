#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Clean,
    [string]$Path,
    [ValidateSet("tuna", "pku")]
    [string]$Mirror,
    [switch]$Help,
    [switch]$Version
)

$ErrorActionPreference = "Stop"

$SCRIPT_VERSION = "1.1.0"

# --- Mirror configurations ---
$MIRROR_CONFIG = @{
    tuna = @{
        Name = "TUNA"
        DisplayName = "清华 TUNA"
        BaseUrl = "https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda"
        CloudUrl = "https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud"
    }
    pku = @{
        Name = "PKU"
        DisplayName = "北大 PKU"
        BaseUrl = "https://mirrors.pku.edu.cn/anaconda/miniconda"
        CloudUrl = "https://mirrors.pku.edu.cn/anaconda/cloud"
    }
}

$DEFAULT_MIRROR = "tuna"
$DEFAULT_INSTALL_PATH = "C:\ProgramData\miniconda3"
$LOCAL_INSTALLER = Join-Path $env:TEMP "Miniconda3-latest-installer.exe"
$TOTAL_STEPS = 5

# --- Logging ---
function Write-Info($msg)  { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Die($msg)         { Write-Err $msg; exit 1 }
function Write-Step($n, $t, $msg) { Write-Host "[$n/$t] " -ForegroundColor Cyan -NoNewline; Write-Host $msg -ForegroundColor White }

# --- Mirror selection ---
function Select-Mirror {
    if ($Mirror) {
        $selected = $Mirror.ToLower()
        Write-Info "Using mirror specified via -Mirror: $($MIRROR_CONFIG[$selected].DisplayName)"
        return $selected
    }

    # Interactive selection
    Write-Host ""
    Write-Host "请选择 conda 镜像源：" -ForegroundColor Yellow
    Write-Host "  [1] 清华 TUNA (mirrors.tuna.tsinghua.edu.cn) - 默认" -ForegroundColor White
    Write-Host "  [2] 北大 PKU (mirrors.pku.edu.cn)" -ForegroundColor White
    Write-Host ""

    while ($true) {
        $choice = Read-Host "请输入选择 [1]"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
        switch ($choice) {
            "1" { return "tuna" }
            "2" { return "pku" }
            default {
                Write-Warn "无效选择，请输入 1 或 2"
            }
        }
    }
}

# --- Help ---
if ($Help) {
    $name = Split-Path $PSCommandPath -Leaf
    Write-Host @"
Usage: $name [OPTIONS]

Install Miniconda (latest) from Chinese mirror.

Options:
  -Force       Skip checks for existing conda and install path
  -Path PATH   Custom installation path (default: C:\ProgramData\miniconda3)
  -Mirror SRC  Choose mirror source: tuna (清华, default) or pku (北大)
  -DryRun      Print detection info and download URL without executing
  -Clean       Remove downloaded installer file and exit
  -Help        Show this help message
  -Version     Print script version

Available mirrors:
  tuna  - 清华 TUNA (mirrors.tuna.tsinghua.edu.cn) [默认]
  pku   - 北大 PKU (mirrors.pku.edu.cn)

Examples:
  $name                      # Interactive selection
  $name -Mirror tuna         # Use TUNA mirror (default)
  $name -Mirror pku          # Use PKU mirror
  $name -Force -Mirror pku   # Force install with PKU mirror

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

# --- Select mirror ---
$MIRROR_KEY = Select-Mirror
$MIRROR = $MIRROR_CONFIG[$MIRROR_KEY]
$MIRROR_BASE_URL = $MIRROR.BaseUrl

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
Write-Info "Mirror: $($MIRROR.DisplayName)"

# ============================================================
# Step 2: Pre-flight checks
# ============================================================
Write-Step 2 $TOTAL_STEPS "Running pre-flight checks..."

# Check existing conda (anywhere in PATH, or at target install path)
$CONDA_ALREADY_INSTALLED = $false
$existingConda = Get-Command conda -ErrorAction SilentlyContinue
$targetCondaExe = Join-Path $INSTALL_PATH "Scripts\conda.exe"
$targetCondaAlt = Join-Path $INSTALL_PATH "conda.exe"

if ($existingConda) {
    $existingVer = try { & conda --version 2>$null } catch { "unknown" }
    if ($Force) {
        Write-Warn "Existing conda found ($existingVer at $($existingConda.Source)), but -Force is set. Continuing."
    } else {
        Write-Info "Conda is already installed ($existingVer at $($existingConda.Source)). Skipping install."
        $CONDA_ALREADY_INSTALLED = $true
    }
} elseif ((Test-Path $targetCondaExe) -or (Test-Path $targetCondaAlt)) {
    if ($Force) {
        Write-Warn "Conda found at $INSTALL_PATH (not in PATH), but -Force is set. Continuing."
    } else {
        Write-Info "Conda found at $INSTALL_PATH (not in PATH). Skipping install."
        $CONDA_ALREADY_INSTALLED = $true
    }
}

if (-not $CONDA_ALREADY_INSTALLED) {
    # Check install path
    if ((Test-Path $INSTALL_PATH) -and (Get-ChildItem $INSTALL_PATH -ErrorAction SilentlyContinue)) {
        if ($Force) {
            Write-Warn "Install path $INSTALL_PATH exists and is non-empty, but -Force is set. Continuing."
        } else {
            Write-Info "Install path $INSTALL_PATH exists and is non-empty. Skipping install."
            $CONDA_ALREADY_INSTALLED = $true
        }
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
    Write-Info "[DRY-RUN] Mirror: $($MIRROR.DisplayName)"
    Write-Info "[DRY-RUN] Command: $LOCAL_INSTALLER /S /D=$INSTALL_PATH"
    exit 0
}

if ($CONDA_ALREADY_INSTALLED) {
    Write-Info "Skipping download (conda already installed)."
} elseif ((Test-Path $LOCAL_INSTALLER) -and (Get-Item $LOCAL_INSTALLER).Length -gt 0) {
    Write-Info "Installer already cached: $LOCAL_INSTALLER"
} else {
    Write-Info "Downloading from: $DOWNLOAD_URL"
    try {
        # Use TLS 1.2 for modern HTTPS
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $LOCAL_INSTALLER -UseBasicParsing
    } catch {
        Die "Download failed. URL: $DOWNLOAD_URL`nError: $_`n  Cached at: $LOCAL_INSTALLER"
    }

    if (-not (Test-Path $LOCAL_INSTALLER) -or (Get-Item $LOCAL_INSTALLER).Length -eq 0) {
        Die "Downloaded installer is empty. The download may have failed."
    }
    Write-Info "Download complete."
}

# ============================================================
# Step 4: Install Miniconda
# ============================================================
Write-Step 4 $TOTAL_STEPS "Installing Miniconda..."

if ($CONDA_ALREADY_INSTALLED) {
    Write-Info "Skipping installation (conda already present)."
} else {
    # Double-check: conda may have been installed to target path by a prior run
    $preCheckConda = Join-Path $INSTALL_PATH "Scripts\conda.exe"
    if (-not (Test-Path $preCheckConda)) { $preCheckConda = Join-Path $INSTALL_PATH "conda.exe" }
    if (Test-Path $preCheckConda) {
        Write-Info "Conda already exists at $INSTALL_PATH. Skipping installation."
    } else {
        Write-Info "Install path: $INSTALL_PATH"

        # NSIS silent install: /S for silent, /D for install dir (must be last, no quotes)
        try {
            $proc = Start-Process -FilePath $LOCAL_INSTALLER -ArgumentList "/S","/D=$INSTALL_PATH" -Wait -PassThru
            if ($proc.ExitCode -ne 0) {
                Die "Miniconda installation failed with exit code $($proc.ExitCode).`n  Installer cached at: $LOCAL_INSTALLER (run manually or retry this script)"
            }
        } catch {
            Die "Miniconda installation failed: $_`n  Installer cached at: $LOCAL_INSTALLER"
        }
    }
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

# conda init (skip if profile already contains conda initialize block)
Write-Info "Running conda init..."
$psProfilePath = Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\profile.ps1"
$psProfileExists = (Test-Path $psProfilePath)
$psHasCondInit = $psProfileExists -and ((Get-Content $psProfilePath -Raw) -match "#region conda initialize")
$cmdHasCondInit = $false
$cmdAutoRunKey = "HKCU:\Software\Microsoft\Command Processor"
try {
    $cmdAutoRun = (Get-ItemProperty -Path $cmdAutoRunKey -Name "AutoRun" -ErrorAction SilentlyContinue).AutoRun
    if ($cmdAutoRun -and $cmdAutoRun -match "conda") { $cmdHasCondInit = $true }
} catch { }

if (-not $psHasCondInit) {
    try {
        & $condaExe init powershell 2>$null
        Write-Info "conda init powershell done."
    } catch {
        Write-Warn "conda init powershell reported a warning."
    }
} else {
    Write-Info "PowerShell profile already has conda initialize block. Skipping."
}

if (-not $cmdHasCondInit) {
    try {
        & $condaExe init cmd.exe 2>$null
        Write-Info "conda init cmd.exe done."
    } catch {
        Write-Warn "conda init cmd.exe reported a warning."
    }
} else {
    Write-Info "CMD AutoRun already has conda initialize. Skipping."
}

# Write ~/.condarc with selected mirror (always overwrite for idempotency)
$CLOUD_URL = $MIRROR.CloudUrl
$CONDARC_PATH = Join-Path $env:USERPROFILE ".condarc"
$condarcContent = @"
channels:
  - conda-forge
custom_channels:
  conda-forge: ${CLOUD_URL}
  bioconda: ${CLOUD_URL}
show_channel_urls: true
"@

if (Test-Path $CONDARC_PATH) {
    $existingContent = (Get-Content $CONDARC_PATH -Raw).Trim()
    if ($existingContent -ne $condarcContent.Trim()) {
        $backup = "${CONDARC_PATH}.bak.$([int](Get-Date -UFormat %s))"
        Copy-Item $CONDARC_PATH $backup
        Write-Warn "Existing ~/.condarc backed up to $backup"
    }
} else {
    Write-Info "No existing ~/.condarc found."
}
Write-Info "Writing $($MIRROR.DisplayName) mirror config to ~/.condarc (always overwrite)..."
Set-Content -Path $CONDARC_PATH -Value $condarcContent -Encoding UTF8

# Accept Anaconda ToS for default channels (fallback guard; conda >= 24.9 only,
# older versions lack the subcommand and are silently skipped)
Write-Info "Accepting Anaconda ToS for default channels..."
foreach ($ch in @(
    "https://repo.anaconda.com/pkgs/main",
    "https://repo.anaconda.com/pkgs/r",
    "https://repo.anaconda.com/pkgs/msys2"
)) {
    try { & $condaExe tos accept --override-channels --channel $ch 2>$null | Out-Null } catch { }
}

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
Write-Host "  Mirror:    $($MIRROR.DisplayName)"
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
    # Keep cached installer on error for retry; only clean zero-length files
    if ((Test-Path $LOCAL_INSTALLER) -and (Get-Item $LOCAL_INSTALLER).Length -eq 0) {
        Remove-Item $LOCAL_INSTALLER -Force -ErrorAction SilentlyContinue
        Write-Info "Cleaned up zero-length installer: $LOCAL_INSTALLER"
    }
}
