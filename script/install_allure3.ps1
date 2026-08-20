#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun,
    [string]$AllureVersion,
    [string]$Registry,
    [string]$NodePath,
    [string]$NodeVersion,
    [string]$NodeDownloadUrl,
    [switch]$SkipNode,
    [switch]$Help,
    [switch]$Version
)

$ErrorActionPreference = "Stop"

$SCRIPT_VERSION = "1.0.0"

# Allure 3 is a TypeScript rewrite distributed only as the npm package "allure"
# (no standalone archive exists), so Node.js + npm are hard requirements.
$DEFAULT_REGISTRY = "https://registry.npmmirror.com"
$OFFICIAL_REGISTRY = "https://registry.npmjs.org"
$PACKAGE_NAME = "allure"

# Allure 3 安装参数（优先级：CLI > 环境变量 > 默认值）
$ALLURE3_VERSION = if ($AllureVersion) { $AllureVersion } elseif ($env:ALLURE3_VERSION) { $env:ALLURE3_VERSION } else { "latest" }
$NPM_REGISTRY = if ($Registry) { $Registry } elseif ($env:ALLURE3_REGISTRY) { $env:ALLURE3_REGISTRY } else { $DEFAULT_REGISTRY }

# Node.js 安装参数（幂等逻辑：仅在 Node.js 不存在或 -Force 时安装）
$DEFAULT_NODE_INSTALL_PATH = "C:\ProgramData\nodejs"
$NODE_INSTALL_PATH = if ($NodePath) { $NodePath } elseif ($env:NODE_INSTALL_PATH) { $env:NODE_INSTALL_PATH } else { $DEFAULT_NODE_INSTALL_PATH }
$NODE_VER = if ($NodeVersion) { $NodeVersion } elseif ($env:NODE_VERSION) { $env:NODE_VERSION } else { $null }
$NODE_DOWNLOAD_URL = $NodeDownloadUrl  # 允许外部传入自定义 URL

# Huawei mirror for Node.js (avoids Tsinghua mirror which lags behind)
$MIRROR_BASE = "https://mirrors.huaweicloud.com/nodejs"
$FALLBACK_VERSION = "v24.19.0"

$TEMP_DIR = $env:TEMP
$TOTAL_STEPS = 6  # Max steps: 1-Check, 2-NodeInstall, 3-VerifyNpm, 4-Resolve, 5-Install, 6-Verify

# Dynamic step tracking
$currentStep = 0
function NextStep { $script:currentStep++; return $script:currentStep }
function DoStep($label) { $script:currentStep++; Write-Step $script:currentStep $TOTAL_STEPS $label }

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

# --- npm wrapper: npm writes warnings to stderr, which would trip
#     $ErrorActionPreference = "Stop" as a NativeCommandError.
#     -StdOutOnly discards stderr so that --json output stays parseable. ---
function Invoke-Npm {
    param(
        [string[]]$NpmArgs,
        [switch]$StdOutOnly
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        if ($StdOutOnly) {
            $out = (& $script:NPM_EXE @NpmArgs 2>$null | Out-String)
        } else {
            $out = (& $script:NPM_EXE @NpmArgs 2>&1 | Out-String)
        }
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out.Trim() }
    } finally {
        $ErrorActionPreference = $prev
    }
}

# --- Read the globally installed version of a package via npm ls --json.
#     Returns the version string, or $null when the package is absent. ---
function Get-GlobalNpmVersion {
    param([string]$Name)
    # npm ls exits 1 for a missing package (and for unrelated tree warnings),
    # so the JSON is parsed regardless of the exit code.
    $result = Invoke-Npm -StdOutOnly -NpmArgs @("ls", "-g", $Name, "--depth=0", "--json")
    if (-not $result.Output) { return $null }
    $json = $result.Output
    $start = $json.IndexOf("{")
    $end = $json.LastIndexOf("}")
    if ($start -lt 0 -or $end -le $start) { return $null }
    try {
        $parsed = $json.Substring($start, $end - $start + 1) | ConvertFrom-Json
    } catch {
        Write-Warn "Could not parse 'npm ls -g $Name' output."
        return $null
    }
    if ($parsed.dependencies -and $parsed.dependencies.$Name) {
        return $parsed.dependencies.$Name.version
    }
    return $null
}

