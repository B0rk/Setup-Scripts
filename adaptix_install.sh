#!/usr/bin/env bash
#
# Adaptix C2 all-in-one installer
# Streamlined by Kyle Hoehn, 06/06/2025
#

set -euo pipefail
IFS=$'\n\t'

# ─── Configuration ──────────────────────────────────────────────────────────────

# Where to assemble the final framework
INSTALL_DIR="$HOME/Adaptix_C2_Framework"

# Repositories to clone
declare -A REPOS=(
  ["AdaptixC2"]="https://github.com/Adaptix-Framework/AdaptixC2.git"
  ["Extension-Kit"]="https://github.com/Adaptix-Framework/Extension-Kit.git"
)

# Dependencies (all in one apt step)
DEPS=(
  golang-1.24 mingw-w64 make libxkbcommon-dev cmake libssl-dev qt6-base-dev qt6-websockets-dev gcc g++ build-essential libssl-dev qt6-declarative-dev
)

# Extensions subdirectories to build under Extension-Kit
EXT_DIRS=(
  AD-BOF Creds-BOF Elevation-BOF Execution-BOF
  Injection-BOF Kerbeus-BOF LateralMovement-BOF
  Process-BOF SAL-BOF SAR-BOF
)

# Server and beacon certificate subjects
SERVER_SUBJ="/C=US/ST=New York/L=New York/O=Hacker/OU=Offensive Security/CN=Hacker/emailAddress=noreply@hacker.com"
BEACON_SUBJ="/C=US/ST=Washington/L=Redmond/O=Microsoft Corporation/OU=Windows Update Services/CN=MSDN/emailAddress=noreply@microsoft.com"

# ─── Logging Helpers ────────────────────────────────────────────────────────────

RED="\033[0;31m" YELLOW="\033[0;33m" GREEN="\033[0;32m" NC="\033[0m"

info()    { echo -e "${YELLOW}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[ OK ]${NC} $*"; }
failure() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# ─── CMake Upgrade Checker ─────────────────────────────────────────────

