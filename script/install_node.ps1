#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Clean,
    [string]$DownloadUrl,
    [string]$Path,
    [string]$NodeVersion,
    [switch]$SkipEnv,
    [switch]$Help,
    [switch]$Version
)

$ErrorActionPreference = "Stop"

$SCRIPT_VERSION = "1.0.0"

# Defaults
# Huawei mirror is used instead of Tsinghua: the Tsinghua nodejs-release mirror
# lags behind (its index.json stops at v24.1.0 and newer LTS paths return 404).
$MIRROR_BASE = "https://mirrors.huaweicloud.com/nodejs"
$FALLBACK_VERSION = "v24.19.0"          # used when the LTS index cannot be fetched
$DEFAULT_INSTALL_PATH = "C:\ProgramData\nodejs"

$INSTALL_PATH = if ($Path) { $Path } elseif ($env:NODE_INSTALL_PATH) { $env:NODE_INSTALL_PATH } else { $DEFAULT_INSTALL_PATH }
$TEMP_DIR = $env:TEMP
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

Install Node.js (latest LTS) from Huawei mirror and add it to PATH.
npm ships inside the Node.js archive, so no separate npm install is needed.

Options:
  -Force            Force reinstall even if Node.js is already detected
  -DryRun           Print detection info and download URL without executing
  -Clean            Remove cached ZIP and exit
  -DownloadUrl URL  Custom download URL (overrides mirror and version)
  -Path PATH        Custom installation path (default: $DEFAULT_INSTALL_PATH)
  -NodeVersion VER  Install a specific version, e.g. v24.19.0 (default: latest LTS)
  -SkipEnv          Skip PATH configuration
  -Help             Show this help message
  -Version          Print script version

Environment variables:
  NODE_INSTALL_PATH  Override default install path (same as -Path)
  NODE_VERSION       Override version to install (same as -NodeVersion)

Notes:
  Node.js 24 ships Windows builds for x64 and arm64 only (no 32-bit x86).
"@
    exit 0
}

if ($Version) {
    Write-Host $SCRIPT_VERSION
    exit 0
}

# --- Clean mode (globs every cached Node.js archive; needs no version resolution) ---
if ($Clean) {
    $cached = @(Get-ChildItem $TEMP_DIR -Filter "node-v*-win-*.zip" -ErrorAction SilentlyContinue)
    if ($cached.Count -eq 0) {
        Write-Info "No cached Node.js ZIP found in $TEMP_DIR"
    } else {
        foreach ($c in $cached) {
            Remove-Item $c.FullName -Force
            Write-Info "Removed: $($c.FullName)"
        }
    }
    exit 0
}

