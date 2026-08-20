#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_VERSION="1.1.0"

# --- Mirror configurations ---
# tuna: 清华 TUNA (默认)
# pku:  北大 PKU
readonly MIRROR_CONFIG='{
    "tuna": {
        "name": "TUNA",
        "display_name": "清华 TUNA",
        "base_url": "https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda",
        "cloud_url": "https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud"
    },
    "pku": {
        "name": "PKU",
        "display_name": "北大 PKU",
        "base_url": "https://mirrors.pku.edu.cn/anaconda/miniconda",
        "cloud_url": "https://mirrors.pku.edu.cn/anaconda/cloud"
    }
}'
readonly DEFAULT_MIRROR="tuna"
readonly OFFICIAL_BASE_URL="https://repo.anaconda.com/miniconda"
readonly DEFAULT_INSTALL_PATH="/opt/miniconda3"
readonly LOCAL_INSTALLER="/tmp/Miniconda3-latest-installer.sh"
readonly TOTAL_STEPS=5

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
step()  { local n="$1" t="$2"; shift 2; echo -e "${BOLD}${CYAN}[${n}/${t}]${NC} ${BOLD}$*${NC}"; }

# --- Get mirror config by key ---
get_mirror_config() {
    local key="$1"
    echo "$MIRROR_CONFIG" | grep -o "\"${key}\": {[^}]*}" | sed 's/"${key}": //' || echo ""
}

get_mirror_value() {
    local key="$1" field="$2"
    echo "$MIRROR_CONFIG" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['$key']['$field'])" 2>/dev/null || \
    echo "$MIRROR_CONFIG" | grep -o "\"${key}\".*\"${field}\": \"[^\"]*\"" | sed "s/.*\"${field}\": \"//;s/\"//"
}

# --- Mirror selection ---
select_mirror() {
    if [[ -n "${SELECTED_MIRROR:-}" ]]; then
        info "Using mirror from --mirror argument: $(get_mirror_value "$SELECTED_MIRROR" display_name)"
        echo "$SELECTED_MIRROR"
        return
    fi

    echo ""
    echo -e "${YELLOW}请选择 conda 镜像源：${NC}"
    echo -e "  ${BOLD}[1]${NC} 清华 TUNA (mirrors.tuna.tsinghua.edu.cn) - 默认"
    echo -e "  ${BOLD}[2]${NC} 北大 PKU (mirrors.pku.edu.cn)"
    echo ""

    while true; do
        read -p "请输入选择 [1]: " choice
        : "${choice:=1}"
        case "$choice" in
            1) echo "tuna"; return ;;
            2) echo "pku"; return ;;
            *) warn "无效选择，请输入 1 或 2" ;;
        esac
    done
}

# --- Arguments ---
FORCE=false
DRY_RUN=false
DO_CLEAN=false
INSTALL_PATH=""
SELECTED_MIRROR=""

usage() {
cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install Miniconda (latest) from Chinese mirror.

Options:
  --force       Skip checks for existing conda and install path
  --path PATH   Custom installation path (default: /opt/miniconda3)
  --mirror SRC  Choose mirror source: tuna (清华, default) or pku (北大)
  --dry-run     Print detection info and download URL without executing
  --clean       Remove downloaded installer file and exit
  --help        Show this help message
  --version     Print script version

Available mirrors:
  tuna  - 清华 TUNA (mirrors.tuna.tsinghua.edu.cn) [默认]
  pku   - 北大 PKU (mirrors.pku.edu.cn)

Examples:
  $(basename "$0")                      # Interactive selection
  $(basename "$0") --mirror tuna         # Use TUNA mirror (default)
  $(basename "$0") --mirror pku          # Use PKU mirror
  $(basename "$0") --force --mirror pku  # Force install with PKU mirror

Environment variables:
  CONDA_INSTALL_PATH  Override default install path (same as --path)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)   FORCE=true; shift ;;
        --path)    INSTALL_PATH="$2"; shift 2 ;;
        --mirror)
            case "$2" in
                tuna|pku) SELECTED_MIRROR="$2"; shift 2 ;;
                *) die "Unknown mirror '$2'. Use --help for available mirrors." ;;
            esac
            ;;
        --dry-run) DRY_RUN=true; shift ;;
        --clean)   DO_CLEAN=true; shift ;;
        --help)    usage; exit 0 ;;
        --version) echo "${SCRIPT_VERSION}"; exit 0 ;;
        *)         die "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# Resolve install path: CLI arg > env var > default
INSTALL_PATH="${INSTALL_PATH:-${CONDA_INSTALL_PATH:-$DEFAULT_INSTALL_PATH}}"