ensure_cmake() {
  local installed_version major minor patch current_number required_number new_version

  # 1. Detect current CMake version (or default to "0.0.0" if missing)
  if ! command -v cmake &> /dev/null; then
    installed_version="0.0.0"
  else
    installed_version=$(cmake --version | head -n1 | awk '{print $3}')
  fi

  # 2. Convert "MAJOR.MINOR.PATCH" → integer for comparison
  IFS='.' read -r major minor patch <<< "$installed_version"
  current_number=$((10#${major} * 1000000 + 10#${minor} * 1000 + 10#${patch}))
  required_number=$((10#3 * 1000000 + 10#29 * 1000 + 10#0))

  # 3. If existing version < 3.29.0, uninstall apt-cmake and install via snap
  if [ "$current_number" -lt "$required_number" ]; then
    info "Detected CMake ${installed_version} (< 3.29). Upgrading via snap..."

    # 3a. If an apt-installed cmake exists, remove it
    if dpkg -l | grep -qi '^ii  cmake '; then
      info "Removing older apt‐installed CMake package..."
      sudo apt remove -y cmake
      success "Removed apt CMake."
    fi

    # 3b. Ensure snapd is available
    if ! command -v snap &> /dev/null; then
      info "Installing snapd (required to get modern CMake)..."
      sudo apt update
      sudo apt install -y snapd
      success "snapd installed."
    fi

    # 3c. Install the latest CMake from snap
    info "Installing latest CMake via 'snap install cmake --classic'..."
    sudo snap remove cmake        &> /dev/null || true
    sudo snap install cmake --classic
    success "Snap‐CMake install invoked."

    # 3d. Ensure that /snap/bin is earlier in PATH, so `cmake` resolves correctly
    export PATH="/snap/bin:$PATH"
    new_version=$(cmake --version | head -n1 | awk '{print $3}')

    # 3e. Compare new version
    IFS='.' read -r major minor patch <<< "$new_version"
    if [ $((10#${major} * 1000000 + 10#${minor} * 1000 + 10#${patch})) -lt "$required_number" ]; then
      failure "CMake upgrade failed or version still < 3.29 (found ${new_version})."
    fi

    success "CMake upgraded to ${new_version} (≧ 3.29)."
  else
    info "CMake ${installed_version} is ≥ 3.29; no upgrade needed."
  fi
}

# ─── Prerequisites ──────────────────────────────────────────────────────────────
command -v apt &> /dev/null || failure "apt not found; this script requires Debian/Ubuntu"

info "Updating package lists and installing dependencies..."
sudo apt update
sudo apt install -y "${DEPS[@]}"
success "Dependencies installed."

# ─── Ensure we have CMake ≥ 3.29 before building AX-Support-Soft ───────────────
ensure_cmake

# ─── Workspace Preparation ───────────────────────────────────────────────────────

info "Creating install directory at ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
success "Workspace ready."

# ─── Functions ──────────────────────────────────────────────────────────────────

clone_repo() {
  local name=$1 url=$2
  info "Cloning ${name}..."
  rm -rf "/tmp/${name}"
  git clone "${url}" "/tmp/${name}"
  success "Cloned ${name}."
}

build_adaptix() {
  info "Building AdaptixC2 server, extenders, and client..."
  pushd "/tmp/AdaptixC2" >/dev/null
    make server
    make extenders
    make client
  popd >/dev/null
  success "AdaptixC2 built."
}

generate_certs() {
  info "Generating X.509 certificates..."
  pushd "/tmp/AdaptixC2/dist" >/dev/null
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout server.rsa.key -out server.rsa.crt -days 3650 -subj "${SERVER_SUBJ}"
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout beacon.rsa.key -out beacon.rsa.crt -days 3650 -subj "${BEACON_SUBJ}"
  popd >/dev/null
  success "Certificates generated."
}

install_adaptix() {
  info "Installing AdaptixC2 framework to ${INSTALL_DIR}..."
  cp -R /tmp/AdaptixC2/dist/* "${INSTALL_DIR}"
  mv "${INSTALL_DIR}/AdaptixClient" "${INSTALL_DIR}/adaptix-client"
  mv "${INSTALL_DIR}/adaptixserver" "${INSTALL_DIR}/adaptix-server"
  success "AdaptixC2 installed."
}

build_extensions() {
  info "Building Extension-Kit modules..."
  pushd "/tmp/Extension-Kit" >/dev/null
    # remove metadata files
    rm -f .gitignore LICENSE README.md
    mkdir -p Build
    for d in "${EXT_DIRS[@]}"; do
      if [ -d "${d}" ]; then
        info "  └─ ${d}"
        pushd "${d}" >/dev/null
          make
        popd >/dev/null
      else
        info "  └─ Skipping missing ${d}"
      fi
    done
    # copy all built BOFs into extensions directory
    mkdir -p "${INSTALL_DIR}/extensions"
    cp -R ./* "${INSTALL_DIR}/extensions/"
  popd >/dev/null
  success "Extensions installed."
}

cleanup() {
  info "Cleaning up temporary repositories..."
  rm -rf /tmp/AdaptixC2 /tmp/Extension-Kit
  success "Cleanup complete."
}

# ─── Main Execution ─────────────────────────────────────────────────────────────

clone_repo "AdaptixC2"     "${REPOS[AdaptixC2]}"
clone_repo "Extension-Kit"  "${REPOS[Extension-Kit]}"

build_adaptix
generate_certs
install_adaptix


build_extensions

cleanup

clear
echo -e "${GREEN}✔ All files and folder structure have been created.${NC}"
echo "Everything needed to use Adaptix Framework is in: ${INSTALL_DIR}"
echo "Please modify 'profile.json' in that folder to set up your server profile."
echo "Documentation: https://adaptix-framework.gitbook.io/adaptix-framework"
