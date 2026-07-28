#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet("github", "gitee")]
    [string]$Mirror = "gitee",
    [switch]$DryRun,
    [switch]$Offline
)

$ErrorActionPreference = "Stop"

# ==================== 配置 ====================
# Java 下载地址（可在此处修改，或通过环境变量覆盖）
$env:JAVA_DOWNLOAD_URL = "https://mirrors.huaweicloud.com/openjdk/21.0.2/openjdk-21.0.2_windows-x64_bin.zip"

# 安装路径
$JAVA_INSTALL_PATH = "C:\ProgramData\Java\jdk-21"
$MINICONDA_INSTALL_PATH = $env:CONDA_INSTALL_PATH, "C:\ProgramData\miniconda3" | Select-Object -First 1

# ==================== 远程脚本地址 ====================
# 远程仓库基础 URL
$GITHUB_BASE = "https://raw.githubusercontent.com/ashj-yf/conda_install_script/master"
$GITEE_BASE = "https://gitee.com/ashj-yf/conda_install_script/raw/master"
$BASE_URL = if ($Mirror -eq "github") { $GITHUB_BASE } else { $GITEE_BASE }

# 各组件独立脚本
$SCRIPTS = @{
    Chrome    = "$BASE_URL/script/install_chrome.ps1"
    Java      = "$BASE_URL/script/install_java.ps1"
    Git       = "$BASE_URL/script/install_git.ps1"
    Miniconda = "$BASE_URL/script/install_miniconda.ps1"
}

# 临时目录
$TEMP_DIR = $env:TEMP
$TOTAL_STEPS = 4

# 本脚本自身的远程地址（用于 iex 管道方式自动提权时重新下载到临时文件）
$DEV_ENV_SCRIPT_URL = "$BASE_URL/install_dev_env.ps1"
$DEV_ENV_SCRIPT = $MyInvocation.MyCommand.Path
# ==================== 配置结束 ====================

# --- 日志函数 ---
function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Die($msg) { Write-Err $msg; exit 1 }
function Write-Step($n, $msg) { Write-Host ""; Write-Host "[$n/$TOTAL_STEPS] " -ForegroundColor Cyan -NoNewline; Write-Host $msg -ForegroundColor White -NoNewline; Write-Host " ..." }

