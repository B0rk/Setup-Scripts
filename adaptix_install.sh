#!/usr/bin/env bash
#
# Adaptix C2 all-in-one installer
# Streamlined by Kyle Hoehn 05/23/2025
#

set -euo pipefail
IFS=$'\n\t'

# ─── Configuration ──────────────────────────────────────────────────────────────

INSTALL_DIR="$HOME/Adaptix_C2_Framework"
declare -A REPOS=(
  ["AdaptixC2"]="https://github.com/Adaptix-Framework/AdaptixC2.git"
  ["AX-Support-Soft"]="https://github.com/Adaptix-Framework/AX-Support-Soft.git"
  ["Extension-Kit"]="https://github.com/Adaptix-Framework/Extension-Kit.git"
)
DEPS=(
  golang-1.24 mingw-w64 make libxkbcommon-dev cmake libssl-dev
  qt6-base-dev qt6-websockets-dev
)
EXT_DIRS=(
  AD-BOF Creds-BOF Elevation-BOF Execution-BOF
  Injection-BOF Kerbeus-BOF LateralMovement-BOF
  Process-BOF SAL-BOF SAR-BOF
)
SERVER_SUBJ="/C=US/ST=Washington/L=Redmond/O=Microsoft Corporation/OU=Windows Update Services/CN=MSDN/emailAddress=noreply@microsoft.com"
BEACON_SUBJ="/C=US/ST=Washington/L=Redmond/O=Microsoft Corporation/OU=Windows Update Services/CN=MSDN/emailAddress=noreply@microsoft.com"

# ─── Logging Helpers ────────────────────────────────────────────────────────────

RED="\033[0;31m" YELLOW="\033[0;33m" GREEN="\033[0;32m" NC="\033[0m"

info()    { echo -e "${YELLOW}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[ OK ]${NC} $*"; }
failure() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# ─── CMake Upgrade Checker ─────────────────────────────────────────────────────

ensure_cmake() {
  if ! command -v cmake &> /dev/null; then
    version="0.0.0"
  else
    version=$(cmake --version | head -n1 | awk '{print $3}')
  fi

  IFS='.' read -r major minor patch <<< "$version"
  current_number=$((10#${major} * 1000000 + 10#${minor} * 1000 + 10#${patch}))
  required_number=$((10#3 * 1000000 + 10#29 * 1000 + 10#0))

  if [ "$current_number" -lt "$required_number" ]; then
    info "Detected CMake $version (< 3.29). Upgrading via snap..."
    if ! command -v snap &> /dev/null; then
      info "Installing snapd..."
      sudo apt update
      sudo apt install -y snapd
      success "snapd installed."
    fi

    sudo snap remove cmake &> /dev/null || true
    sudo snap install cmake --classic

    newver=$(cmake --version | head -n1 | awk '{print $3}')
    if [ "$(echo "$newver" | awk -F. '{ print $1 * 1000000 + $2 * 1000 + $3 }')" -lt "$required_number" ]; then
      failure "CMake upgrade failed or version still < 3.29 (found $newver)."
    fi
    success "CMake upgraded to $newver."
  else
    info "CMake $version is ≥ 3.29; no upgrade needed."
  fi
}

# ─── Prerequisites ──────────────────────────────────────────────────────────────

command -v apt &> /dev/null || failure "apt not found; this script requires Debian/Ubuntu"

info "Updating package lists and installing dependencies..."
sudo apt update
sudo apt install -y "${DEPS[@]}"
success "Dependencies installed."

# Make sure CMake is ≥ 3.29 before we try to build AX-Support-Soft
ensure_cmake

# ─── Workspace Preparation ───────────────────────────────────────────────────────

info "Creating install directory at ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
success "Workspace ready."

# ─── [Rest of your functions remain unchanged] ─────────────────────────────────

clone_repo() { … }
build_adaptix() { … }
generate_certs() { … }
install_adaptix() { … }
build_support_tools() { … }
build_extensions() { … }
cleanup() { … }

# ─── Main Execution ─────────────────────────────────────────────────────────────

clone_repo "AdaptixC2"     "${REPOS[AdaptixC2]}"
clone_repo "AX-Support-Soft" "${REPOS[AX-Support-Soft]}"
clone_repo "Extension-Kit"  "${REPOS[Extension-Kit]}"

build_adaptix
generate_certs
install_adaptix

build_support_tools
build_extensions

cleanup

clear
echo -e "${GREEN}✔ All files and folder structure have been created.${NC}"
echo "${YELLOW}Everything needed to use Adaptix Framework is in: ${INSTALL_DIR}${NC}"
echo "${YELLOW}Please modify 'profile.json' in that folder to set up your server profile.${NC}"
echo "${GREEN}Documentation:${NC} https://adaptix-framework.gitbook.io/adaptix-framework"