# --- Select mirror ---
MIRROR_KEY="$(select_mirror)"
MIRROR_BASE_URL="$(get_mirror_value "$MIRROR_KEY" base_url)"
MIRROR_CLOUD_URL="$(get_mirror_value "$MIRROR_KEY" cloud_url)"
MIRROR_DISPLAY_NAME="$(get_mirror_value "$MIRROR_KEY" display_name)"

# --- Clean mode ---
if [[ "${DO_CLEAN}" == true ]]; then
    if [[ -f "${LOCAL_INSTALLER}" ]]; then
        rm -f "${LOCAL_INSTALLER}"
        info "Removed installer: ${LOCAL_INSTALLER}"
    else
        info "No installer file found at ${LOCAL_INSTALLER}"
    fi
    exit 0
fi

# --- Cleanup trap ---
cleanup() {
    if [[ -f "${LOCAL_INSTALLER}" ]]; then
        rm -f "${LOCAL_INSTALLER}"
        info "Cleaned up partial download: ${LOCAL_INSTALLER}"
    fi
}
trap cleanup EXIT

# ============================================================
# Step 1: Detect environment
# ============================================================
step 1 "${TOTAL_STEPS}" "Detecting environment..."

OS_NAME="$(uname -s)"
case "${OS_NAME}" in
    Linux*)  CONDA_OS="Linux" ;;
    Darwin*) CONDA_OS="MacOSX" ;;
    *)       die "Unsupported OS: ${OS_NAME}. Only Linux and macOS are supported." ;;
esac

ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64)       CONDA_ARCH="x86_64" ;;
    aarch64)      CONDA_ARCH="aarch64" ;;
    arm64)        CONDA_ARCH="arm64" ;;
    armv7l)       CONDA_ARCH="armv7l" ;;
    ppc64le)      CONDA_ARCH="ppc64le" ;;
    s390x)        CONDA_ARCH="s390x" ;;
    i386|i686)    CONDA_ARCH="x86" ;;
    *)            die "Unsupported architecture: ${ARCH}" ;;
esac

INSTALLER_FILENAME="Miniconda3-latest-${CONDA_OS}-${CONDA_ARCH}.sh"
case "${CONDA_ARCH}" in
    ppc64le|s390x)
        DOWNLOAD_URL="${OFFICIAL_BASE_URL}/${INSTALLER_FILENAME}"
        warn "${MIRROR_DISPLAY_NAME} mirror does not carry ${CONDA_ARCH} installers; falling back to repo.anaconda.com."
        ;;
    *)
        DOWNLOAD_URL="${MIRROR_BASE_URL}/${INSTALLER_FILENAME}"
        ;;
esac

info "OS: ${CONDA_OS}  |  Arch: ${CONDA_ARCH}  |  Installer: ${INSTALLER_FILENAME}"
info "Mirror: ${MIRROR_DISPLAY_NAME}"

# ============================================================
# Step 2: Pre-flight checks
# ============================================================
step 2 "${TOTAL_STEPS}" "Running pre-flight checks..."

# Check existing conda
if command -v conda &>/dev/null; then
    EXISTING_CONDA="$(command -v conda)"
    EXISTING_VER="$(conda --version 2>/dev/null || echo 'unknown')"
    if [[ "${FORCE}" == true ]]; then
        warn "Existing conda found (${EXISTING_VER} at ${EXISTING_CONDA}), but --force is set. Continuing."
    else
        die "Conda is already installed (${EXISTING_VER} at ${EXISTING_CONDA}). Use --force to override."
    fi
fi

# Check download tool
if command -v curl &>/dev/null; then
    DOWNLOAD_TOOL="curl"
elif command -v wget &>/dev/null; then
    DOWNLOAD_TOOL="wget"
else
    die "Neither curl nor wget found. Please install one and retry."
fi
info "Download tool: ${DOWNLOAD_TOOL}"

# Check install path
if [[ -d "${INSTALL_PATH}" ]] && [[ -n "$(ls -A "${INSTALL_PATH}" 2>/dev/null)" ]]; then
    if [[ "${FORCE}" == true ]]; then
        warn "Install path ${INSTALL_PATH} exists and is non-empty, but --force is set. Continuing."
    else
        die "Install path ${INSTALL_PATH} already exists and is non-empty. Use --force to override."
    fi
fi

# Check parent directory writable
PARENT_DIR="$(dirname "${INSTALL_PATH}")"
if [[ ! -w "${PARENT_DIR}" ]]; then
    die "Parent directory ${PARENT_DIR} is not writable. Choose a different path with --path."
fi

# Disk space check (soft)
AVAILABLE_KB="$(df "${PARENT_DIR}" 2>/dev/null | awk 'NR==2{print $4}')"
if [[ -n "${AVAILABLE_KB}" ]] && [[ "${AVAILABLE_KB}" -lt 3145728 ]]; then
    warn "Less than 3 GB free disk space in ${PARENT_DIR}. Installation may fail."