# --- Cleanup trap (ZIP path is only known after version resolution) ---
$NODE_ZIP = $null
try {

# Refresh PATH so tools installed earlier in this session are visible
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

# ============================================================
# Step 1: Detect environment and resolve version
# ============================================================
Write-Step 1 $TOTAL_STEPS "Detecting environment and resolving Node.js version..."

# Architecture -> Node.js archive suffix
switch ($env:PROCESSOR_ARCHITECTURE) {
    "AMD64" { $NODE_ARCH = "win-x64" }
    "ARM64" { $NODE_ARCH = "win-arm64" }
    "x86"   { Die "32-bit Windows is not supported: Node.js 24 no longer ships win-x86 builds. Install Node.js 20 manually if you need 32-bit." }
    default { Die "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
}
Write-Info "Architecture: $NODE_ARCH"

# Resolve version: CLI arg > env var > latest LTS from mirror index > fallback
$requestedVersion = if ($NodeVersion) { $NodeVersion } elseif ($env:NODE_VERSION) { $env:NODE_VERSION } else { $null }

if ($requestedVersion) {
    $NODE_VER = if ($requestedVersion.StartsWith("v")) { $requestedVersion } else { "v$requestedVersion" }
    Write-Info "Using requested Node.js version: $NODE_VER"
} else {
    Write-Info "Querying latest LTS from $MIRROR_BASE/index.json ..."
    $NODE_VER = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $index = Invoke-RestMethod -Uri "$MIRROR_BASE/index.json" -UseBasicParsing -TimeoutSec 30
        # The index is ordered newest-first; "lts" is false for non-LTS and the codename for LTS
        $ltsEntry = $index | Where-Object { $_.lts } | Select-Object -First 1
        if ($ltsEntry) {
            $NODE_VER = $ltsEntry.version
            Write-Info "Latest LTS: $NODE_VER (codename $($ltsEntry.lts), bundled npm $($ltsEntry.npm))"
        }
    } catch {
        Write-Warn "Could not query the LTS index: $_"
    }
    if (-not $NODE_VER) {
        $NODE_VER = $FALLBACK_VERSION
        Write-Warn "Falling back to pinned version $NODE_VER"
    }
}

$NODE_DIR_NAME = "node-$NODE_VER-$NODE_ARCH"
$NODE_ZIP = Join-Path $TEMP_DIR "$NODE_DIR_NAME.zip"
$NODE_DOWNLOAD_URL = if (-not [string]::IsNullOrWhiteSpace($DownloadUrl)) { $DownloadUrl } else { "$MIRROR_BASE/$NODE_VER/$NODE_DIR_NAME.zip" }

# Detect existing Node.js: target install path first, then anything in PATH
$nodeExePath = Join-Path $INSTALL_PATH "node.exe"
$nodeAlreadyInstalled = $false
$detectedNode = if (Test-Path $nodeExePath) { $nodeExePath } else { (Get-Command node -ErrorAction SilentlyContinue).Source }

if ($detectedNode) {
    $existingVer = try { (& $detectedNode --version 2>&1 | Out-String).Trim() } catch { "unknown" }
    if ($Force) {
        Write-Warn "Node.js $existingVer found at $detectedNode, but -Force is set. Will reinstall."
    } else {
        Write-Info "Node.js $existingVer is already installed at $detectedNode. Use -Force to reinstall."
        $nodeAlreadyInstalled = $true
    }
} else {
    Write-Info "Node.js not detected. Proceeding with installation."
}

# ============================================================
# Step 2: Dry run / Download Node.js
# ============================================================
Write-Step 2 $TOTAL_STEPS "Downloading Node.js $NODE_VER..."

if ($DryRun) {
    Write-Host ""
    Write-Info "[DRY-RUN] Version:      $NODE_VER"
    Write-Info "[DRY-RUN] Architecture: $NODE_ARCH"
    Write-Info "[DRY-RUN] Download URL: $NODE_DOWNLOAD_URL"
    Write-Info "[DRY-RUN] Install path: $INSTALL_PATH"
    Write-Info "[DRY-RUN] ZIP cache:    $NODE_ZIP"
    if ($nodeAlreadyInstalled) { Write-Info "[DRY-RUN] Would skip (already installed)." }
    exit 0
}

if ($nodeAlreadyInstalled) {
    Write-Info "Skipping download (Node.js already installed)."
} elseif ((Test-Path $NODE_ZIP) -and (Get-Item $NODE_ZIP).Length -gt 0) {
    Write-Info "Node.js ZIP already cached: $NODE_ZIP"
} else {
    Write-Info "Download URL: $NODE_DOWNLOAD_URL"
    Write-Info "Downloading (about 30 MB, this may take a few minutes)..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $NODE_DOWNLOAD_URL -OutFile $NODE_ZIP -UseBasicParsing
        Write-Info "Download complete."
    } catch {
        Die "Node.js download failed: $_`n  Cached at: $NODE_ZIP (may be partial - retry this script to resume)"
    }
}

# ============================================================
# Step 3: Extract and install Node.js
# ============================================================
Write-Step 3 $TOTAL_STEPS "Extracting Node.js..."

