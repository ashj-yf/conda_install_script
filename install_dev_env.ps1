#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet("github", "gitee")]
    [string]$Mirror = "github"
)

$ErrorActionPreference = "Stop"

# ==================== 配置 ====================
# Java 下载地址（可在此处修改，或通过环境变量覆盖）
$env:JAVA_DOWNLOAD_URL = "https://mirrors.huaweicloud.com/openjdk/21.0.2/openjdk-21.0.2_windows-x64_bin.zip"

# 安装路径
$JAVA_INSTALL_PATH = "C:\ProgramData\Java\jdk-21"
$MINICONDA_INSTALL_PATH = $env:CONDA_INSTALL_PATH, "C:\ProgramData\miniconda3" | Select-Object -First 1

# Miniconda 远程脚本地址（根据镜像源选择）
$GITHUB_MINICONDA_URL = "https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/install_miniconda.ps1"
$GITEE_MINICONDA_URL = "https://gitee.com/ashj-yf/conda_install_script/raw/master/install_miniconda.ps1"
$MINICONDA_SCRIPT_URL = if ($Mirror -eq "gitee") { $GITEE_MINICONDA_URL } else { $GITHUB_MINICONDA_URL }

# 临时目录
$TEMP_DIR = $env:TEMP
$JAVA_ZIP = Join-Path $TEMP_DIR "openjdk-21.0.2_windows-x64_bin.zip"
$MINICONDA_SCRIPT = Join-Path $TEMP_DIR "install_miniconda.ps1"

$TOTAL_STEPS = 5
# ==================== 配置结束 ====================

# --- 日志函数 ---
function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Die($msg) { Write-Err $msg; exit 1 }
function Write-Step($n, $msg) { Write-Host ""; Write-Host "[$n/$TOTAL_STEPS] " -ForegroundColor Cyan -NoNewline; Write-Host $msg -ForegroundColor White -NoNewline; Write-Host " ..." }

# --- 环境变量操作 ---
function Add-ToSystemPath {
    param([string]$Path)
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($currentPath -notlike "*;$Path;*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$Path", "Machine")
        $script:needsPathRefresh = $true
        Write-Info "已添加到系统 PATH: $Path"
    } else {
        Write-Info "系统 PATH 已包含: $Path"
    }
}

# --- 步骤 0: 预检查 ---
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Windows 开发环境一键安装脚本" -ForegroundColor White
Write-Host "  Chrome + Java 21 + Miniconda" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan

if ($DryRun) {
    Write-Info "=== 预检信息 ==="
    Write-Host "Java 下载地址: $env:JAVA_DOWNLOAD_URL"
    Write-Host "Java 安装路径: $JAVA_INSTALL_PATH"
    Write-Host "Miniconda 安装路径: $MINICONDA_INSTALL_PATH"
    Write-Host "Miniconda 脚本: $MINICONDA_SCRIPT_URL"
    Write-Host "Java ZIP: $JAVA_ZIP"
    exit 0
}

# 刷新 PATH 以获取最新环境变量
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

# ===========================================
# 步骤 1: 安装 Chrome
# ===========================================
Write-Step 1 "安装 Chrome"
try {
    $chrome = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction SilentlyContinue
    if ($chrome -and (Test-Path $chrome."(default)")) {
        Write-Info "Chrome 已安装: $($chrome.'(default)')"
    } elseif (Get-Command chrome -ErrorAction SilentlyContinue) {
        Write-Info "Chrome 已安装（命令行可用）"
    } else {
        Write-Info "正在下载 Chrome 安装程序..."
        $chromeSetup = Join-Path $TEMP_DIR "ChromeSetup.exe"
        Invoke-WebRequest -Uri "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile $chromeSetup -UseBasicParsing
        Write-Info "正在安装 Chrome（静默模式）..."
        Start-Process $chromeSetup -ArgumentList "/silent /install" -Wait
        Remove-Item $chromeSetup -Force -ErrorAction SilentlyContinue
        Write-Info "Chrome 安装完成"
    }
} catch {
    Write-Warn "Chrome 安装失败: $_"
    Write-Info "请手动下载安装: https://www.google.com/chrome/"
}

# ===========================================
# 步骤 2: 下载 Java
# ===========================================
Write-Step 2 "下载 Java 21 (OpenJDK)"

