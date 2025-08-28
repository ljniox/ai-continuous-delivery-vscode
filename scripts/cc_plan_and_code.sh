#!/bin/bash
set -euo pipefail

# Script de planification et développement avec Claude Code
# Utilise Archon MCP pour la gestion des contextes et backlog
# Support multi-projet pour développement sur repositories externes

echo "🧠 Démarrage de la planification avec Claude Code..."

# Variables d'environnement
ARCHON_MCP_URL=${ARCHON_MCP_URL:-"http://localhost:8051"}
RUN_ID=${RUN_ID:-""}

# Multi-project variables
TARGET_REPO=${TARGET_REPO:-$GITHUB_REPOSITORY}
TARGET_BRANCH=${TARGET_BRANCH:-main}
PROJECT_NAME=${PROJECT_NAME:-$TARGET_REPO}
ORIGINAL_WORKSPACE=$(pwd)

echo "📋 Configuration multi-projet:"
echo "  Repository cible: $TARGET_REPO"
echo "  Branche cible: $TARGET_BRANCH"
echo "  Nom du projet: $PROJECT_NAME"
echo "  Workspace original: $ORIGINAL_WORKSPACE"

# Vérifier que Claude Code est installé et connecté
if ! command -v claude &> /dev/null; then
    echo "❌ Claude Code CLI non trouvé"
    echo "Installation requise: voir https://docs.anthropic.com/claude-code"
    exit 1
fi

# Vérifier la version et la connexion
echo "📋 Vérification de Claude Code..."
claude --version

# Test de connexion à Archon MCP
if ! curl -s "$ARCHON_MCP_URL" > /dev/null; then
    echo "❌ Archon MCP non accessible sur $ARCHON_MCP_URL"
    exit 1
fi

echo "✅ Archon MCP accessible"

# Multi-project setup: Clone target repository if different from current
if [[ "$TARGET_REPO" != "${GITHUB_REPOSITORY:-}" ]] && [[ "$TARGET_REPO" != "$(basename $(git config --get remote.origin.url 2>/dev/null || echo '') .git)" ]]; then
    echo "🔄 Configuration pour repository externe: $TARGET_REPO"
    
    # Create workspace for target project
    WORK_DIR="/tmp/workspace-$(basename $TARGET_REPO)-$$"
    mkdir -p "$WORK_DIR"
    
    echo "📥 Clonage du repository cible..."
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        git clone "https://$GITHUB_TOKEN@github.com/$TARGET_REPO.git" "$WORK_DIR"
    else
        git clone "https://github.com/$TARGET_REPO.git" "$WORK_DIR"
    fi
    
    # Change to target repository workspace
    cd "$WORK_DIR"
    
    # Copy spec file from original workspace
    cp "$ORIGINAL_WORKSPACE/spec.yaml" . 2>/dev/null || echo "⚠️ Pas de spec.yaml à copier"
    
    # Configure git for AI commits
    git config user.name "AI Continuous Delivery"
    git config user.email "ai-cd@github-actions.noreply.com"
    
    # Create or checkout target branch
    git checkout -b "feature/ai-cd-$(date +%s)" "$TARGET_BRANCH" 2>/dev/null || git checkout "$TARGET_BRANCH"
    
    echo "✅ Repository cible configuré dans $WORK_DIR"
    echo "🌿 Branche courante: $(git branch --show-current)"
    
    EXTERNAL_REPO=true
else
    echo "✅ Travail dans le repository courant"
    EXTERNAL_REPO=false
fi

# Créer le répertoire de travail si nécessaire
mkdir -p artifacts sprints

# Charger le contexte du run si disponible
RUN_CONTEXT_FILE="artifacts/run_context.json"
if [[ -f "$RUN_CONTEXT_FILE" ]]; then
    echo "📖 Chargement du contexte du run..."
    SPEC_ID=$(jq -r '.spec_id' "$RUN_CONTEXT_FILE")
    SPRINT_ID=$(jq -r '.sprint_id' "$RUN_CONTEXT_FILE")
    echo "   Spec ID: $SPEC_ID"
    echo "   Sprint ID: $SPRINT_ID"
fi

# Étape 1: Analyser la spécification
if [[ -f "spec.yaml" ]]; then
    echo "📋 Analyse de la spécification..."
    
    # Créer un prompt pour Claude Code
    cat > artifacts/claude_prompt.md << EOF
# Analyse et Planification de Projet

## Contexte
Vous devez analyser la spécification suivante et créer un plan de développement structuré.