# --- Help ---
if ($Help) {
    $name = Split-Path $PSCommandPath -Leaf
    Write-Host @"
Usage: $name [OPTIONS]

Install Allure 3 (npm package "$PACKAGE_NAME") globally via npm.
This script handles Node.js installation idempotently if needed.

Options:
  -Force              Reinstall even if the latest Allure 3 is already present
  -DryRun             Print detection info and the npm command without executing
  -AllureVersion VER   Version to install, e.g. 3.14.3 (default: latest)
  -Registry URL       npm registry (default: $DEFAULT_REGISTRY)
                      Official registry: $OFFICIAL_REGISTRY
  -NodePath PATH      Node.js installation path (default: $DEFAULT_NODE_INSTALL_PATH)
  -NodeVersion VER    Node.js version to install, e.g. v24.19.0 (default: latest LTS)
  -NodeDownloadUrl URL Override Node.js download URL
  -SkipNode           Skip Node.js installation (assume Node.js is already available)
  -Help               Show this help message
  -Version            Print script version

Environment variables:
  ALLURE3_VERSION   Override version to install (same as -AllureVersion)
  ALLURE3_REGISTRY  Override npm registry (same as -Registry)
  NODE_INSTALL_PATH Override Node.js install path (same as -NodePath)
  NODE_VERSION      Override Node.js version (same as -NodeVersion)

Notes:
  Allure 2 and Allure 3 both provide an "allure" command. If Allure 2 is also
  installed, whichever PATH entry comes first wins; this script warns about it.

  Node.js is installed idempotently: it is only downloaded/extracted when
  node.exe is not found at the target path or in PATH.
"@
    exit 0
}

if ($Version) {
    Write-Host $SCRIPT_VERSION
    exit 0
}

# Refresh PATH so Node.js installed earlier in this session is visible
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

# ============================================================
# Step 1: Idempotent Node.js installation (only if not found)
# ============================================================
DoStep "Checking Node.js installation..."

$nodeExePath = Join-Path $NODE_INSTALL_PATH "node.exe"
$detectedNode = $null

# Check target path first, then PATH
if (Test-Path $nodeExePath) {
    $detectedNode = $nodeExePath
} else {
    $existingNode = Get-Command node -ErrorAction SilentlyContinue
    if ($existingNode) { $detectedNode = $existingNode.Source }
}

if ($detectedNode) {
    $existingVer = try { (& $detectedNode --version 2>&1 | Out-String).Trim() } catch { "unknown" }
    Write-Info "Node.js $existingVer found at $detectedNode"
    if ($Force) {
        Write-Warn "-Force is set. Will reinstall Node.js."
    } else {
        Write-Info "Node.js already installed. Skipping download/extraction."
        $skipNodeInstall = $true
    }
} else {
    Write-Info "Node.js not found. Proceeding with installation."
    $skipNodeInstall = $false
}

