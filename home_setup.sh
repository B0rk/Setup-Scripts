#!/usr/bin/env bash
#
#
# This script installs ligolo-ng and mimikatz (via apt), then sets up
# a suite of tooling and directories under the invoking (non-root) user’s home.
# Even if executed with sudo, all files will belong to the original user.
#
# Usage: sudo ./home_setup.sh
#

set -euo pipefail
IFS=$'\n\t'

# ─── Determine Original User ────────────────────────────────────────────────────
# If run under sudo, SUDO_USER will be set to the calling user. Otherwise, fall back to the login name.
if [[ -n "${SUDO_USER-}" ]]; then
  ORIGINAL_USER="$SUDO_USER"
else
  ORIGINAL_USER="$(logname 2>/dev/null || echo "$USER")"
fi

# Obtain the home directory of the original user
USER_HOME="$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)"

# Confirm that USER_HOME is non‐empty
if [[ -z "$USER_HOME" ]]; then
  echo "Error: Unable to determine home directory for user '$ORIGINAL_USER'." >&2
  exit 1
fi

# ─── Step 1: Install Required Packages (as root) ─────────────────────────────────
# Only this section requires true root privileges; everything else will drop back to $ORIGINAL_USER.

echo "[*] Installing ligolo-ng and mimikatz via apt…"
apt update
DEBIAN_FRONTEND=noninteractive apt install -y ligolo-ng mimikatz

# ─── Step 2: Remove Default “User” Directories (in $USER_HOME) ───────────────────
# Because this script runs under sudo, removing them as root is acceptable,
# but we point to $USER_HOME explicitly (never “~/”) so root’s home isn’t affected.

echo "[*] Removing standard user directories under $USER_HOME…"
rm -rf "$USER_HOME/Music" \
       "$USER_HOME/Public" \
       "$USER_HOME/Templates" \
       "$USER_HOME/Videos" \
    || true

# ─── Step 3: Create Base Folders Under $USER_HOME ────────────────────────────────
# Use mkdir -p so it does nothing if they already exist. Then chown them to $ORIGINAL_USER.

echo "[*] Creating base tool directories under $USER_HOME…"
mkdir -p "$USER_HOME/Tools" \
         "$USER_HOME/Upload" \
         "$USER_HOME/Shellcode_Loaders"

chown "$ORIGINAL_USER":"$ORIGINAL_USER" \
      "$USER_HOME/Tools" \
      "$USER_HOME/Upload" \
      "$USER_HOME/Shellcode_Loaders"

# ─── Step 4: Create Subdirectories for Each Tool ─────────────────────────────────
# We create ligolo‐binaries, mimikatz‐binaries, peas-ng under both Tools and Upload.
echo "[*] Creating subdirectories for ligolo, mimikatz, peas-ng…"
mkdir -p \
  "$USER_HOME/Tools/ligolo-binaries"       \
  "$USER_HOME/Upload/ligolo-binaries"      \
  "$USER_HOME/Tools/mimikatz-binaries"     \
  "$USER_HOME/Upload/mimikatz-binaries"    \
  "$USER_HOME/Tools/peas-ng"               \
  "$USER_HOME/Upload/peas-ng"

chown -R "$ORIGINAL_USER":"$ORIGINAL_USER" \
      "$USER_HOME/Tools" "$USER_HOME/Upload"

# ─── Step 5: Download Useful Scripts (as $ORIGINAL_USER) ────────────────────────
# Since wget invoked as root would create root-owned files, we explicitly sudo -u back to ORIGINAL_USER.

echo "[*] Downloading web_upload.py into $USER_HOME…"
sudo -u "$ORIGINAL_USER" wget -q -O "$USER_HOME/web_upload.py" \
  "https://raw.githubusercontent.com/B0rk/ChatGPT-Generated-Scripts/refs/heads/main/web_upload.py"

echo "[*] Downloading PEASS-ng binaries into $USER_HOME/Tools/peas-ng…"
sudo -u "$ORIGINAL_USER" wget -q -P "$USER_HOME/Tools/peas-ng" \
  "https://github.com/peass-ng/PEASS-ng/releases/download/20250526-9bcce952/linpeas.sh"
sudo -u "$ORIGINAL_USER" wget -q -P "$USER_HOME/Tools/peas-ng" \
  "https://github.com/peass-ng/PEASS-ng/releases/download/20250526-9bcce952/linpeas_linux_amd64"
sudo -u "$ORIGINAL_USER" wget -q -P "$USER_HOME/Tools/peas-ng" \
  "https://github.com/peass-ng/PEASS-ng/releases/download/20250526-9bcce952/linpeas_linux_386"
sudo -u "$ORIGINAL_USER" wget -q -P "$USER_HOME/Tools/peas-ng" \
  "https://github.com/peass-ng/PEASS-ng/releases/download/20250526-9bcce952/winPEAS.bat"
