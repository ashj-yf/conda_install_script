#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$UserName,
    [string]$Password,
    [switch]$Random,
    [switch]$Interactive,
    [switch]$Help,
    [switch]$Version
)

$ErrorActionPreference = "Stop"

$SCRIPT_VERSION = "1.0.0"
$MIN_LENGTH = 6
$RECOMMEND_LENGTH = 8

# --- Logging ---
function Write-Info($msg)  { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Die($msg)         { Write-Err $msg; exit 1 }

# --- Help ---
if ($Help) {
    $name = Split-Path $PSCommandPath -Leaf
    Write-Host @"
Usage: $name [OPTIONS]

修改 Windows 本地账户密码。默认修改当前登录用户，支持交互输入或参数传参。

Options:
  -UserName <name>    目标本地账户名（默认：当前登录用户）
  -Random             随机密码模式（默认行为，参数仅为显式声明）
  -Password <pwd>     指定新密码
  -Interactive        交互式输入密码（隐藏回显，输入两次确认）
  -Help               显示帮助信息
  -Version            显示脚本版本

Examples:
  # 默认：一键随机改密（零交互，密码打印在输出中，请立即保存）
  .\$name

  # 指定账户并传参密码
  .\$name -UserName administrator -Password 'MyP@ss123'

  # 交互式输入（隐藏回显，不进命令历史）
  .\$name -Interactive

Notes:
  - 必须以管理员身份运行 PowerShell
  - -Password 传参可能残留在命令历史中，交互模式更安全
"@
    exit 0
}

if ($Version) {
    Write-Host "$SCRIPT_VERSION"
    exit 0
}

# --- Admin check ---
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Die "需要管理员权限，请以管理员身份运行 PowerShell 后重试"
}

# --- Resolve target user ---
$currentFullName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
if (-not $UserName) {
    $parts = $currentFullName -split '\\', 2
    if ($parts.Count -eq 2 -and $parts[0] -ne $env:COMPUTERNAME) {
        Die "当前用户 '$currentFullName' 不是本地账户（域/AzureAD 账户），请用 -UserName 指定要修改的本地账户"
    }
    $UserName = if ($parts.Count -eq 2) { $parts[1] } else { $currentFullName }
    Write-Info "未指定 -UserName，默认修改当前用户: $UserName"
}

if (-not (Get-Command Get-LocalUser -ErrorAction SilentlyContinue)) {
    Die "Get-LocalUser 不可用，请确认系统已安装 Windows PowerShell 5.1+"
}

$targetUser = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
if (-not $targetUser) {
    Write-Warn "本地账户 '$UserName' 不存在，现有本地账户："
    Get-LocalUser | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor White }
    Die "目标账户不存在: $UserName"
}

# --- Random password ---
function New-RandomPassword([int]$Length = 16) {
    # 去除易混淆字符（0O1lI），避开 shell/引号歧义字符；Get-Random 使用加密安全随机源
    $charset = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#%^*_-"
    $chars = $charset.ToCharArray()
    return -join (1..$Length | ForEach-Object { $chars[(Get-Random -Maximum $chars.Count)] })
}

# --- Obtain new password ---
function ConvertFrom-SecureToPlain([Security.SecureString]$sec) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try     { [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$isGenerated = $false
if ($Password) {
    Write-Warn "命令行参数传参的密码可能残留在 PowerShell 历史记录中，建议执行后清理历史"
} elseif ($Interactive) {
    if (-not [Environment]::UserInteractive) {
        Die "当前为非交互环境，无法交互输入，请通过 -Password 指定密码或使用默认随机模式"
    }
    while ($true) {
        $sec1 = Read-Host -Prompt "请输入新密码" -AsSecureString
        $sec2 = Read-Host -Prompt "请再次输入确认" -AsSecureString
        $plain1 = ConvertFrom-SecureToPlain $sec1
        $plain2 = ConvertFrom-SecureToPlain $sec2
        if ($plain1 -cne $plain2) {
            Write-Warn "两次输入不一致，请重新输入"
            continue
        }
        $Password = $plain1
        break
    }
} else {
    $Password = New-RandomPassword
    $isGenerated = $true
    Write-Info "已生成 16 位随机密码（零交互，直接设置），请立即复制保存："
    Write-Host ""
    Write-Host "  $Password" -ForegroundColor Cyan
    Write-Host ""
}

# --- Validate ---
if ($Password.Length -lt $MIN_LENGTH) {
    Die "密码长度不足：至少 $MIN_LENGTH 位，当前 $($Password.Length) 位"
}
if ($Password -match "[\r\n]") {
    Die "密码不能包含换行符"
}

$classes = 0
if ($Password -cmatch '[A-Z]')       { $classes++ }
if ($Password -cmatch '[a-z]')       { $classes++ }
if ($Password -match '\d')           { $classes++ }
if ($Password -match '[^A-Za-z0-9]') { $classes++ }
if (-not $isGenerated -and ($Password.Length -lt $RECOMMEND_LENGTH -or $classes -lt 3)) {
    Write-Warn "密码强度较弱（长度 $($Password.Length)，含 $classes 类字符），建议至少 $RECOMMEND_LENGTH 位且包含大小写/数字/特殊字符中的三类（若系统密码策略更严格，以系统校验结果为准）"
}

# --- Apply ---
$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force

try {
    if (Get-Command Set-LocalUser -ErrorAction SilentlyContinue) {
        Set-LocalUser -Name $UserName -Password $securePassword
    } else {
        Write-Warn "Set-LocalUser 不可用，回退到 net user（密码将短暂出现在子进程参数中）"
        $output = net user $UserName "$Password" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "net user 修改失败: $output" }
    }
} catch {
    Die "修改密码失败: $($_.Exception.Message)"
}

# --- Done ---
Write-Host ""
Write-Info "密码修改完成"
Write-Host "  目标账户: $UserName" -ForegroundColor White

# --- Record password to file ---
# 在当前工作目录生成 password_主机_账户_时间戳.txt
try {
    $recordFile = Join-Path (Get-Location).Path ("password_{0}_{1}_{2}.txt" -f $env:COMPUTERNAME, $UserName, (Get-Date -Format "yyyyMMdd-HHmmss"))
    $recordContent = "主机: $env:COMPUTERNAME`r`n账户: $UserName`r`n新密码: $Password`r`n时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Set-Content -Path $recordFile -Value $recordContent -Encoding UTF8
    Write-Info "密码已记录到: $recordFile（请妥善保管，勿提交到代码仓库）"
} catch {
    Write-Warn "密码记录文件写入失败: $($_.Exception.Message)（密码仅在上方输出中）"
}

Write-Info "请妥善保管新密码，并同步更新使用该账户的凭据（计划任务、服务、远程桌面保存的凭据等）"
