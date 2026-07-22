#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet("github", "gitee")]
    [string]$Mirror = "gitee",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# ==================== 配置 ====================
# Java 下载地址（可在此处修改，或通过环境变量覆盖）
$env:JAVA_DOWNLOAD_URL = "https://mirrors.huaweicloud.com/openjdk/21.0.2/openjdk-21.0.2_windows-x64_bin.zip"

# Git 下载地址（华为镜像）
$GIT_DOWNLOAD_URL = "https://mirrors.huaweicloud.com/git-for-windows/v2.47.1.windows.1/Git-2.47.1-64-bit.exe"

# 安装路径
$JAVA_INSTALL_PATH = "C:\ProgramData\Java\jdk-21"
$MINICONDA_INSTALL_PATH = $env:CONDA_INSTALL_PATH, "C:\ProgramData\miniconda3" | Select-Object -First 1
$GIT_INSTALL_PATH = "C:\ProgramData\Git"

# Miniconda 远程脚本地址
$GITHUB_MINICONDA_URL = "https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/install_miniconda.ps1"
$GITEE_MINICONDA_URL = "https://gitee.com/ashj-yf/conda_install_script/raw/master/install_miniconda.ps1"
$MINICONDA_SCRIPT_URL = if ($Mirror -eq "github") { $GITHUB_MINICONDA_URL } else { $GITEE_MINICONDA_URL }

# 本脚本自身的远程地址（用于 iex 管道方式自动提权时重新下载到临时文件）
$GITHUB_DEV_ENV_URL = "https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/install_dev_env.ps1"
$GITEE_DEV_ENV_URL = "https://gitee.com/ashj-yf/conda_install_script/raw/master/install_dev_env.ps1"
$DEV_ENV_SCRIPT_URL = if ($Mirror -eq "github") { $GITHUB_DEV_ENV_URL } else { $GITEE_DEV_ENV_URL }

# 临时目录
$TEMP_DIR = $env:TEMP
$JAVA_ZIP = Join-Path $TEMP_DIR "openjdk-21.0.2_windows-x64_bin.zip"
$MINICONDA_SCRIPT = Join-Path $TEMP_DIR "install_miniconda.ps1"
$DEV_ENV_SCRIPT = $MyInvocation.MyCommand.Path
$CHROME_SETUP = Join-Path $TEMP_DIR "ChromeSetup.exe"
$GIT_SETUP = Join-Path $TEMP_DIR "GitSetup.exe"

$TOTAL_STEPS = 6
# ==================== 配置结束 ====================

# --- 日志函数 ---
function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Die($msg) { Write-Err $msg; exit 1 }
function Write-Step($n, $msg) { Write-Host ""; Write-Host "[$n/$TOTAL_STEPS] " -ForegroundColor Cyan -NoNewline; Write-Host $msg -ForegroundColor White -NoNewline; Write-Host " ..." }

