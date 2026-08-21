#!/usr/bin/env bash
# ==============================================================================
# Automated Provisioning Script for SkillSpector & OpenClaw on Ubuntu ARM (VM)
# Run inside your Ubuntu 24.04 ARM Virtual Machine
# ==============================================================================

set -e

echo "🚀 Starting Automated VM Provisioning for SkillSpector & OpenClaw..."

# 1. Update system packages
echo "📦 Updating system packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y git python3 python3-pip python3-venv curl build-essential wget software-properties-common

# 2. Install Node.js 22 (LTS)
echo "🟢 Installing Node.js 22 (LTS)..."
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
echo "Node Version: $(node -v)"

# 3. Install pnpm
echo "⚡ Installing pnpm..."
curl -fsSL https://get.pnpm.io/install.sh | sh -
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"

# 4. Install OpenClaw CLI
echo "🦅 Installing OpenClaw CLI..."
$PNPM_HOME/pnpm add -g openclaw
export PATH="$HOME/.local/share/pnpm/global/5/node_modules/.bin:$PATH"

# 5. Onboard OpenClaw Workspace
echo "⚙️ Initializing OpenClaw Workspace..."
openclaw onboard --non-interactive --accept-risk || true

# 6. Setup SkillSpector Virtual Environment
echo "🛡️ Setting up SkillSpector Virtual Environment..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLSPECTOR_DIR="$SCRIPT_DIR/skillspector"

if [ -d "$SKILLSPECTOR_DIR" ]; then
    python3 -m venv "$SKILLSPECTOR_DIR/.venv"
    source "$SKILLSPECTOR_DIR/.venv/bin/activate"
    pip install --upgrade pip
    pip install -e "$SKILLSPECTOR_DIR"
    echo "✅ SkillSpector successfully installed in virtual environment!"
else
    echo "⚠️ SkillSpector directory not found at $SKILLSPECTOR_DIR. Skipping venv setup."
fi

# 7. Add PATH exports to ~/.bashrc
echo "📝 Updating ~/.bashrc..."
if ! grep -q "PNPM_HOME" "$HOME/.bashrc"; then
    cat << 'EOF' >> "$HOME/.bashrc"

# SkillSpector & OpenClaw Environment
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
alias skillspector="$HOME/skillspector/.venv/bin/skillspector"
EOF
fi

echo ""
echo "=============================================================================="
echo "🎉 Provisioning Complete!"
echo "OpenClaw: $(openclaw --version 2>/dev/null || echo 'Installed')"
echo "To activate SkillSpector, run: source ~/.bashrc"
echo "=============================================================================="
