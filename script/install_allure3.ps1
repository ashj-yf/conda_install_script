#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun,
    [string]$AllureVersion,
    [string]$Registry,
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

# Resolve: CLI arg > env var > default
$ALLURE3_VERSION = if ($AllureVersion) { $AllureVersion } elseif ($env:ALLURE3_VERSION) { $env:ALLURE3_VERSION } else { "latest" }
$NPM_REGISTRY = if ($Registry) { $Registry } elseif ($env:ALLURE3_REGISTRY) { $env:ALLURE3_REGISTRY } else { $DEFAULT_REGISTRY }

$TOTAL_STEPS = 4

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

Allure 3 is distributed only through npm and requires Node.js. Install Node.js
first (see install_node.ps1) - this script will not install it for you.

Options:
  -Force              Reinstall even if the latest Allure 3 is already present
  -DryRun             Print detection info and the npm command without executing
  -AllureVersion VER  Version to install, e.g. 3.14.3 (default: latest)
  -Registry URL       npm registry (default: $DEFAULT_REGISTRY)
                      Official registry: $OFFICIAL_REGISTRY
  -Help               Show this help message
  -Version            Print script version

Environment variables:
  ALLURE3_VERSION   Override version to install (same as -AllureVersion)
  ALLURE3_REGISTRY  Override npm registry (same as -Registry)

Notes:
  Allure 2 and Allure 3 both provide an "allure" command. If Allure 2 is also
  installed, whichever PATH entry comes first wins; this script warns about it.
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
# Step 1: Verify Node.js / npm prerequisite
# ============================================================
Write-Step 1 $TOTAL_STEPS "Checking Node.js and npm..."

$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Die "Node.js is required but not found in PATH.`n  Install it first: .\install_node.ps1  (or open a new terminal if it was just installed)"
}
$nodeVersion = try { (& node --version 2>&1 | Out-String).Trim() } catch { "unknown" }
Write-Info "node $nodeVersion at $($nodeCmd.Source)"

# npm ships next to node.exe as npm.cmd; prefer that over PATH lookup
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
    Die "npm was not found next to node.exe or in PATH. Reinstall Node.js (see install_node.ps1)."
}

$npmVersionResult = Invoke-Npm -StdOutOnly -NpmArgs @("--version")
if ($npmVersionResult.ExitCode -ne 0 -or -not $npmVersionResult.Output) {
    Die "npm is present but not runnable: $($npmVersionResult.Output)"
}
Write-Info "npm $($npmVersionResult.Output) at $NPM_EXE"

# ============================================================
# Step 2: Resolve target version and detect existing Allure 3
# ============================================================
Write-Step 2 $TOTAL_STEPS "Resolving Allure 3 version..."

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
# Step 3: Install Allure 3 via npm
# ============================================================
Write-Step 3 $TOTAL_STEPS "Installing $packageSpec..."

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
# Step 4: Verify and check PATH
# ============================================================
Write-Step 4 $TOTAL_STEPS "Verifying Allure 3 installation..."

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