# --- Node.js Download & Extract (only when needed) ---
if (-not $SkipNode -and -not $skipNodeInstall) {
    DoStep "Installing Node.js..."

    # Resolve architecture
    switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { $NODE_ARCH = "win-x64" }
        "ARM64" { $NODE_ARCH = "win-arm64" }
        "x86"   { Die "32-bit Windows is not supported for Node.js 24+" }
        default { Die "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
    }
    Write-Info "Architecture: $NODE_ARCH"

    # Resolve version
    if ($NODE_VER) {
        $NODE_VER_FULL = if ($NODE_VER.StartsWith("v")) { $NODE_VER } else { "v$NODE_VER" }
        Write-Info "Using requested Node.js version: $NODE_VER_FULL"
    } else {
        Write-Info "Querying latest LTS from $MIRROR_BASE/index.json ..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $index = Invoke-RestMethod -Uri "$MIRROR_BASE/index.json" -UseBasicParsing -TimeoutSec 30
            $ltsEntry = $index | Where-Object { $_.lts } | Select-Object -First 1
            if ($ltsEntry) {
                $NODE_VER_FULL = $ltsEntry.version
                Write-Info "Latest LTS: $NODE_VER_FULL (npm $($ltsEntry.npm))"
            }
        } catch {
            Write-Warn "Could not query LTS index: $_"
        }
        if (-not $NODE_VER_FULL) {
            $NODE_VER_FULL = $FALLBACK_VERSION
            Write-Warn "Falling back to $NODE_VER_FULL"
        }
    }

    $NODE_DIR_NAME = "node-$NODE_VER_FULL-$NODE_ARCH"
    $NODE_ZIP = if ($NODE_DOWNLOAD_URL) { $null } else { Join-Path $TEMP_DIR "$NODE_DIR_NAME.zip" }
    $downloadUrl = if ($NODE_DOWNLOAD_URL) { $NODE_DOWNLOAD_URL } else { "$MIRROR_BASE/$NODE_VER_FULL/$NODE_DIR_NAME.zip" }

    if ($DryRun) {
        Write-Host ""
        Write-Info "[DRY-RUN] Node.js Version:      $NODE_VER_FULL"
        Write-Info "[DRY-RUN] Node.js Architecture: $NODE_ARCH"
        Write-Info "[DRY-RUN] Download URL:         $downloadUrl"
        Write-Info "[DRY-RUN] Install path:         $NODE_INSTALL_PATH"
    } else {
        # Download
        if ($NODE_ZIP -and (Test-Path $NODE_ZIP) -and (Get-Item $NODE_ZIP).Length -gt 0) {
            Write-Info "Node.js ZIP already cached: $NODE_ZIP"
        } else {
            Write-Info "Download URL: $downloadUrl"
            Write-Info "Downloading (about 30 MB)..."
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                if ($NODE_ZIP) {
                    Invoke-WebRequest -Uri $downloadUrl -OutFile $NODE_ZIP -UseBasicParsing
                } else {
                    # Custom URL: download directly to temp with temp name
                    Invoke-WebRequest -Uri $downloadUrl -OutFile (Join-Path $TEMP_DIR "$NODE_DIR_NAME.zip") -UseBasicParsing
                    $NODE_ZIP = Join-Path $TEMP_DIR "$NODE_DIR_NAME.zip"
                }
                Write-Info "Download complete."
            } catch {
                Die "Node.js download failed: $_"
            }
        }

        # Extract
        Write-Info "Extracting to $NODE_INSTALL_PATH ..."
        $staging = Join-Path $TEMP_DIR "node-extract-$NODE_VER_FULL"
        try {
            if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
            New-Item -ItemType Directory -Path $staging -Force | Out-Null
            Expand-Archive -Path $NODE_ZIP -DestinationPath $staging -Force

            $extracted = Get-ChildItem $staging -Directory | Select-Object -First 1
            if (-not $extracted) { Die "Extraction failed: no folder in archive" }

            $installParent = Split-Path $NODE_INSTALL_PATH -Parent
            if (-not (Test-Path $installParent)) { New-Item -ItemType Directory -Path $installParent -Force | Out-Null }
            if (Test-Path $NODE_INSTALL_PATH) { Remove-Item $NODE_INSTALL_PATH -Recurse -Force }
            Move-Item -Path $extracted.FullName -Destination $NODE_INSTALL_PATH -Force
            Write-Info "Extraction complete."
        } catch {
            Die "Node.js extraction failed: $_"
        } finally {
            if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
        }

        # Add to PATH
        Add-ToSystemPath $NODE_INSTALL_PATH
        Write-Info "Node.js $NODE_VER_FULL installed at $NODE_INSTALL_PATH"
    }
}

# Refresh PATH after potential Node.js installation
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

# ============================================================
# Verify npm is functional
# ============================================================
DoStep "Verifying npm..."

$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Die "Node.js is not in PATH after installation. Please restart your terminal and re-run this script."
}
$nodeVersion = try { (& node --version 2>&1 | Out-String).Trim() } catch { "unknown" }
Write-Info "node $nodeVersion at $($nodeCmd.Source)"

# npm ships next to node.exe as npm.cmd
$NPM_EXE = $null
$npmSibling = Join-Path (Split-Path $nodeCmd.Source -Parent) "npm.cmd"
if (Test-Path $npmSibling) {
    $NPM_EXE = $npmSibling
} else {
    $npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npmCmd) { $npmCmd = Get-Command npm -ErrorAction SilentlyContinue }
    if ($npmCmd) { $NPM_EXE = $npmCmd.Source }
}
if (-not $NPM_EXE) {
    Die "npm not found. Please reinstall Node.js."
}

$npmVersionResult = Invoke-Npm -StdOutOnly -NpmArgs @("--version")
if ($npmVersionResult.ExitCode -ne 0 -or -not $npmVersionResult.Output) {
    Die "npm is not runnable: $($npmVersionResult.Output)"
}
Write-Info "npm $($npmVersionResult.Output) at $NPM_EXE"

# ============================================================
# Resolve target version and detect existing Allure 3
# ============================================================
DoStep "Resolving Allure 3 version..."

# Resolve "latest" against the registry so an installed copy can be compared
$targetVersion = $null
if ($ALLURE3_VERSION -eq "latest") {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $meta = Invoke-RestMethod -Uri "$NPM_REGISTRY/$PACKAGE_NAME/latest" -UseBasicParsing -TimeoutSec 30
        $targetVersion = $meta.version
        Write-Info "Latest $PACKAGE_NAME on $NPM_REGISTRY is $targetVersion"
    } catch {
        Write-Warn "Could not resolve the latest version from the registry: $_"
        Write-Warn "npm will resolve '$PACKAGE_NAME@latest' on its own."
    }
} else {
    $targetVersion = $ALLURE3_VERSION
    Write-Info "Requested version: $targetVersion"
}

# What is installed globally right now?
$installedVersion = Get-GlobalNpmVersion $PACKAGE_NAME

