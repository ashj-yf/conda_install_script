#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly MIRROR_BASE_URL="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda"
readonly DEFAULT_INSTALL_PATH="${HOME}/miniconda3"
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

# --- Arguments ---
FORCE=false
DRY_RUN=false
DO_CLEAN=false
INSTALL_PATH=""

usage() {
cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install Miniconda (latest) from Tsinghua mirror.

Options:
  --force       Skip checks for existing conda and install path
  --path PATH   Custom installation path (default: \$HOME/miniconda3)
  --dry-run     Print detection info and download URL without executing
  --clean       Remove downloaded installer file and exit
  --help        Show this help message
  --version     Print script version

Environment variables:
  CONDA_INSTALL_PATH  Override default install path (same as --path)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)   FORCE=true; shift ;;
        --path)    INSTALL_PATH="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --clean)   DO_CLEAN=true; shift ;;
        --help)    usage; exit 0 ;;
        --version) echo "${SCRIPT_VERSION}"; exit 0 ;;
        *)         die "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# Resolve install path: CLI arg > env var > default
INSTALL_PATH="${INSTALL_PATH:-${CONDA_INSTALL_PATH:-$DEFAULT_INSTALL_PATH}}"

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
DOWNLOAD_URL="${MIRROR_BASE_URL}/${INSTALLER_FILENAME}"

info "OS: ${CONDA_OS}  |  Arch: ${CONDA_ARCH}  |  Installer: ${INSTALLER_FILENAME}"

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

# Write ~/.condarc with Tsinghua mirror
CONDARC_PATH="${HOME}/.condarc"
if [[ -f "${CONDARC_PATH}" ]]; then
    BACKUP="${CONDARC_PATH}.bak.$(date +%s)"
    cp "${CONDARC_PATH}" "${BACKUP}"
    warn "Existing ~/.condarc backed up to ${BACKUP}"
fi

info "Writing Tsinghua mirror config to ~/.condarc..."
cat > "${CONDARC_PATH}" << 'CONDARC'
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
CONDARC

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
echo "  Mirror:    Tsinghua (mirrors.tuna.tsinghua.edu.cn)"
echo ""
echo "To activate conda, run ONE of:"
echo "  source ${SHELL_RC}"
echo "  Or restart your terminal"
echo ""
echo "Then verify with:"
echo "  conda --version"
echo "  conda config --show channels"
echo -e "${GREEN}============================================================${NC}"
