#!/bin/bash
set -euo pipefail

# Script de déploiement pour Supabase Projet B (Control-Plane)
# Usage: ./deploy.sh <SUPABASE_B_URL> <SUPABASE_B_SERVICE_KEY>

if [ $# -ne 2 ]; then
    echo "Usage: $0 <SUPABASE_B_URL> <SUPABASE_B_SERVICE_KEY>"
    echo "Exemple: $0 https://xyz.supabase.co eyJhbG..."
    exit 1
fi

SUPABASE_B_URL="$1"
SUPABASE_B_SERVICE_KEY="$2"

echo "🚀 Déploiement Supabase Projet B..."
echo "URL: $SUPABASE_B_URL"

# Vérifier que supabase CLI est installé
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI n'est pas installé"
    echo "Installation: curl -fsSL https://raw.githubusercontent.com/supabase/supabase/main/install.sh | sh"
    exit 1
fi

# Créer le projet Supabase local si nécessaire
if [ ! -f "supabase/config.toml" ]; then
    echo "📝 Initialisation du projet Supabase local..."
    supabase init
fi

# Configurer les variables d'environnement pour les Edge Functions
export SUPABASE_URL="$SUPABASE_B_URL"
export SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_B_SERVICE_KEY"

# Déployer le schéma SQL
echo "🗄️  Application du schéma SQL..."
# Note: Vous devrez appliquer manuellement schema.sql via l'interface Supabase
# ou utiliser la commande suivante si vous avez configuré le linking:
# supabase db push

echo "📦 Création du bucket Storage 'automation'..."
echo "⚠️  À faire manuellement dans l'interface Supabase:"
echo "   1. Aller dans Storage > Buckets"
echo "   2. Créer un bucket public 'automation'"
echo "   3. Créer les dossiers: specs/, reports/"

echo "⚡ Déploiement des Edge Functions..."

# Déployer ingest_email
supabase functions deploy ingest_email \
    --project-ref=$(echo $SUPABASE_B_URL | sed 's/.*\/\/\([^.]*\).*/\1/') || echo "❌ Échec déploiement ingest_email"

# Déployer notify_report  
supabase functions deploy notify_report \
    --project-ref=$(echo $SUPABASE_B_URL | sed 's/.*\/\/\([^.]*\).*/\1/') || echo "❌ Échec déploiement notify_report"

echo "✅ Déploiement terminé !"
echo ""
echo "🔧 Actions manuelles restantes:"
echo "1. Appliquer schema.sql via l'interface Supabase (SQL Editor)"
echo "2. Créer le bucket 'automation' avec dossiers specs/ et reports/"
echo "3. Configurer les variables d'environnement des Edge Functions:"
echo "   - SUPABASE_URL: $SUPABASE_B_URL"
echo "   - SUPABASE_SERVICE_ROLE_KEY: [votre clé]"
echo "   - GITHUB_TOKEN: [votre token GitHub]"
echo "   - TARGET_REPO: [nom du repo, ex: username/repo]"
echo "   - SMTP_ENDPOINT: [optionnel, pour les emails]"
echo "   - SMTP_TOKEN: [optionnel, pour les emails]"
echo ""
echo "4. Tester les fonctions:"
echo "   curl -X POST $SUPABASE_B_URL/functions/v1/ingest_email"
echo "   curl -X POST $SUPABASE_B_URL/functions/v1/notify_report"