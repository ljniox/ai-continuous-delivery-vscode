#!/bin/bash
set -euo pipefail

# Script de configuration complète du VPS pour l'IA en livraison continue

echo "🚀 Configuration du VPS pour l'IA en livraison continue..."

# Variables
GITHUB_REPO="ai-continuous-delivery"
GITHUB_USER="ljniox"

# Fonction de log avec couleur
log() {
    echo -e "\033[1;32m[$(date +'%H:%M:%S')]\033[0m $1"
}

error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

# Mise à jour du système
log "📦 Mise à jour du système..."
sudo apt update && sudo apt upgrade -y

# Installation des dépendances système
log "🔧 Installation des dépendances système..."
sudo apt install -y \
    curl wget git jq \
    python3 python3-pip python3-venv \
    nodejs npm \
    docker.io docker-compose \
    build-essential

# S'assurer que Docker fonctionne
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER

log "✅ Docker configuré"

# Installation de Claude Code
log "🤖 Installation de Claude Code..."
if ! command -v claude &> /dev/null; then
    curl -fsSL https://claude.ai/install.sh | bash
    export PATH="$PATH:$HOME/.local/bin"
    echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
else
    log "Claude Code déjà installé"
fi

# Installation de Supabase CLI
log "⚡ Installation de Supabase CLI..."
if ! command -v supabase &> /dev/null; then
    curl -fsSL https://supabase.com/install.sh | sh
    export PATH="$PATH:$HOME/.local/bin"
else
    log "Supabase CLI déjà installé"
fi

# Installation des dépendances Python globales
log "🐍 Installation des dépendances Python..."
python3 -m pip install --upgrade pip
pip3 install supabase pytest pytest-cov requests

# Installation des dépendances Node.js globales
log "📦 Installation des dépendances Node.js..."
sudo npm install -g @playwright/test

# Créer le répertoire de travail
WORK_DIR="/home/$USER/ai-cd-runner"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

log "📁 Répertoire de travail: $WORK_DIR"

# Configuration Git globale
log "📝 Configuration Git..."
git config --global user.name "AI Continuous Delivery Runner"
git config --global user.email "ai-cd-runner@example.com"
git config --global init.defaultBranch main

# Créer le service systemd pour les actions GitHub (préparation)
log "⚙️  Préparation du service GitHub Actions Runner..."
sudo mkdir -p /opt/actions-runner
sudo chown $USER:$USER /opt/actions-runner

cat > /tmp/github-runner.service << 'EOF'
[Unit]
Description=GitHub Actions Runner
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/actions-runner
ExecStart=/opt/actions-runner/run.sh
Restart=always
RestartSec=10
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/ubuntu/.local/bin
Environment=HOME=/home/ubuntu

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/github-runner.service /etc/systemd/system/
sudo systemctl daemon-reload

log "🔧 Configuration des variables d'environnement..."
cat >> ~/.bashrc << 'EOF'

# AI Continuous Delivery Environment
export SUPABASE_A_URL="https://zhfkjwptbmbrbnorprji.supabase.co"
export SUPABASE_B_URL="https://dyxoofvqukenklzwlvfn.supabase.co"
export ARCHON_URL="http://localhost:8181"
export ARCHON_MCP_URL="http://localhost:8051"
export PATH="$PATH:$HOME/.local/bin"
EOF

# Recharger les variables d'environnement
source ~/.bashrc

log "✅ Configuration du VPS terminée !"
echo ""
echo "🔑 Actions manuelles restantes:"
echo "1. Connecter Claude Code: claude login"
echo "2. Connecter Supabase: supabase login"
echo "3. Configurer GitHub Actions Runner (voir instructions ci-dessous)"
echo "4. Ajouter les secrets GitHub:"
echo "   - SUPABASE_B_URL"
echo "   - SUPABASE_B_SERVICE_ROLE" 
echo "   - DASHSCOPE_API_KEY"
echo ""
echo "📋 Commandes pour GitHub Actions Runner:"
echo "cd /opt/actions-runner"
echo "curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz"
echo "tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz"
echo "./config.sh --url https://github.com/$GITHUB_USER/$GITHUB_REPO --token YOUR_GITHUB_TOKEN"
echo "sudo systemctl enable github-runner"
echo "sudo systemctl start github-runner"