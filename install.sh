#!/usr/bin/env bash
set -euo pipefail

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${BOLD}${GREEN}==> Installing system dependencies (DNF)...${RESET}"
sudo dnf install -y \
    python3 python3-pip python3-virtualenv \
    git openssh-clients yubikey-manager \
    pcsc-lite golang age

sudo systemctl enable --now pcscd

BIN_DIR="$HOME/.local/bin"
GO_BIN_DIR="$HOME/go/bin"
mkdir -p "$BIN_DIR" "$GO_BIN_DIR"

# Ensure PATH incorporates both local and Go binaries
export PATH="$GO_BIN_DIR:$BIN_DIR:$PATH"

if ! command -v sops &>/dev/null; then
    echo -e "${BOLD}${GREEN}==> Compiling SOPS from official source...${RESET}"
    go install github.com/getsops/sops/v3/cmd/sops@latest
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

echo -e "${BOLD}${GREEN}==> Setting up Python virtual environment...${RESET}"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip >/dev/null

# Install Python dependencies from requirements.txt if present
if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
    echo -e "${BOLD}${GREEN}==> Installing dependencies from requirements.txt...${RESET}"
    "$VENV_DIR/bin/pip" install -r "$SCRIPT_DIR/requirements.txt" >/dev/null
else
    echo -e "${BOLD}${YELLOW}==> requirements.txt not found. Installing default inline packages...${RESET}"
    "$VENV_DIR/bin/pip" install typer paramiko pyyaml rich fido2 >/dev/null
fi

echo -e "${BOLD}${GREEN}==> Symlinking hwkey executable wrapper to $BIN_DIR/hwkey...${RESET}"
cat <<EOF > "$BIN_DIR/hwkey"
#!/usr/bin/env bash
export PATH="\$HOME/go/bin:\$PATH"
exec "$VENV_DIR/bin/python3" "$SCRIPT_DIR/hwkey" "\$@"
EOF

chmod +x "$BIN_DIR/hwkey" "$SCRIPT_DIR/hwkey"

# Auto-append PATH configuration to ~/.bashrc if missing
if ! grep -q 'go/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo -e "${BOLD}${GREEN}==> Added ~/go/bin to ~/.bashrc${RESET}"
fi

echo -e "\n${BOLD}${GREEN}✔ Installation successful!${RESET}"