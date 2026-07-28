#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Clean,
    [string]$DownloadUrl,
    [string]$Path,
    [switch]$SkipEnv,
    [switch]$Help,
    [switch]$Version
)

$ErrorActionPreference = "Stop"

$SCRIPT_VERSION = "1.0.0"

# Defaults
$DEFAULT_DOWNLOAD_URL = "https://mirrors.huaweicloud.com/openjdk/21.0.2/openjdk-21.0.2_windows-x64_bin.zip"
$DEFAULT_INSTALL_PATH = "C:\ProgramData\Java\jdk-21"

# Resolve: CLI arg > env var > default
$JAVA_DOWNLOAD_URL = if (-not [string]::IsNullOrWhiteSpace($DownloadUrl)) { $DownloadUrl } elseif ($env:JAVA_DOWNLOAD_URL) { $env:JAVA_DOWNLOAD_URL } else { $DEFAULT_DOWNLOAD_URL }
$JAVA_INSTALL_PATH = if ($Path) { $Path } else { $DEFAULT_INSTALL_PATH }

$TEMP_DIR = $env:TEMP
$JAVA_ZIP = Join-Path $TEMP_DIR "openjdk-21.0.2_windows-x64_bin.zip"
$TOTAL_STEPS = if ($SkipEnv) { 3 } else { 4 }