# --- 清理函数 ---
function Remove-TempFiles {
    Write-Host "" -NoNewline
    Write-Info "正在清理临时文件..."

    # 清理 Chrome 安装包
    if (Test-Path $CHROME_SETUP) {
        Remove-Item $CHROME_SETUP -Force -ErrorAction SilentlyContinue
        Write-Info "已删除: $CHROME_SETUP"
    }

    # 清理 Git 安装包
    if (Test-Path $GIT_SETUP) {
        Remove-Item $GIT_SETUP -Force -ErrorAction SilentlyContinue
        Write-Info "已删除: $GIT_SETUP"
    }

    # 清理 Java ZIP
    if (Test-Path $JAVA_ZIP) {
        Remove-Item $JAVA_ZIP -Force -ErrorAction SilentlyContinue
        Write-Info "已删除: $JAVA_ZIP"
    }

    # 清理 Miniconda 安装脚本
    if (Test-Path $MINICONDA_SCRIPT) {
        Remove-Item $MINICONDA_SCRIPT -Force -ErrorAction SilentlyContinue
        Write-Info "已删除: $MINICONDA_SCRIPT"
    }

    # 清理自身（仅当脚本位于临时目录时，即远程下载执行的情况）
    if ($DEV_ENV_SCRIPT -and $DEV_ENV_SCRIPT.StartsWith($TEMP_DIR, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item $DEV_ENV_SCRIPT -Force -ErrorAction SilentlyContinue
        Write-Info "已删除: $DEV_ENV_SCRIPT"
    }

    Write-Info "清理完成"
}

# --- 环境变量操作 ---
function Add-ToSystemPath {
    param([string]$Path)
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    # 两端补分号，确保能匹配到处于开头/结尾的条目，避免重复追加
    if (";$currentPath;" -notlike "*;$Path;*") {
        $newPath = if ($currentPath) { "$currentPath;$Path" } else { $Path }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
        # 刷新当前会话 PATH，使后续命令能立即用到新路径
        $env:Path = "$newPath;" + [Environment]::GetEnvironmentVariable("Path", "User")
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

# 检查管理员权限，非管理员则自动提权（设置系统级环境变量需要写入 HKLM 注册表）
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Info "需要管理员权限，正在自动提权（请在 UAC 窗口点击「是」）..."

    # 构造传递给提权进程的参数，保留用户传入的参数
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

    # 确定脚本文件路径：从文件运行则直接用；iex 管道方式则重新下载到临时文件
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

# 刷新 PATH 以获取最新环境变量
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

# ===========================================
# 步骤 1: 安装 Chrome
# ===========================================
Write-Step 1 "安装 Chrome"
try {
    $chromePath = $null
    # 检查注册表 App Paths（HKLM 系统级 + HKCU 用户级）
    foreach ($hive in @("HKLM:", "HKCU:")) {
        $chrome = Get-ItemProperty "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction SilentlyContinue
        if ($chrome -and $chrome.'(default)' -and (Test-Path $chrome.'(default)')) {
            $chromePath = $chrome.'(default)'
            break
        }
    }
    # 检查 PATH
    if (-not $chromePath) {
        $cmd = Get-Command chrome -ErrorAction SilentlyContinue
        if ($cmd) { $chromePath = $cmd.Source }
    }
    # 检查常见安装路径（含用户级安装）
    if (-not $chromePath) {
        foreach ($p in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) {
            if ($p -and (Test-Path $p)) { $chromePath = $p; break }
        }
    }
    if ($chromePath) {
        Write-Info "Chrome 已安装: $chromePath"
    } else {
        Write-Info "正在下载 Chrome 安装程序..."
        Invoke-WebRequest -Uri "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile $CHROME_SETUP -UseBasicParsing
        Write-Info "正在安装 Chrome（静默模式）..."
        Start-Process $CHROME_SETUP -ArgumentList "/silent /install" -Wait
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

# 步骤 5: 安装 Git
# ===========================================
Write-Step 5 "安装 Git"
try {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    # Get-Command 检测不到时，检查常见安装路径
    if (-not $gitCmd) {
        foreach ($p in @("$env:ProgramFiles\Git\cmd\git.exe", "${env:ProgramFiles(x86)}\Git\cmd\git.exe")) {
            if ($p -and (Test-Path $p)) { $gitCmd = $p; break }
        }
    }
    if ($gitCmd) {
        $gitVersion = & $gitCmd --version 2>&1
        Write-Info "Git 已安装: $gitVersion"
    } else {
        Write-Info "正在下载 Git 安装程序..."
        Invoke-WebRequest -Uri $GIT_DOWNLOAD_URL -OutFile $GIT_SETUP -UseBasicParsing
        Write-Info "正在安装 Git（静默模式）..."
        Start-Process $GIT_SETUP -ArgumentList "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS", "/COMPONENTS=`"icons,extreg`"" -Wait
        Write-Info "Git 安装完成"
    }
} catch {
    Write-Warn "Git 安装失败: $_"
    Write-Info "请手动下载安装: https://git-scm.com/download/win"
}

# ===========================================
# 步骤 6: 安装 Miniconda
# ===========================================
Write-Step 6 "安装 Miniconda"

$condaExe = Join-Path $MINICONDA_INSTALL_PATH "Scripts\conda.exe"
if (Get-Command conda -ErrorAction SilentlyContinue) {
    Write-Info "Miniconda/Conda 已安装，跳过"
} elseif (Test-Path $condaExe) {
    Write-Info "Miniconda 已安装于 $MINICONDA_INSTALL_PATH（PATH 缺失），跳过安装"
} else {
    Write-Info "正在下载安装脚本..."
    try {
        Invoke-WebRequest -Uri $MINICONDA_SCRIPT_URL -OutFile $MINICONDA_SCRIPT -UseBasicParsing
        Write-Info "正在安装 Miniconda（静默模式）..."
        # 执行安装脚本（子进程 + Bypass 绕过执行策略；子进程 exit 不影响本进程）
        & powershell.exe -ExecutionPolicy Bypass -NoProfile -File $MINICONDA_SCRIPT -Path $MINICONDA_INSTALL_PATH
        if ($LASTEXITCODE -ne 0) { throw "Miniconda 安装脚本退出码: $LASTEXITCODE" }
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