if ($nodeAlreadyInstalled) {
    Write-Info "Skipping extraction (Node.js already installed)."
} elseif ((Test-Path $nodeExePath) -and -not $Force) {
    Write-Info "Node.js already exists at $INSTALL_PATH. Skipping extraction."
} else {
    Write-Info "Extracting to $INSTALL_PATH ..."
    # Stage extraction in TEMP so the archive's top-level folder can be renamed safely
    $staging = Join-Path $TEMP_DIR "node-extract-$NODE_VER"
    try {
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
        New-Item -ItemType Directory -Path $staging -Force | Out-Null

        Expand-Archive -Path $NODE_ZIP -DestinationPath $staging -Force

        # The archive contains a single top-level folder (e.g. node-v24.19.0-win-x64)
        $extracted = Get-ChildItem $staging -Directory | Select-Object -First 1
        if (-not $extracted) {
            Die "Node.js extraction failed: no folder found inside $NODE_ZIP (delete it and retry)"
        }

        $installParent = Split-Path $INSTALL_PATH -Parent
        if (-not (Test-Path $installParent)) {
            New-Item -ItemType Directory -Path $installParent -Force | Out-Null
        }
        if (Test-Path $INSTALL_PATH) { Remove-Item $INSTALL_PATH -Recurse -Force }
        Move-Item -Path $extracted.FullName -Destination $INSTALL_PATH -Force
        Write-Info "Extraction complete."
    } catch {
        Die "Node.js extraction failed: $_`n  ZIP cached at: $NODE_ZIP (retry this script to resume)"
    } finally {
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# The usable Node.js: our own install if present, otherwise whatever was found on PATH
$effectiveNode = if (Test-Path $nodeExePath) { $nodeExePath } else { $detectedNode }
if (-not $effectiveNode) {
    Die "Installation failed: node.exe not found at $INSTALL_PATH"
}
$effectiveHome = Split-Path $effectiveNode -Parent

# Read the version actually on disk - it differs from $NODE_VER when an existing
# installation elsewhere was reused instead of downloading the resolved LTS.
$effectiveVersion = try { (& $effectiveNode --version 2>&1 | Out-String).Trim() } catch { $NODE_VER }
if (-not $effectiveVersion) { $effectiveVersion = $NODE_VER }

# ============================================================
# Step 4: Configure environment variables
# ============================================================
if (-not $SkipEnv) {
    Write-Step 4 $TOTAL_STEPS "Configuring Node.js environment variables..."

    if ((Test-Path $nodeExePath)) {
        # node.exe and npm.cmd both live in the archive root, so one PATH entry is enough
        Add-ToSystemPath $INSTALL_PATH
    } else {
        Write-Info "Skipping PATH setup (Node.js already installed elsewhere and on PATH)."
    }

    # Verify
    Write-Info "Verifying Node.js installation..."
    Write-Info "node $effectiveVersion"

    $npmCmd = Join-Path $effectiveHome "npm.cmd"
    if (Test-Path $npmCmd) {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $npmVer = try { (& $npmCmd --version 2>$null | Out-String).Trim() } catch { $null }
        $ErrorActionPreference = $prevEap
        if ($npmVer) { Write-Info "npm $npmVer" } else { Write-Warn "npm --version failed." }
    } else {
        Write-Warn "npm.cmd not found next to node.exe at $effectiveHome"
    }
}

# --- Success message ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Node.js installation finished!" -ForegroundColor Green
Write-Host ""
Write-Host "  Location:   $effectiveHome"
Write-Host "  Version:    $effectiveVersion"
if (-not $SkipEnv) {
    Write-Host "  PATH:       $effectiveHome"
}
Write-Host ""
Write-Host "Verify with:"
Write-Host "  node --version"
Write-Host "  npm --version"
Write-Host "============================================================" -ForegroundColor Green

} finally {
    # Keep cached ZIP on error for retry; only clean zero-length files
    if ($NODE_ZIP -and (Test-Path $NODE_ZIP) -and (Get-Item $NODE_ZIP).Length -eq 0) {
        Remove-Item $NODE_ZIP -Force -ErrorAction SilentlyContinue
        Write-Info "Cleaned up zero-length ZIP: $NODE_ZIP"
    }
}