# --- Logging ---
function Write-Info($msg)  { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Die($msg)         { Write-Err $msg; exit 1 }
function Write-Step($n, $t, $msg) { Write-Host "[$n/$t] " -ForegroundColor Cyan -NoNewline; Write-Host $msg -ForegroundColor White }

# --- Environment variable helper ---
function Add-ToSystemPath {
    param([string]$TargetPath)
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if (";$currentPath;" -notlike "*;$TargetPath;*") {
        $newPath = if ($currentPath) { "$currentPath;$TargetPath" } else { $TargetPath }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
        $env:Path = "$newPath;" + [Environment]::GetEnvironmentVariable("Path", "User")
        Write-Info "Added to system PATH: $TargetPath"
    } else {
        Write-Info "System PATH already contains: $TargetPath"
    }
}

# --- Help ---
if ($Help) {
    $name = Split-Path $PSCommandPath -Leaf
    Write-Host @"
Usage: $name [OPTIONS]

Install OpenJDK 21 from Huawei mirror and configure JAVA_HOME + PATH.

Options:
  -Force           Force reinstall even if Java is already detected
  -DryRun          Print detection info and download URL without executing
  -Clean           Remove cached ZIP and exit
  -DownloadUrl URL Custom download URL (default: Huawei OpenJDK 21 mirror)
  -Path PATH       Custom installation path (default: C:\ProgramData\Java\jdk-21)
  -SkipEnv         Skip JAVA_HOME and PATH configuration
  -Help            Show this help message
  -Version         Print script version

Environment variables:
  JAVA_DOWNLOAD_URL  Override default download URL (same as -DownloadUrl)
"@
    exit 0
}

if ($Version) {
    Write-Host $SCRIPT_VERSION
    exit 0
}

# --- Clean mode ---
if ($Clean) {
    if (Test-Path $JAVA_ZIP) {
        Remove-Item $JAVA_ZIP -Force
        Write-Info "Removed: $JAVA_ZIP"
    } else {
        Write-Info "No cached ZIP found at $JAVA_ZIP"
    }
    exit 0
}

# --- Cleanup trap ---
try {

# ============================================================
# Step 1: Detect existing Java
# ============================================================
Write-Step 1 $TOTAL_STEPS "Detecting Java..."

$javaExePath = Join-Path $JAVA_INSTALL_PATH "bin\java.exe"
$javaAlreadyInstalled = $false

if (Test-Path $javaExePath) {
    Write-Info "Java detected at: $JAVA_INSTALL_PATH"
    if (-not $Force) {
        Write-Info "Java is already installed. Use -Force to reinstall."
        $javaAlreadyInstalled = $true
    } else {
        Write-Warn "Force flag set. Will reinstall Java."
    }
} else {
    Write-Info "Java not detected at $JAVA_INSTALL_PATH. Proceeding with installation."
}

# ============================================================
# Step 2: Dry run / Download Java
# ============================================================
Write-Step 2 $TOTAL_STEPS "Downloading Java 21 (OpenJDK)..."

if ($DryRun) {
    Write-Host ""
    Write-Info "[DRY-RUN] Download URL: $JAVA_DOWNLOAD_URL"
    Write-Info "[DRY-RUN] Install path: $JAVA_INSTALL_PATH"
    Write-Info "[DRY-RUN] ZIP cache: $JAVA_ZIP"
    if ($javaAlreadyInstalled) { Write-Info "[DRY-RUN] Would skip (already installed)." }
    exit 0
}

if ($javaAlreadyInstalled) {
    Write-Info "Skipping download (Java already installed)."
} elseif ((Test-Path $JAVA_ZIP) -and (Get-Item $JAVA_ZIP).Length -gt 0) {
    Write-Info "Java ZIP already cached: $JAVA_ZIP"
} else {
    Write-Info "Download URL: $JAVA_DOWNLOAD_URL"
    Write-Info "Downloading (this may take a few minutes)..."
    try {
        Invoke-WebRequest -Uri $JAVA_DOWNLOAD_URL -OutFile $JAVA_ZIP -UseBasicParsing
        Write-Info "Download complete."
    } catch {
        Die "Java download failed: $_`n  Cached at: $JAVA_ZIP (may be partial — retry this script to resume)"
    }
}

# ============================================================
# Step 3: Extract and install Java
# ============================================================
Write-Step 3 $TOTAL_STEPS "Extracting Java..."

if ($javaAlreadyInstalled) {
    Write-Info "Skipping extraction (Java already installed)."
} else {
    # Re-check: maybe installed by a prior run
    if (Test-Path $javaExePath) {
        Write-Info "Java already exists at $JAVA_INSTALL_PATH. Skipping extraction."
    } else {
        Write-Info "Extracting to $JAVA_INSTALL_PATH ..."
        try {
            $javaParent = Split-Path $JAVA_INSTALL_PATH -Parent
            if (-not (Test-Path $javaParent)) {
                New-Item -ItemType Directory -Path $javaParent -Force | Out-Null
            }

            # Record directories before extraction to identify the ZIP's top-level folder
            $dirsBefore = @(Get-ChildItem $javaParent -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)

            # Extract ZIP
            Expand-Archive -Path $JAVA_ZIP -DestinationPath $javaParent -Force

            # Dynamically identify the extracted top-level folder
            $dirsAfter = @(Get-ChildItem $javaParent -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
            $newDirName = $dirsAfter | Where-Object { $dirsBefore -notcontains $_ } | Select-Object -First 1
            $extractedFolder = if ($newDirName) { Join-Path $javaParent $newDirName } else { $null }

            if ($extractedFolder -and (Test-Path $extractedFolder) -and $extractedFolder -ne $JAVA_INSTALL_PATH) {
                Move-Item -Path $extractedFolder -Destination $JAVA_INSTALL_PATH -Force
            }
            Write-Info "Extraction complete."
        } catch {
            Die "Java extraction failed: $_`n  ZIP cached at: $JAVA_ZIP (retry this script to resume)"
        }
    }
}

# ============================================================
# Step 4: Configure environment variables
# ============================================================
if (-not $SkipEnv) {
    Write-Step 4 $TOTAL_STEPS "Configuring Java environment variables..."

    if ($javaAlreadyInstalled) {
        Write-Info "Skipping environment setup (Java already installed)."
    }

    # Set JAVA_HOME
    $currentJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    if ($currentJavaHome -ne $JAVA_INSTALL_PATH) {
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $JAVA_INSTALL_PATH, "Machine")
        $env:JAVA_HOME = $JAVA_INSTALL_PATH
        Write-Info "JAVA_HOME set to: $JAVA_INSTALL_PATH"
    } else {
        Write-Info "JAVA_HOME already correctly configured."
    }

    # Add to PATH
    $javaBin = Join-Path $JAVA_INSTALL_PATH "bin"
    Add-ToSystemPath $javaBin

    # Verify
    Write-Info "Verifying Java installation..."
    try {
        $javaVersion = & java --version 2>&1
        Write-Info "Java version: $javaVersion"
    } catch {
        Write-Warn "Java verification failed. Please restart your terminal and try again."
    }
}

# Cleanup ZIP (keep for cache reuse; temp dir handles eventual cleanup)

# --- Success message ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Java 21 installation finished!" -ForegroundColor Green
Write-Host ""
Write-Host "  Location:   $JAVA_INSTALL_PATH"
if (-not $SkipEnv) {
    Write-Host "  JAVA_HOME:  $JAVA_INSTALL_PATH"
}
Write-Host ""
Write-Host "Verify with:"
Write-Host "  java --version"
Write-Host "============================================================" -ForegroundColor Green

} finally {
    # Keep cached ZIP on error for retry; only clean zero-length files
    if ((Test-Path $JAVA_ZIP) -and (Get-Item $JAVA_ZIP).Length -eq 0) {
        Remove-Item $JAVA_ZIP -Force -ErrorAction SilentlyContinue
        Write-Info "Cleaned up zero-length ZIP: $JAVA_ZIP"
    }
}
