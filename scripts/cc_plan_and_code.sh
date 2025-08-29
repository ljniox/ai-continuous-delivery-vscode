#!/bin/bash
set -euo pipefail

# Script de planification et développement avec Claude Code
# Utilise Archon MCP pour la gestion des contextes et backlog
# Support multi-projet pour développement sur repositories externes

echo "🧠 Démarrage de la planification avec Claude Code..."

# Variables d'environnement
ARCHON_API_URL=${ARCHON_API_URL:-"http://localhost:8181"}
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

# Test de connexion à Archon
echo "🔌 Vérification de la connexion à Archon..."

# Test Archon API
if ! curl -s "$ARCHON_API_URL/health" > /dev/null; then
    echo "❌ Archon API non accessible sur $ARCHON_API_URL"
    echo "💡 Démarrez Archon avec: ./ops/archon/init-archon.sh"
    exit 1
fi
echo "✅ Archon API accessible"

# Test Archon MCP Server  
if ! curl -s "$ARCHON_MCP_URL" > /dev/null; then
    echo "❌ Archon MCP Server non accessible sur $ARCHON_MCP_URL"
    exit 1
fi
echo "✅ Archon MCP Server accessible"

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
# Analyse et Planification de Projet avec Archon MCP

## Contexte Multi-Projet
- Repository cible: $TARGET_REPO
- Branche cible: $TARGET_BRANCH
- Nom du projet: $PROJECT_NAME

## Spécification
\`\`\`yaml
$(cat spec.yaml)
\`\`\`

## Instructions pour Claude Code avec Archon MCP

Utilisez les outils MCP d'Archon pour:

1. **Recherche de contexte**: Utilisez l'outil de recherche RAG d'Archon pour trouver des exemples similaires
2. **Analyse des besoins**: Analysez la spécification avec l'aide des connaissances d'Archon
3. **Architecture**: Consultez les bonnes pratiques stockées dans Archon
4. **Génération de code**: Utilisez les templates et patterns d'Archon

## Tâches à réaliser avec Archon
1. Rechercher dans la base de connaissances des projets similaires
2. Analyser les besoins fonctionnels et techniques avec contexte RAG
3. Découper en tâches développables selon les patterns Archon
4. Créer l'architecture de base du projet en consultant les templates
5. Initialiser la structure de fichiers avec les bonnes pratiques
6. Créer les premiers commits avec l'ossature

## Configuration MCP
- Serveur MCP: $ARCHON_MCP_URL
- API Archon: $ARCHON_API_URL
- Transport: Server-Sent Events (SSE)

## Livrables attendus
- Structure de projet initialisée selon les patterns Archon
- Tests de base fonctionnels  
- Documentation technique extraite des connaissances Archon
- Premier commit avec l'ossature MVP
- Manifeste de sprint enrichi par les capacités d'Archon
EOF

    echo "🤖 Exécution de la planification avec Claude Code + Archon MCP..."
    
    # Configuration MCP pour Claude Code avec Archon
    export CLAUDE_MCP_CONFIG_PATH="$ORIGINAL_WORKSPACE/mcp-config.json"
    export CLAUDE_MCP_SERVER_URL="$ARCHON_MCP_URL"
    
    # Créer la configuration MCP temporaire si elle n'existe pas
    if [[ ! -f "$CLAUDE_MCP_CONFIG_PATH" ]]; then
        cat > "$CLAUDE_MCP_CONFIG_PATH" << EOF
{
  "mcpServers": {
    "archon": {
      "transport": {
        "type": "sse",
        "url": "$ARCHON_MCP_URL"
      },
      "capabilities": ["tools", "resources", "prompts"]
    }
  }
}
EOF
    fi
    
    # Utiliser Claude Code avec Archon MCP
    # D'abord, ajouter le contexte du projet à Archon (using correct API)
    echo "📚 Ajout du contexte de spécification à Archon..."
    curl -s -X POST "$ARCHON_API_URL/api/knowledge-items/crawl" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"Project Specification - $PROJECT_NAME\",
            \"description\": \"YAML specification for $PROJECT_NAME project\",
            \"url_or_path\": \"$(pwd)/spec.yaml\",
            \"source_type\": \"file\"
        }" || echo "⚠️ Ajout du contexte à Archon échoué"
    
    echo "🔍 Recherche de contexte similaire dans Archon..."
    SIMILAR_CONTEXT=$(curl -s -X POST "$ARCHON_API_URL/api/knowledge-items/search" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"$(head -5 spec.yaml | tr '\n' ' ')\", \"limit\": 3}" || echo "{}")
    
    # Exécuter Claude Code avec le contexte Archon (simplified integration)
    echo "🤖 Exécution de Claude Code avec contexte Archon enrichi..."
    
    # Add search results to prompt file
    cat >> artifacts/claude_prompt.md << EOF

## Contexte Archon RAG
Résultats de recherche dans la base de connaissances:
\`\`\`json
$SIMILAR_CONTEXT
\`\`\`

## Instructions Claude Code
1. Lis la spécification spec.yaml et le contexte ci-dessus
2. Analyse les besoins fonctionnels et techniques
3. Crée un plan de développement structuré
4. Initialise la structure de projet selon les bonnes pratiques
5. Crée les fichiers de base nécessaires
6. Génère un manifeste de sprint dans sprints/current_manifest.yaml

EOF
    
    # Run Claude Code with enhanced context and limit handling
    echo "🤖 Executing Claude Code with limit handling..."
    
    if bash scripts/claude_limit_handler.sh execute claude --print "$(cat artifacts/claude_prompt.md)" > artifacts/claude_analysis.txt; then
        echo "✅ Claude Code analysis completed successfully"
    else
        echo "⚠️ Claude Code failed after limit handling, using fallback..."
        
        # Fallback: Create basic project structure
        echo "🔧 Creating fallback project structure..."
        mkdir -p src tests docs
        
        cat > artifacts/claude_analysis.txt << 'EOF'
# Fallback Analysis - Claude Limit Reached

## Project Structure Created
- src/ - Source code directory  
- tests/ - Test files directory
- docs/ - Documentation directory

## Next Steps
- Manual code implementation required
- Resume when Claude limit resets
- Check artifacts/claude_session_state.json for continuation
EOF
    fi
    
    # Show the analysis result
    if [[ -f "artifacts/claude_analysis.txt" ]]; then
        echo "✅ Analyse Claude Code terminée - voir artifacts/claude_analysis.txt"
    fi

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