fi

# ============================================================
# Step 3: Download installer
# ============================================================
step 3 "${TOTAL_STEPS}" "Downloading Miniconda installer..."

if [[ "${DRY_RUN}" == true ]]; then
    echo ""
    info "[DRY-RUN] Would download: ${DOWNLOAD_URL}"
    info "[DRY-RUN] Install to: ${INSTALL_PATH}"
    info "[DRY-RUN] Mirror: ${MIRROR_DISPLAY_NAME}"
    info "[DRY-RUN] Command: bash ${LOCAL_INSTALLER} -b -p ${INSTALL_PATH}"
    exit 0
fi

info "Downloading from: ${DOWNLOAD_URL}"
if [[ "${DOWNLOAD_TOOL}" == "curl" ]]; then
    curl -L -f --progress-bar -o "${LOCAL_INSTALLER}" "${DOWNLOAD_URL}" || die "Download failed. URL: ${DOWNLOAD_URL}"
else
    wget --progress=bar:force -O "${LOCAL_INSTALLER}" "${DOWNLOAD_URL}" || die "Download failed. URL: ${DOWNLOAD_URL}"
fi

if [[ ! -s "${LOCAL_INSTALLER}" ]]; then
    die "Downloaded installer is empty. The download may have failed."
fi
info "Download complete."

# ============================================================
# Step 4: Install Miniconda
# ============================================================
step 4 "${TOTAL_STEPS}" "Installing Miniconda..."

info "Install path: ${INSTALL_PATH}"
bash "${LOCAL_INSTALLER}" -b -p "${INSTALL_PATH}" || die "Miniconda installation failed."

if [[ ! -x "${INSTALL_PATH}/bin/conda" ]]; then
    die "Installation failed: conda binary not found at ${INSTALL_PATH}/bin/conda"
fi

CONDA_VER="$("${INSTALL_PATH}/bin/conda" --version 2>/dev/null || echo 'unknown')"
info "Miniconda ${CONDA_VER} installed successfully."

# ============================================================
# Step 5: Post-install configuration
# ============================================================
step 5 "${TOTAL_STEPS}" "Configuring conda..."

# conda init
info "Running conda init..."
"${INSTALL_PATH}/bin/conda" init || warn "conda init reported a warning."

# Write ~/.condarc with selected mirror
CONDARC_PATH="${HOME}/.condarc"
if [[ -f "${CONDARC_PATH}" ]]; then
    BACKUP="${CONDARC_PATH}.bak.$(date +%s)"
    cp "${CONDARC_PATH}" "${BACKUP}"
    warn "Existing ~/.condarc backed up to ${BACKUP}"
fi

info "Writing ${MIRROR_DISPLAY_NAME} mirror config to ~/.condarc..."
cat > "${CONDARC_PATH}" << CONDARC
channels:
  - conda-forge
custom_channels:
  conda-forge: ${MIRROR_CLOUD_URL}
  bioconda: ${MIRROR_CLOUD_URL}
show_channel_urls: true
CONDARC

# Accept Anaconda ToS for default channels (fallback guard; conda >= 24.9 only,
# older versions lack the subcommand and are silently skipped)
info "Accepting Anaconda ToS for default channels..."
for ch in "https://repo.anaconda.com/pkgs/main" "https://repo.anaconda.com/pkgs/r" "https://repo.anaconda.com/pkgs/msys2"; do
    "${INSTALL_PATH}/bin/conda" tos accept --override-channels --channel "${ch}" >/dev/null 2>&1 || true
done

# Cleanup installer
rm -f "${LOCAL_INSTALLER}"
info "Installer cleaned up."

# Disable the EXIT trap since we finished successfully
trap - EXIT

# --- Success message ---
SHELL_RC=""
if [[ -n "${ZSH_VERSION:-}" ]]; then
    SHELL_RC="~/.zshrc"
elif [[ -n "${BASH_VERSION:-}" ]]; then
    SHELL_RC="~/.bashrc"
else
    SHELL_RC="your shell rc file"
fi

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} Miniconda installed successfully!${NC}"
echo ""
echo "  Location:  ${INSTALL_PATH}"
echo "  Version:   ${CONDA_VER}"
echo "  Mirror:    ${MIRROR_DISPLAY_NAME}"
echo ""
echo "To activate conda, run ONE of:"
echo "  source ${SHELL_RC}"
echo "  Or restart your terminal"
echo ""
echo "Then verify with:"
echo "  conda --version"
echo "  conda config --show channels"
echo -e "${GREEN}============================================================${NC}"
