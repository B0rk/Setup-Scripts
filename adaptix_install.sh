#!/usr/bin/env bash
#
# Adaptix C2 all-in-one installer
# Streamlined by Kyle Hoehn 05/23/2025
#

set -euo pipefail
IFS=$'\n\t'

# ─── Configuration ──────────────────────────────────────────────────────────────

# Where to assemble the final framework
INSTALL_DIR="$HOME/Adaptix_C2_Framework"

# Repositories to clone
declare -A REPOS=(
  ["AdaptixC2"]="https://github.com/Adaptix-Framework/AdaptixC2.git"
  ["AX-Support-Soft"]="https://github.com/Adaptix-Framework/AX-Support-Soft.git"
  ["Extension-Kit"]="https://github.com/Adaptix-Framework/Extension-Kit.git"
)

# Dependencies (all in one apt step)
DEPS=(
  golang-1.24 mingw-w64 make libxkbcommon-dev cmake libssl-dev
  qt6-base-dev qt6-websockets-dev
)

# Extensions subdirectories to build under Extension-Kit
EXT_DIRS=(
  AD-BOF Creds-BOF Elevation-BOF Execution-BOF
  Injection-BOF Kerbeus-BOF LateralMovement-BOF
  Process-BOF SAL-BOF SAR-BOF
)

# Server and beacon certificate subjects
SERVER_SUBJ="/C=US/ST=Washington/L=Redmond/O=Microsoft Corporation/OU=Windows Update Services/CN=MSDN/emailAddress=noreply@microsoft.com"
BEACON_SUBJ="/C=US/ST=Washington/L=Redmond/O=Microsoft Corporation/OU=Windows Update Services/CN=MSDN/emailAddress=noreply@microsoft.com"

# ─── Logging Helpers ────────────────────────────────────────────────────────────

RED="\033[0;31m" YELLOW="\033[0;33m" GREEN="\033[0;32m" NC="\033[0m"

info()    { echo -e "${YELLOW}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[ OK ]${NC} $*"; }
failure() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# ─── Prerequisites ──────────────────────────────────────────────────────────────

# Ensure script is run on a Debian-based system
command -v apt &> /dev/null || failure "apt not found; this script requires Debian/Ubuntu"

info "Updating package lists and installing dependencies..."
sudo apt update
sudo apt install -y "${DEPS[@]}"
success "Dependencies installed."

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
  cp -R "/tmp/AdaptixC2/dist/." "${INSTALL_DIR}"
  mv "${INSTALL_DIR}/AdaptixClient" "${INSTALL_DIR}/adaptix-client"
  mv "${INSTALL_DIR}/adaptixserver" "${INSTALL_DIR}/adaptix-server"
  success "AdaptixC2 installed."
}

build_support_tools() {
  for sub in AXchecker CmdChecker; do
    info "Building support tool: ${sub}..."
    pushd "/tmp/AX-Support-Soft/${sub}" >/dev/null
      mkdir -p Build && cd Build
      cmake .. && make
      cp "${sub}" "${INSTALL_DIR}/${sub}"
    popd >/dev/null
    success "Installed ${sub}."
  done
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
  rm -rf /tmp/AdaptixC2 /tmp/AX-Support-Soft /tmp/Extension-Kit
  sudo rm -rf "${HOME}/go"
  success "Cleanup complete."
}

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

info "Moving the completed framework to /opt/adaptix_c2..."
sudo mv "${INSTALL_DIR}" /opt/adaptix_c2
success "Framework moved to /opt/adaptix_c2."

OWNER="${SUDO_USER:-$USER}"

sudo chown -R "${OWNER}:${OWNER}" /opt/adaptix_c2/Adaptix_C2_Framework
# Give the owner read/write/execute as appropriate, remove group/other write/execute
sudo chmod -R u+rwX,go-rX    /opt/adaptix_c2/Adaptix_C2_Framework
success "Ownership changed to ${OWNER}, permissions set accordingly."

clear
echo -e "${GREEN}✔ All files and folder structure have been created.${NC}"
echo -e "${YELLOW}Everything needed to use Adaptix Framework is in: '/opt/adaptix_c2'${NC}"
echo -e "${YELLOW}Please modify 'profile.json' in that folder to set up your server profile.${NC}"
echo -e "${GREEN}Documentation:${NC} https://adaptix-framework.gitbook.io/adaptix-framework"