if (Test-Path $JAVA_INSTALL_PATH) {
    Write-Info "Java 已存在: $JAVA_INSTALL_PATH，跳过下载"
} else {
    if (Test-Path $JAVA_ZIP) { Remove-Item $JAVA_ZIP -Force }
    Write-Info "下载地址: $env:JAVA_DOWNLOAD_URL"
    Write-Info "正在下载（可能需要几分钟）..."
    try {
        Invoke-WebRequest -Uri $env:JAVA_DOWNLOAD_URL -OutFile $JAVA_ZIP -UseBasicParsing
        Write-Info "下载完成"
    } catch {
        Die "Java 下载失败: $_"
    }
}

# ===========================================
# 步骤 3: 解压并安装 Java
# ===========================================
Write-Step 3 "解压并安装 Java"

if (Test-Path $JAVA_INSTALL_PATH) {
    Write-Info "Java 已解压至: $JAVA_INSTALL_PATH"
} else {
    Write-Info "正在解压到 $JAVA_INSTALL_PATH ..."
    try {
        # 创建目标目录
        $javaParent = Split-Path $JAVA_INSTALL_PATH -Parent
        if (-not (Test-Path $javaParent)) {
            New-Item -ItemType Directory -Path $javaParent -Force | Out-Null
        }

        # 解压 ZIP
        Expand-Archive -Path $JAVA_ZIP -DestinationPath (Split-Path $JAVA_INSTALL_PATH -Parent) -Force
        # 重命名为指定路径
        $extractedFolder = Join-Path (Split-Path $JAVA_INSTALL_PATH -Parent) "jdk-21.0.2"
        if ($extractedFolder -ne $JAVA_INSTALL_PATH -and (Test-Path $extractedFolder)) {
            Move-Item -Path $extractedFolder -Destination $JAVA_INSTALL_PATH -Force
        }
        Write-Info "解压完成"
    } catch {
        Die "Java 解压失败: $_"
    } finally {
        # 清理 ZIP
        if (Test-Path $JAVA_ZIP) { Remove-Item $JAVA_ZIP -Force -ErrorAction SilentlyContinue }
    }
}

# ===========================================
# 步骤 4: 配置 Java 环境变量
# ===========================================
Write-Step 4 "配置 Java 环境变量"

# 设置 JAVA_HOME
$currentJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
if ($currentJavaHome -ne $JAVA_INSTALL_PATH) {
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $JAVA_INSTALL_PATH, "Machine")
    $env:JAVA_HOME = $JAVA_INSTALL_PATH
    Write-Info "已设置 JAVA_HOME: $JAVA_INSTALL_PATH"
} else {
    Write-Info "JAVA_HOME 已正确配置"
}

# 添加到 PATH
$javaBin = Join-Path $JAVA_INSTALL_PATH "bin"
Add-ToSystemPath $javaBin

# 验证
Write-Info "验证 Java 安装..."
try {
    $javaVersion = & java --version 2>&1
    Write-Info "Java 版本: $javaVersion"
} catch {
    Write-Warn "Java 验证失败，请重新打开终端"
}

# ===========================================
# 步骤 5: 安装 Miniconda
# ===========================================
Write-Step 5 "安装 Miniconda"

if (Get-Command conda -ErrorAction SilentlyContinue) {
    Write-Info "Miniconda/Conda 已安装，跳过"
} else {
    Write-Info "正在下载安装脚本..."
    try {
        Invoke-WebRequest -Uri $MINICONDA_SCRIPT_URL -OutFile $MINICONDA_SCRIPT -UseBasicParsing
        Write-Info "正在安装 Miniconda（静默模式）..."
        # 执行安装脚本
        & $MINICONDA_SCRIPT -Path $MINICONDA_INSTALL_PATH
    } catch {
        Write-Warn "Miniconda 安装失败: $_"
        Write-Info "请手动运行: irm $MINICONDA_SCRIPT_URL | iex"
    } finally {
        if (Test-Path $MINICONDA_SCRIPT) { Remove-Item $MINICONDA_SCRIPT -Force -ErrorAction SilentlyContinue }
    }
}

# 添加 Miniconda 到 PATH
$minicondaScripts = Join-Path $MINICONDA_INSTALL_PATH "Scripts"
if (Test-Path $minicondaScripts) {
    Add-ToSystemPath $minicondaScripts
}

# ===========================================
# 完成
# ===========================================
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
Write-Host ""