sudo -u "$ORIGINAL_USER" wget -q -P "$USER_HOME/Tools/peas-ng" \
  "https://github.com/peass-ng/PEASS-ng/releases/download/20250526-9bcce952/winPEASany_ofs.exe"
sudo -u "$ORIGINAL_USER" wget -q -P "$USER_HOME/Tools/peas-ng" \
  "https://github.com/peass-ng/PEASS-ng/releases/download/20250526-9bcce952/winPEASx64_ofs.exe"
sudo -u "$ORIGINAL_USER" wget -q -P "$USER_HOME/Tools/peas-ng" \
  "https://github.com/peass-ng/PEASS-ng/releases/download/20250526-9bcce952/winPEASx86_ofs.exe"

# Ensure the downloaded scripts are owned by ORIGINAL_USER
chown -R "$ORIGINAL_USER":"$ORIGINAL_USER" "$USER_HOME/Tools/peas-ng"
chown "$ORIGINAL_USER":"$ORIGINAL_USER" "$USER_HOME/web_upload.py"

# Ensure ownership of the cloned repo
chown -R "$ORIGINAL_USER":"$ORIGINAL_USER" "$USER_HOME/Shellcode_Loaders"

# ─── Step 6: Copy Installed Binaries into User Directories ───────────────────────
# The /usr/share/… paths exist because apt install ligolo-ng/mimikatz was done as root.
echo "[*] Copying mimikatz binaries to user’s Tools and Upload…"
cp -R /usr/share/windows-resources/mimikatz/* \
      "$USER_HOME/Tools/mimikatz-binaries"
cp -R /usr/share/windows-resources/mimikatz/* \
      "$USER_HOME/Upload/mimikatz-binaries"

echo "[*] Copying ligolo-ng binaries to user’s Tools and Upload…"
cp -R /usr/share/ligolo-ng-common-binaries/* \
      "$USER_HOME/Tools/ligolo-binaries"
cp -R /usr/share/ligolo-ng-common-binaries/* \
      "$USER_HOME/Upload/ligolo-binaries"

echo "[*] Copying PEASS-ng files from Tools to Upload…"
cp -R "$USER_HOME/Tools/peas-ng/"* "$USER_HOME/Upload/peas-ng/"

# Fix ownership on everything copied
chown -R "$ORIGINAL_USER":"$ORIGINAL_USER" \
      "$USER_HOME/Tools" "$USER_HOME/Upload"

# ─── Step 7: Append Useful Commands to $USER_HOME/.zsh_history ───────────────────
# We wrap each echo in sudo -u … bash -c "…" so that lines go into the correct .zsh_history.

echo "[*] Appending common commands to $USER_HOME/.zsh_history…"
sudo -u "$ORIGINAL_USER" bash -c \
  "echo 'python3 $USER_HOME/web_upload.py --port 4444 --directory $USER_HOME/Upload' >> '$USER_HOME/.zsh_history'"

sudo -u "$ORIGINAL_USER" bash -c \
  "echo 'cd Shellcode_Loaders' >> '$USER_HOME/.zsh_history'"

sudo -u "$ORIGINAL_USER" bash -c \
  "echo 'mcs -platform:x64 -target:winexe -out:cs_payload.exe \$HOME/cs_loader.cs' >> '$USER_HOME/.zsh_history'"

sudo -u "$ORIGINAL_USER" bash -c \
  "echo 'x86_64-w64-mingw32-gcc c_loader.c -o c_payload.exe -lbcrypt -DUSE_NT_INJECTION' >> '$USER_HOME/.zsh_history'"

sudo -u "$ORIGINAL_USER" bash -c \
  "echo 'cd /opt/adaptix_c2' >> '$USER_HOME/.zsh_history'"

sudo -u "$ORIGINAL_USER" bash -c \
  "echo './adaptix-server -profile profile.json' >> '$USER_HOME/.zsh_history'"

sudo -u "$ORIGINAL_USER" bash -c \
  "echo './adaptix-client' >> '$USER_HOME/.zsh_history'"

chown "$ORIGINAL_USER":"$ORIGINAL_USER" "$USER_HOME/.zsh_history"

# ─── Final Step: Summary and Ownership Verification ─────────────────────────────
echo "[*] Verifying ownership for all created/modified files..."
chown -R "$ORIGINAL_USER":"$ORIGINAL_USER" \
      "$USER_HOME/Tools" \
      "$USER_HOME/Upload" \
      "$USER_HOME/Shellcode_Loaders" \
      "$USER_HOME/web_upload.py" \
      "$USER_HOME/.zsh_history"

echo "[✔] Setup complete. All tools and directories reside under $USER_HOME, owned by $ORIGINAL_USER."