$skipInstall = $false
if ($installedVersion) {
    Write-Info "Allure 3 $installedVersion is already installed globally."
    if ($Force) {
        Write-Warn "Force flag set. Will reinstall."
    } elseif ($targetVersion -and $installedVersion -eq $targetVersion) {
        Write-Info "Already at the target version ($targetVersion). Nothing to do."
        $skipInstall = $true
    } elseif ($targetVersion) {
        Write-Info "Updating $installedVersion -> $targetVersion"
    } else {
        Write-Info "Reinstalling to pick up the latest version."
    }
} else {
    Write-Info "Allure 3 is not installed globally. Proceeding with installation."
}

# The exact spec handed to npm
$packageSpec = if ($targetVersion) { "$PACKAGE_NAME@$targetVersion" } else { "$PACKAGE_NAME@latest" }

# ============================================================
# Install Allure 3 via npm
# ============================================================
DoStep "Installing $packageSpec..."

if ($DryRun) {
    Write-Host ""
    Write-Info "[DRY-RUN] Package:  $packageSpec"
    Write-Info "[DRY-RUN] Registry: $NPM_REGISTRY"
    Write-Info "[DRY-RUN] Command:  npm install -g $packageSpec --registry $NPM_REGISTRY"
    Write-Info "[DRY-RUN] npm:      $NPM_EXE"
    if ($installedVersion) { Write-Info "[DRY-RUN] Installed now: $installedVersion" }
    if ($skipInstall) { Write-Info "[DRY-RUN] Would skip (already at target version)." }
    exit 0
}

if ($skipInstall) {
    Write-Info "Skipping npm install (already at $installedVersion)."
} else {
    Write-Info "Registry: $NPM_REGISTRY"
    Write-Info "Running: npm install -g $packageSpec (this may take a few minutes)..."
    $installResult = Invoke-Npm @("install", "-g", $packageSpec, "--registry", $NPM_REGISTRY)
    if ($installResult.ExitCode -ne 0) {
        Write-Host $installResult.Output
        Die "npm install failed with exit code $($installResult.ExitCode).`n  Retry, or try the official registry: -Registry $OFFICIAL_REGISTRY"
    }
    Write-Info "npm install complete."
}

# ============================================================
# Verify and check PATH
# ============================================================
DoStep "Verifying Allure 3 installation..."

# Global binaries land in the npm prefix; make sure it is reachable
$prefixResult = Invoke-Npm -StdOutOnly -NpmArgs @("prefix", "-g")
$npmPrefix = if ($prefixResult.ExitCode -eq 0 -and $prefixResult.Output) { $prefixResult.Output } else { $null }
if ($npmPrefix) {
    Write-Info "npm global prefix: $npmPrefix"
    $allureShim = Join-Path $npmPrefix "allure.cmd"
    if ((Test-Path $allureShim) -and -not (Get-Command allure -ErrorAction SilentlyContinue)) {
        Write-Warn "The npm global prefix is not on PATH. Adding it."
        Add-ToSystemPath $npmPrefix
    }
}

# Warn about the Allure 2 / Allure 3 command name clash
$allureOnPath = Get-Command allure -ErrorAction SilentlyContinue
if ($allureOnPath) {
    Write-Info "'allure' resolves to: $($allureOnPath.Source)"
    if ($npmPrefix -and (Split-Path $allureOnPath.Source -Parent).TrimEnd('\') -ne $npmPrefix.TrimEnd('\')) {
        Write-Warn "'allure' currently resolves OUTSIDE the npm prefix - most likely an Allure 2"
        Write-Warn "installation earlier in PATH. Allure 3's binary is at: $(Join-Path $npmPrefix 'allure.cmd')"
        Write-Warn "Remove the Allure 2 bin directory from PATH, or call Allure 3 by full path."
    }
}

$finalVersion = Get-GlobalNpmVersion $PACKAGE_NAME
if ($finalVersion) {
    Write-Info "Allure 3 $finalVersion is installed."
} else {
    Write-Warn "Could not confirm the installed version via npm. Run: npm ls -g allure"
}

# --- Success message ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Allure 3 installation finished!" -ForegroundColor Green
Write-Host ""
Write-Host "  Package:    $PACKAGE_NAME"
Write-Host "  Version:    $(if ($finalVersion) { $finalVersion } else { $packageSpec })"
Write-Host "  Registry:   $NPM_REGISTRY"
if ($npmPrefix) {
    Write-Host "  Binary:     $(Join-Path $npmPrefix 'allure.cmd')"
}
Write-Host ""
Write-Host "Verify with (restart your terminal first):"
Write-Host "  allure --version"
Write-Host "============================================================" -ForegroundColor Green