# --- 下载并执行子脚本 ---
function Invoke-SubScript {
    param(
        [string]$ScriptName,
        [string]$ScriptUrl,
        [hashtable]$Arguments = @{}
    )

    $localScript = Join-Path $TEMP_DIR $ScriptName

    # 下载脚本
    if (-not $Offline) {
        if ((Test-Path $localScript) -and (Get-Item $localScript).Length -gt 0) {
            Write-Info "子脚本已缓存: $localScript"
        } else {
            Write-Info "正在下载子脚本: $ScriptUrl"
            try {
                Invoke-WebRequest -Uri $ScriptUrl -OutFile $localScript -UseBasicParsing
            } catch {
                Write-Warn "子脚本下载失败: $_"
                return $false
            }
        }
    } else {
        # 离线模式：优先使用当前目录下 script/ 子目录中的脚本
        $localFallback = Join-Path (Split-Path $DEV_ENV_SCRIPT -Parent) "script\$ScriptName"
        if (Test-Path $localFallback) {
            $localScript = $localFallback
            Write-Info "离线模式，使用本地脚本: $localScript"
        } elseif (-not (Test-Path $localScript)) {
            Write-Warn "离线模式下找不到子脚本: $ScriptName（请将脚本放在与 install_dev_env.ps1 相同目录，或先在线运行一次以缓存到 TEMP）"
            return $false
        }
    }

    # 构建参数列表
    $argList = @("-ExecutionPolicy", "Bypass", "-NoProfile", "-File", "`"$localScript`"")
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ($value -is [switch] -and $value.IsPresent) {
            $argList += "-$key"
        } elseif ($value -is [string] -and $value) {
            $argList += "-$key"
            $argList += "`"$value`""
        }
    }

    # 执行
    try {
        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -ne 0) {
            Write-Warn "$ScriptName 执行完成（退出码: $($proc.ExitCode)）"
            return $false
        }
        return $true
    } catch {
        Write-Warn "$ScriptName 执行失败: $_"
        return $false
    } finally {
        # 执行后清理子脚本（除非离线模式使用本地脚本）
        if (-not $Offline -and (Test-Path $localScript) -and $localScript.StartsWith($TEMP_DIR, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item $localScript -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- 清理函数 ---
function Remove-TempFiles {
    Write-Host ""
    Write-Info "正在清理临时文件..."

    $patterns = @("ChromeSetup.exe", "GitSetup.exe", "openjdk-*.zip", "install_*.ps1")
    foreach ($pattern in $patterns) {
        Get-ChildItem $TEMP_DIR -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Info "已删除: $($_.FullName)"
        }
    }

    # 清理自身（仅当脚本位于临时目录时，即远程下载执行的情况）
    if ($DEV_ENV_SCRIPT -and $DEV_ENV_SCRIPT.StartsWith($TEMP_DIR, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item $DEV_ENV_SCRIPT -Force -ErrorAction SilentlyContinue
        Write-Info "已删除: $DEV_ENV_SCRIPT"
    }

    Write-Info "清理完成"
}

# ===========================================
# 预检查
# ===========================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Windows 开发环境一键安装脚本" -ForegroundColor White
Write-Host "  Chrome + Java 21 + Git + Miniconda" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan

if ($DryRun) {
    Write-Info "=== 预检信息 ==="
    Write-Host "Java 下载地址: $env:JAVA_DOWNLOAD_URL"
    Write-Host "Java 安装路径: $JAVA_INSTALL_PATH"
    Write-Host "Miniconda 安装路径: $MINICONDA_INSTALL_PATH"
    Write-Host "镜像源: $Mirror"
    Write-Host "子脚本基础 URL: $BASE_URL"
    Write-Host ""
    foreach ($name in $SCRIPTS.Keys) {
        Write-Host "  $name : $($SCRIPTS[$name])"
    }
    exit 0
}

# 检查管理员权限，非管理员则自动提权
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Info "需要管理员权限，正在自动提权（请在 UAC 窗口点击「是」）..."

    # 构造传递给提权进程的参数
    $elevateArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-NoExit")
    foreach ($key in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$key]
        if ($value -is [switch]) {
            if ($value.IsPresent) { $elevateArgs += "-$key" }
        } else {
            $elevateArgs += "-$key"
            $elevateArgs += "`"$value`""
        }
    }

    # 确定脚本文件路径
    $scriptFile = $PSCommandPath
    if (-not ($scriptFile -and (Test-Path $scriptFile))) {
        $scriptFile = Join-Path $env:TEMP "install_dev_env.ps1"
        Write-Info "正在下载脚本到临时文件以进行提权..."
        Invoke-WebRequest -Uri $DEV_ENV_SCRIPT_URL -OutFile $scriptFile -UseBasicParsing
    }
    $elevateArgs += "-File", "`"$scriptFile`""

    try {
        Start-Process -Verb RunAs -FilePath "powershell.exe" -ArgumentList $elevateArgs -Wait
    } catch {
        Write-Err "提权失败或被取消: $_"
        Write-Host "请以管理员身份手动打开 PowerShell 后重新执行。" -ForegroundColor Yellow
        exit 1
    }
    exit
}

# 刷新 PATH
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

# ===========================================
# 步骤 1: 安装 Chrome
# ===========================================
Write-Step 1 "安装 Chrome"
Invoke-SubScript -ScriptName "install_chrome.ps1" -ScriptUrl $SCRIPTS.Chrome

# ===========================================
# 步骤 2: 安装 Java 21
# ===========================================
Write-Step 2 "安装 Java 21"
Invoke-SubScript -ScriptName "install_java.ps1" -ScriptUrl $SCRIPTS.Java -Arguments @{
    Path        = $JAVA_INSTALL_PATH
    DownloadUrl = $env:JAVA_DOWNLOAD_URL
}

# ===========================================
# 步骤 3: 安装 Git
# ===========================================
Write-Step 3 "安装 Git"
Invoke-SubScript -ScriptName "install_git.ps1" -ScriptUrl $SCRIPTS.Git

# ===========================================
# 步骤 4: 安装 Miniconda
# ===========================================
Write-Step 4 "安装 Miniconda"
Invoke-SubScript -ScriptName "install_miniconda.ps1" -ScriptUrl $SCRIPTS.Miniconda -Arguments @{
    Path = $MINICONDA_INSTALL_PATH
}

# ===========================================
# ===========================================
# 完成
# ===========================================
Write-Host ""
Write-Host "验证命令：" -ForegroundColor White
Write-Host "  java --version" -ForegroundColor Cyan
Write-Host "  conda --version" -ForegroundColor Cyan
Write-Host "  conda info" -ForegroundColor Cyan
Write-Host ""

# 清理临时文件
Remove-TempFiles

# 完成后提示
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  安装完成！" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "请重新打开终端/命令行以加载新的环境变量。" -ForegroundColor Yellow
Write-Host ""
Write-Host "环境变量配置：" -ForegroundColor White
Write-Host "  JAVA_HOME   = $JAVA_INSTALL_PATH" -ForegroundColor Gray
Write-Host "  Miniconda   = $MINICONDA_INSTALL_PATH" -ForegroundColor Gray
Write-Host ""
Write-Host "验证命令：" -ForegroundColor White
Write-Host "  java --version" -ForegroundColor Cyan
Write-Host "  conda --version" -ForegroundColor Cyan
Write-Host "  conda info" -ForegroundColor Cyan
