#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Clean,
    [string]$DownloadUrl,
    [string]$Path,
    [string]$AllureVersion,
    [switch]$SkipEnv,
    [switch]$Help,
    [switch]$Version
)

$ErrorActionPreference = "Stop"

$SCRIPT_VERSION = "1.0.0"

# Allure must be newer than this version
$MIN_VERSION = [version]"2.44.0"

# Defaults
$DEFAULT_ALLURE_VERSION = "2.45.0"
$DEFAULT_URL_TEMPLATE = "https://mirrors.huaweicloud.com/repository/maven/io/qameta/allure/allure-commandline/{0}/allure-commandline-{0}.zip"
$DEFAULT_PATH_TEMPLATE = "C:\ProgramData\Allure\allure-{0}"

# Resolve: CLI arg > env var > default
$ALLURE_VERSION = if ($AllureVersion) { $AllureVersion } elseif ($env:ALLURE_VERSION) { $env:ALLURE_VERSION } else { $DEFAULT_ALLURE_VERSION }
$ALLURE_DOWNLOAD_URL = if (-not [string]::IsNullOrWhiteSpace($DownloadUrl)) { $DownloadUrl } elseif ($env:ALLURE_DOWNLOAD_URL) { $env:ALLURE_DOWNLOAD_URL } else { $DEFAULT_URL_TEMPLATE -f $ALLURE_VERSION }
$ALLURE_INSTALL_PATH = if ($Path) { $Path } elseif ($env:ALLURE_INSTALL_PATH) { $env:ALLURE_INSTALL_PATH } else { $DEFAULT_PATH_TEMPLATE -f $ALLURE_VERSION }

$TEMP_DIR = $env:TEMP
$ALLURE_ZIP = Join-Path $TEMP_DIR "allure-commandline-$ALLURE_VERSION.zip"
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

