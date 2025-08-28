#!/bin/bash
set -euo pipefail

# Configuration automatique de Supabase Projet B
echo "🚀 Configuration de Supabase Projet B..."

# Variables
SUPABASE_B_URL="https://dyxoofvqukenklzwlvfn.supabase.co"
SUPABASE_B_SERVICE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5eG9vZnZxdWtlbmtsendsdmZuIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1NjM3Mzg4OSwiZXhwIjoyMDcxOTQ5ODg5fQ.-gETS_L8mWiOdNtd9Vk612zmZqPPR4xGgA0aVrg-Z8E"
PROJECT_REF="dyxoofvqukenklzwlvfn"

# Installer Supabase CLI si pas installé
if ! command -v supabase &> /dev/null; then
    echo "📦 Installation de Supabase CLI..."
    curl -fsSL https://supabase.com/install.sh | sh
    export PATH="$PATH:$HOME/.local/bin"
fi

# Créer le répertoire de travail pour Supabase B
cd /home/ubuntu/ai-continuous-delivery/supabase-b

# Initialiser le projet Supabase local si nécessaire
if [ ! -f "supabase/config.toml" ]; then
    echo "📝 Initialisation du projet Supabase local..."
    supabase init
fi

# Login vers Supabase (utilise un access token si disponible)
echo "🔐 Connexion à Supabase..."
# Pour l'instant, on skip le login automatique - tu devras faire: supabase login

echo "⚡ Déploiement des Edge Functions..."

# Déployer ingest_email
echo "Déploiement de ingest_email..."
if supabase functions deploy ingest_email --project-ref=$PROJECT_REF; then
    echo "✅ ingest_email déployée"
else
    echo "❌ Échec déploiement ingest_email"
fi

# Déployer notify_report
echo "Déploiement de notify_report..."
if supabase functions deploy notify_report --project-ref=$PROJECT_REF; then
    echo "✅ notify_report déployée"
else
    echo "❌ Échec déploiement notify_report"
fi

echo ""
echo "🔧 Configuration des variables d'environnement pour les Edge Functions..."
echo "À faire manuellement dans l'interface Supabase :"
echo "1. Aller dans Edge Functions > Settings"
echo "2. Ajouter ces variables d'environnement :"
echo "   SUPABASE_URL=$SUPABASE_B_URL"
echo "   SUPABASE_SERVICE_ROLE_KEY=$SUPABASE_B_SERVICE_KEY"
echo "   GITHUB_TOKEN=[ton token GitHub]"
echo "   TARGET_REPO=[username/repo-name]"
echo ""
echo "✅ Configuration terminée !"