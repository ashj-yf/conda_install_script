#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly TARGET_USER="root"
readonly MIN_LENGTH=6
readonly RECOMMEND_LENGTH=8

NEW_PASSWORD=""

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Logging ---
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$@"; exit 1; }

# --- Help ---
show_help() {
    local name
    name="$(basename "$0")"
    cat <<EOF
Usage: $name [OPTIONS]

修改 Linux root 账户密码。支持交互输入或参数传参，需 root 权限执行。

Options:
  -p, --password <pwd>   新密码（省略则交互式输入两次确认）
      --password=<pwd>   等价的 = 形式传参
  -h, --help             显示帮助信息
  -V, --version          显示脚本版本

Examples:
  # 交互式修改 root 密码
  sudo bash $name

  # 参数传密码（可能残留 shell 历史，谨慎使用）
  sudo bash $name --password 'MyP@ss123'

Notes:
  - 密码通过 chpasswd 从 stdin 写入，不会出现在进程参数列表中
  - chpasswd 不走 PAM 复杂度策略校验，脚本内置基础长度校验
  - 密码不能包含换行符
EOF
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--password)
            [[ -n "${2:-}" ]] || die "--password 需要一个密码参数"
            NEW_PASSWORD="$2"
            shift 2
            ;;
        --password=*)
            NEW_PASSWORD="${1#*=}"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -V|--version)
            echo "$SCRIPT_VERSION"
            exit 0
            ;;
        *)
            die "未知参数: $1（使用 --help 查看帮助）"
            ;;
    esac
done

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
    if [[ -n "$NEW_PASSWORD" ]]; then
        die "需要 root 权限。请切换到 root 会话（su -）后执行，避免通过 sudo 命令行传递密码"
    fi
    die "需要 root 权限执行，请使用: sudo bash $0"
fi

# --- Obtain new password ---
if [[ -z "$NEW_PASSWORD" ]]; then
    if [[ ! -t 0 ]]; then
        die "检测到非交互终端，请通过 --password 传入密码"
    fi
    while true; do
        read -rs -p "请输入新密码: " pass1 || die "密码输入被中断"
        echo
        read -rs -p "请再次输入确认: " pass2 || die "密码输入被中断"
        echo
        if [[ -z "$pass1" ]]; then
            warn "密码不能为空，请重新输入"
            continue
        fi
        if [[ "$pass1" != "$pass2" ]]; then
            warn "两次输入不一致，请重新输入"
            continue
        fi
        NEW_PASSWORD="$pass1"
        break
    done
    unset pass1 pass2
else
    warn "--password 传参可能残留在 shell 历史与进程列表中，建议执行后清理（history -c）"
fi

# --- Validate ---
if [[ -z "$NEW_PASSWORD" ]]; then
    die "密码不能为空"
fi
if [[ ${#NEW_PASSWORD} -lt $MIN_LENGTH ]]; then
    die "密码长度不足：至少 $MIN_LENGTH 位，当前 ${#NEW_PASSWORD} 位"
fi
if [[ "$NEW_PASSWORD" == *$'\n'* || "$NEW_PASSWORD" == *$'\r'* ]]; then
    die "密码不能包含换行符"
fi

classes=0
if [[ "$NEW_PASSWORD" =~ [[:upper:]] ]];  then classes=$((classes + 1)); fi
if [[ "$NEW_PASSWORD" =~ [[:lower:]] ]];  then classes=$((classes + 1)); fi
if [[ "$NEW_PASSWORD" =~ [[:digit:]] ]];  then classes=$((classes + 1)); fi
if [[ "$NEW_PASSWORD" =~ [^[:alnum:]] ]]; then classes=$((classes + 1)); fi
if [[ ${#NEW_PASSWORD} -lt $RECOMMEND_LENGTH || $classes -lt 3 ]]; then
    warn "密码强度较弱（长度 ${#NEW_PASSWORD}，含 ${classes} 类字符），建议至少 ${RECOMMEND_LENGTH} 位且包含大小写/数字/特殊字符中的三类"
fi

# --- Apply ---
if ! command -v chpasswd >/dev/null 2>&1; then
    die "未找到 chpasswd 命令，请确认已安装 passwd/shadow-utils 软件包"
fi

if printf '%s:%s\n' "$TARGET_USER" "$NEW_PASSWORD" | chpasswd; then
    info "已通过 chpasswd 修改 ${TARGET_USER} 密码"
else
    die "chpasswd 执行失败，请检查系统日志（/var/log/auth.log 或 /var/log/secure）"
fi

# --- Verify ---
# 直接读取 /etc/shadow 密码字段校验（root 下必然可读，不依赖 passwd -S 的系统支持）
shadow_hash="$(awk -F: -v u="$TARGET_USER" '$1 == u {print $2}' /etc/shadow 2>/dev/null || true)"
if [[ -n "$shadow_hash" && "$shadow_hash" != '!'* && "$shadow_hash" != '*'* ]]; then
    info "验证通过：${TARGET_USER} 密码哈希已写入 /etc/shadow"
else
    warn "无法从 /etc/shadow 确认密码状态，建议手动验证登录"
fi

unset NEW_PASSWORD
info "完成。请妥善保管新密码；SSH 密钥登录不受影响，密码登录请重新测试"