# --- Remove stale Allure bin entries from system PATH (older versions) ---
function Remove-StaleAllurePath {
    param([string]$KeepPath)
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if (-not $currentPath) { return }
    $entries = @($currentPath -split ";")
    $stale = @($entries | Where-Object {
        $_ -match "\\allure[^\\]*\\bin\\?$" -and $_.TrimEnd('\') -ne $KeepPath.TrimEnd('\')
    })
    if ($stale.Count -gt 0) {
        $kept = @($entries | Where-Object { $stale -notcontains $_ })
        [Environment]::SetEnvironmentVariable("Path", ($kept -join ";"), "Machine")
        foreach ($s in $stale) { Write-Info "Removed stale Allure entry from system PATH: $s" }
    }
}

# --- Query Allure version from an executable; returns [version] or $null ---
function Get-AllureVersion {
    param([string]$Exe)
    try {
        $raw = (& $Exe --version 2>&1 | Out-String).Trim()
        return [version]($raw -split "\r?\n" | Select-Object -First 1).Trim()
    } catch {
        return $null
    }
}

# --- Help ---
if ($Help) {
    $name = Split-Path $PSCommandPath -Leaf
    Write-Host @"
Usage: $name [OPTIONS]

Install Allure Commandline (> $MIN_VERSION) from Huawei Maven mirror and add it to PATH.

Options:
  -Force              Force reinstall even if a suitable Allure is already detected
  -DryRun             Print detection info and download URL without executing
  -Clean              Remove cached ZIP and exit
  -DownloadUrl URL    Custom download URL (default: Huawei Maven mirror)
  -Path PATH          Custom installation path (default: C:\ProgramData\Allure\allure-<version>)
  -AllureVersion VER  Allure version to install (default: $DEFAULT_ALLURE_VERSION, must be > $MIN_VERSION)
  -SkipEnv            Skip PATH configuration
  -Help               Show this help message
  -Version            Print script version

Environment variables:
  ALLURE_VERSION       Override default version (same as -AllureVersion)
  ALLURE_DOWNLOAD_URL  Override default download URL (same as -DownloadUrl)
  ALLURE_INSTALL_PATH  Override default install path (same as -Path)

Requirements:
  Java 8+ (java.exe in PATH or JAVA_HOME set) - Allure is a JVM tool.
"@
    exit 0
}

if ($Version) {
    Write-Host $SCRIPT_VERSION
    exit 0
}

# --- Validate requested version ---
$requestedVersion = $null
try { $requestedVersion = [version]$ALLURE_VERSION } catch { }
if (-not $requestedVersion) {
    Die "Invalid Allure version format: '$ALLURE_VERSION' (expected e.g. 2.45.0)"
}
if ($requestedVersion -le $MIN_VERSION) {
    Die "Allure version must be greater than $MIN_VERSION, but '$ALLURE_VERSION' was requested."
}

# --- Clean mode ---
if ($Clean) {
    if (Test-Path $ALLURE_ZIP) {
        Remove-Item $ALLURE_ZIP -Force
        Write-Info "Removed: $ALLURE_ZIP"
    } else {
        Write-Info "No cached ZIP found at $ALLURE_ZIP"
    }
    exit 0
}

# --- Cleanup trap ---
try {

# Refresh PATH so tools installed earlier in this session (e.g. Java) are visible
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

# ============================================================
# Step 1: Detect Java prerequisite and existing Allure
# ============================================================
Write-Step 1 $TOTAL_STEPS "Detecting Java and Allure..."

# Allure needs a JVM. Prefer java.exe in PATH, fall back to JAVA_HOME.
if (Get-Command java -ErrorAction SilentlyContinue) {
    Write-Info "Java found in PATH."
} else {
    $javaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    if (-not $javaHome) { $javaHome = $env:JAVA_HOME }
    if ($javaHome -and (Test-Path (Join-Path $javaHome "bin\java.exe"))) {
        $env:Path = (Join-Path $javaHome "bin") + ";$env:Path"
        Write-Info "Java found via JAVA_HOME: $javaHome"
    } else {
        Write-Warn "Java not found (no java.exe in PATH and no valid JAVA_HOME)."
        Write-Warn "Allure will be installed, but it cannot run until Java is available (see install_java.ps1)."
    }
}

# Detect an existing Allure: target install path first, then anything in PATH
$allureAlreadyInstalled = $false
$detectedVersion = $null
$targetAllureBat = Join-Path $ALLURE_INSTALL_PATH "bin\allure.bat"
$detectedExe = if (Test-Path $targetAllureBat) { $targetAllureBat } else { (Get-Command allure -ErrorAction SilentlyContinue).Source }

if ($detectedExe) {
    $detectedVersion = Get-AllureVersion $detectedExe
    if (-not $detectedVersion) {
        Write-Warn "Allure found at $detectedExe but its version could not be determined. Will reinstall."
    } elseif ($detectedVersion -le $MIN_VERSION) {
        Write-Warn "Allure $detectedVersion found at $detectedExe, which is not greater than $MIN_VERSION. Upgrading to $ALLURE_VERSION."
    } elseif ($Force) {
        Write-Warn "Allure $detectedVersion found, but -Force is set. Will reinstall."
    } else {
        Write-Info "Allure $detectedVersion is already installed at $detectedExe (> $MIN_VERSION). Use -Force to reinstall."
        $allureAlreadyInstalled = $true
    }
} else {
    Write-Info "Allure not detected. Proceeding with installation."
}

# ============================================================
# Step 2: Dry run / Download Allure
# ============================================================
Write-Step 2 $TOTAL_STEPS "Downloading Allure $ALLURE_VERSION..."

if ($DryRun) {
    Write-Host ""
    Write-Info "[DRY-RUN] Version:      $ALLURE_VERSION (minimum: > $MIN_VERSION)"
    Write-Info "[DRY-RUN] Download URL: $ALLURE_DOWNLOAD_URL"
    Write-Info "[DRY-RUN] Install path: $ALLURE_INSTALL_PATH"
    Write-Info "[DRY-RUN] ZIP cache:    $ALLURE_ZIP"
    if ($allureAlreadyInstalled) { Write-Info "[DRY-RUN] Would skip (already installed)." }
    exit 0
}

if ($allureAlreadyInstalled) {
    Write-Info "Skipping download (Allure already installed)."
} elseif ((Test-Path $ALLURE_ZIP) -and (Get-Item $ALLURE_ZIP).Length -gt 0) {
    Write-Info "Allure ZIP already cached: $ALLURE_ZIP"
} else {
    Write-Info "Download URL: $ALLURE_DOWNLOAD_URL"
    Write-Info "Downloading (about 30 MB, this may take a few minutes)..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $ALLURE_DOWNLOAD_URL -OutFile $ALLURE_ZIP -UseBasicParsing
        Write-Info "Download complete."
    } catch {
        Die "Allure download failed: $_`n  Cached at: $ALLURE_ZIP (may be partial - retry this script to resume)"
    }
}

# ============================================================
# Step 3: Extract and install Allure
# ============================================================
Write-Step 3 $TOTAL_STEPS "Extracting Allure..."

if ($allureAlreadyInstalled) {
    Write-Info "Skipping extraction (Allure already installed)."
} elseif (Test-Path $targetAllureBat) {
    # A prior run of this script already extracted the requested version
    $existingVersion = Get-AllureVersion $targetAllureBat
    if ($existingVersion -and $existingVersion -gt $MIN_VERSION -and -not $Force) {
        Write-Info "Allure $existingVersion already exists at $ALLURE_INSTALL_PATH. Skipping extraction."
    } else {
        Write-Warn "Replacing existing installation at $ALLURE_INSTALL_PATH ..."
        Remove-Item $ALLURE_INSTALL_PATH -Recurse -Force
        $allureAlreadyInstalled = $false
    }
}

if (-not $allureAlreadyInstalled -and -not (Test-Path $targetAllureBat)) {
    Write-Info "Extracting to $ALLURE_INSTALL_PATH ..."
    # Stage extraction in TEMP so the ZIP's top-level folder can be renamed safely
    $staging = Join-Path $TEMP_DIR "allure-extract-$ALLURE_VERSION"
    try {
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
        New-Item -ItemType Directory -Path $staging -Force | Out-Null

        Expand-Archive -Path $ALLURE_ZIP -DestinationPath $staging -Force

        # The archive contains a single top-level folder (e.g. allure-2.45.0)
        $extracted = Get-ChildItem $staging -Directory | Select-Object -First 1
        if (-not $extracted) {
            Die "Allure extraction failed: no folder found inside $ALLURE_ZIP`n  ZIP cached at: $ALLURE_ZIP (delete it and retry)"
        }

        $installParent = Split-Path $ALLURE_INSTALL_PATH -Parent
        if (-not (Test-Path $installParent)) {
            New-Item -ItemType Directory -Path $installParent -Force | Out-Null
        }
        if (Test-Path $ALLURE_INSTALL_PATH) { Remove-Item $ALLURE_INSTALL_PATH -Recurse -Force }
        Move-Item -Path $extracted.FullName -Destination $ALLURE_INSTALL_PATH -Force
        Write-Info "Extraction complete."
    } catch {
        Die "Allure extraction failed: $_`n  ZIP cached at: $ALLURE_ZIP (retry this script to resume)"
    } finally {
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# Verify the launcher is in place
if (-not (Test-Path $targetAllureBat)) {
    # Allure may already have been installed elsewhere (detected in PATH); only fail if nothing is usable
    if (-not $allureAlreadyInstalled) {
        Die "Installation failed: allure.bat not found at $ALLURE_INSTALL_PATH"
    }
}

# The usable launcher: our own install if present, otherwise whatever was found on PATH
$effectiveExe = if (Test-Path $targetAllureBat) { $targetAllureBat } else { $detectedExe }
$effectiveHome = if (Test-Path $targetAllureBat) { $ALLURE_INSTALL_PATH } else { Split-Path (Split-Path $effectiveExe -Parent) -Parent }
$effectiveVersion = if (Test-Path $targetAllureBat) { $ALLURE_VERSION } else { $detectedVersion }

# ============================================================
# Step 4: Configure environment variables
# ============================================================
if (-not $SkipEnv) {
    Write-Step 4 $TOTAL_STEPS "Configuring Allure environment variables..."

    if (-not (Test-Path $targetAllureBat)) {
        Write-Info "Skipping PATH setup (Allure already installed elsewhere and on PATH)."
    } else {
        $allureBin = Join-Path $ALLURE_INSTALL_PATH "bin"
        Remove-StaleAllurePath $allureBin
        Add-ToSystemPath $allureBin
    }

    # Verify
    Write-Info "Verifying Allure installation..."
    $finalVersion = Get-AllureVersion $effectiveExe
    if ($finalVersion) {
        Write-Info "Allure version: $finalVersion"
    } else {
        Write-Warn "Allure verification failed (Java may be missing). Please restart your terminal and run: allure --version"
    }
}

# --- Success message ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Allure installation finished!" -ForegroundColor Green
Write-Host ""
Write-Host "  Location:   $effectiveHome"
Write-Host "  Version:    $effectiveVersion"
if (-not $SkipEnv) {
    Write-Host "  PATH:       $(Join-Path $effectiveHome 'bin')"
}
Write-Host ""
Write-Host "Verify with:"
Write-Host "  allure --version"
Write-Host "============================================================" -ForegroundColor Green

} finally {
    # Keep cached ZIP on error for retry; only clean zero-length files
    if ((Test-Path $ALLURE_ZIP) -and (Get-Item $ALLURE_ZIP).Length -eq 0) {
        Remove-Item $ALLURE_ZIP -Force -ErrorAction SilentlyContinue
        Write-Info "Cleaned up zero-length ZIP: $ALLURE_ZIP"
    }
}