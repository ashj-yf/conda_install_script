#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly TARGET_USER="root"
readonly MIN_LENGTH=6
readonly RECOMMEND_LENGTH=8

NEW_PASSWORD=""
RANDOM_MODE=0
INTERACTIVE_MODE=0

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
  -r, --random            随机密码模式（默认行为，参数仅为显式声明）：自动生成
                          16 位随机密码并直接设置，密码打印在输出中
  -p, --password <pwd>    指定新密码
      --password=<pwd>    等价的 = 形式传参
  -i, --interactive       交互式输入密码（隐藏回显，输入两次确认）
  -h, --help              显示帮助信息
  -V, --version           显示脚本版本

Examples:
  # 默认：一键随机改密（零交互，密码打印在输出中，请立即保存）
  sudo bash $name

  # 参数传密码（可能残留 shell 历史，谨慎使用）
  sudo bash $name --password 'MyP@ss123'

  # 交互式输入（隐藏回显，不进 shell 历史）
  sudo bash $name --interactive

Notes:
  - 密码通过 chpasswd 从 stdin 写入，不会出现在进程参数列表中
  - chpasswd 不走 PAM 复杂度策略校验，脚本内置基础长度校验
  - 密码不能包含换行符
EOF
}

# --- Random password generator ---
gen_random_password() {
    local length="${1:-16}" out
    # 去除易混淆字符（0O1lI），避开 shell/引号歧义字符；'-' 置于字符集末尾避免被解析为范围
    # head 先取定长样本再交给 tr（管道顺序保证 tr 正常读到 EOF，不会触发 SIGPIPE）
    # LC_ALL=C 强制按字节处理（BSD/GNU tr 在多字节 locale 下会对随机字节流报 Illegal byte sequence）
    out="$(head -c 1024 /dev/urandom | LC_ALL=C tr -dc 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#%^*_-')" || true
    if [[ ${#out} -lt $length ]]; then
        die "随机密码生成失败（随机源输出不足），请重试"
    fi
    printf '%s' "${out:0:$length}"
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--password)
            [[ -n "${2:-}" ]] || die "--password 需要一个密码参数"
            NEW_PASSWORD="$2"
            shift 2
            ;;
        -r|--random)
            RANDOM_MODE=1
            shift
            ;;
        -i|--interactive)
            INTERACTIVE_MODE=1
            shift
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
# 优先级：--password > --interactive > 默认随机
IS_GENERATED=0
if [[ -n "$NEW_PASSWORD" ]]; then
    warn "--password 传参可能残留在 shell 历史与进程列表中，建议执行后清理（history -c）"
elif [[ $INTERACTIVE_MODE -eq 1 ]]; then
    if [[ ! -t 0 ]]; then
        die "检测到非交互终端，无法交互输入，请改用 --password 或使用默认随机模式"
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
    NEW_PASSWORD="$(gen_random_password 16)"
    IS_GENERATED=1
    info "已生成 16 位随机密码（零交互，直接设置），请立即复制保存："
    echo ""
    echo -e "  ${BOLD}${CYAN}${NEW_PASSWORD}${NC}"
    echo ""
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
if [[ $IS_GENERATED -ne 1 && ( ${#NEW_PASSWORD} -lt $RECOMMEND_LENGTH || $classes -lt 3 ) ]]; then
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

# --- Record password to file ---
# 在当前工作目录生成 password_主机_账户_时间戳.txt（umask 077 保证权限 600）
record_file="$(pwd)/password_$(hostname)_${TARGET_USER}_$(date +%Y%m%d-%H%M%S).txt"
if ( umask 077 && printf '主机: %s\n账户: %s\n新密码: %s\n时间: %s\n' \
        "$(hostname)" "$TARGET_USER" "$NEW_PASSWORD" "$(date '+%Y-%m-%d %H:%M:%S')" > "$record_file" ); then
    info "密码已记录到: $record_file（权限 600，请妥善保管，勿提交到代码仓库）"
else
    warn "密码记录文件写入失败（当前目录不可写？），密码仅在上方输出中"
fi

unset NEW_PASSWORD
info "完成。请妥善保管新密码；SSH 密钥登录不受影响，密码登录请重新测试"