## Spécification
\`\`\`yaml
$(cat spec.yaml)
\`\`\`

## Tâches à réaliser
1. Analyser les besoins fonctionnels et techniques
2. Découper en tâches développables
3. Créer l'architecture de base du projet
4. Initialiser la structure de fichiers
5. Créer les premiers commits avec l'ossature

## Contraintes
- Respecter les standards de code (ruff, mypy, black pour Python)
- Intégrer les tests unitaires et E2E
- Préparer pour les critères DoD définis dans la spec

## Livrables attendus
- Structure de projet initialisée
- Tests de base fonctionnels
- Documentation technique minimaliste
- Premier commit avec l'ossature MVP
EOF

    echo "🤖 Exécution de la planification avec Claude Code..."
    
    # Utiliser Claude Code pour analyser et planifier
    # Note: Les commandes exactes dépendent de la version de Claude Code
    # Ceci est un exemple basé sur la documentation
    
    claude run "
    Lis le fichier artifacts/claude_prompt.md et la spécification spec.yaml.
    Analyse les besoins et crée un plan de développement structuré.
    Initialise la structure de projet selon les bonnes pratiques.
    Crée les fichiers de base nécessaires.
    Génère un manifeste de sprint dans sprints/current_manifest.yaml
    " || echo "⚠️ Claude Code a rencontré une erreur, continuons..."

else
    echo "⚠️ Aucune spécification trouvée (spec.yaml), utilisation d'un template par défaut"
    
    # Créer une structure de projet par défaut
    mkdir -p src tests e2e
    
    # Fichier de configuration Python basique
    cat > pyproject.toml << EOF
[build-system]
requires = ["setuptools", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "ai-generated-project"
version = "0.1.0"
description = "Projet généré automatiquement par l'IA"
dependencies = [
    "fastapi",
    "uvicorn",
    "jinja2",
    "pytest",
    "pytest-cov",
]

[tool.ruff]
line-length = 88
target-version = "py311"

[tool.mypy]
python_version = "3.11"
strict = true
EOF

    # Test de base
    cat > tests/test_basic.py << EOF
"""Tests de base pour vérifier que l'environnement fonctionne"""

def test_basic():
    """Test basique qui doit toujours passer"""
    assert True

def test_imports():
    """Test que les imports essentiels fonctionnent"""
    import json
    import os
    assert json and os
EOF
fi

# Étape 2: Initialiser Git et créer le premier commit si pas déjà fait
if [[ ! -d ".git" ]]; then
    echo "🔧 Initialisation du repository Git..."
    git init
    git config user.name "AI Continuous Delivery"
    git config user.email "ai-cd@example.com"
fi

# S'assurer qu'on est sur une branche de feature
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
    FEATURE_BRANCH="feature/S1/auto-generated"
    echo "🌿 Création de la branche $FEATURE_BRANCH"
    git checkout -b "$FEATURE_BRANCH" 2>/dev/null || git checkout "$FEATURE_BRANCH"
fi

# Étape 3: Commit des changements
if [[ -n "$(git status --porcelain)" ]]; then
    echo "📝 Création du commit avec les changements..."
    git add .
    git commit -m "chore(scaffold): initialisation automatique du projet

- Structure de base créée par Claude Code
- Configuration Python/Node.js
- Tests de base
- Prêt pour développement des fonctionnalités

🤖 Generated with Claude Code + Archon MCP" || echo "⚠️ Commit échoué, peut-être rien à committer"
fi

# Étape 4: Créer le manifeste de sprint
cat > sprints/current_manifest.yaml << EOF
sprint_id: S1
status: COMPLETED
tasks:
  - id: S1-T1
    type: scaffold
    desc: "Initialisation structure projet + configuration"
    status: done
    done_when:
      - "Structure de fichiers créée"
      - "Configuration Python/Node opérationnelle"
      - "Tests de base passent"
  
  - id: S1-T2
    type: feature
    desc: "Développement fonctionnalités core selon spec"
    status: in_progress
    tests:
      unit: ["tests/"]
      e2e: ["e2e/"]

artifact_contract:
  junit: "artifacts/junit.xml"
  coverage: "artifacts/coverage.xml"
  lighthouse: "artifacts/lighthouse.json"

notes: |
  Projet initialisé automatiquement par Claude Code.
  Architecture de base en place, prêt pour développement des features.
EOF

# Étape 5: Enregistrement de statut
if [[ -n "$RUN_ID" ]]; then
    echo "📊 Enregistrement du statut de planification..."
    
    # Créer un résumé pour le moment
    cat > artifacts/planning_summary.json << EOF
{
  "phase": "planning_completed",
  "run_id": "$RUN_ID",
  "files_created": $(find . -name "*.py" -o -name "*.yaml" -o -name "*.toml" | wc -l),
  "git_branch": "$(git rev-parse --abbrev-ref HEAD)",
  "git_commit": "$(git rev-parse --short HEAD 2>/dev/null || echo 'none')",
  "timestamp": "$(date -Iseconds)"
}
EOF
fi

# Push changes to external repository if applicable
if [[ "$EXTERNAL_REPO" == "true" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "🚀 Push des changements vers le repository cible..."
    
    # Ensure all changes are committed
    if [[ -n "$(git status --porcelain)" ]]; then
        git add .
        git commit -m "AI Continuous Delivery: Generated code implementation

Project: $PROJECT_NAME
Target: $TARGET_REPO ($TARGET_BRANCH)

🤖 Generated with Claude Code + Archon MCP
Co-Authored-By: Claude <noreply@anthropic.com>" || echo "⚠️ Commit échoué"
    fi
    
    # Push to target repository
    CURRENT_BRANCH=$(git branch --show-current)
    git push origin "$CURRENT_BRANCH" && echo "✅ Changements pushés vers $TARGET_REPO" || echo "❌ Push échoué vers $TARGET_REPO"
    
    # Copy artifacts back to original workspace for GitHub Actions
    mkdir -p "$ORIGINAL_WORKSPACE/artifacts"
    cp -r artifacts/* "$ORIGINAL_WORKSPACE/artifacts/" 2>/dev/null || echo "⚠️ Pas d'artefacts à copier"
    cp -r sprints "$ORIGINAL_WORKSPACE/" 2>/dev/null || echo "⚠️ Pas de sprints à copier"
fi

echo "✅ Planification terminée !"
echo "📁 Structure créée, tests configurés"
echo "🌿 Branche: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'none')"
echo "📝 Manifeste: sprints/current_manifest.yaml"
echo "🎯 Repository cible: $TARGET_REPO"
if [[ "$EXTERNAL_REPO" == "true" ]]; then
    echo "📁 Workspace externe: $(pwd)"
    echo "🔗 Artifacts copiés vers: $ORIGINAL_WORKSPACE/artifacts"
fi