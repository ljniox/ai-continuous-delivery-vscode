#!/bin/bash

# Archon Initialization Script
# Properly sets up Archon with knowledge base and MCP server for AI Continuous Delivery

set -euo pipefail

echo "🏛️ Initialisation d'Archon pour AI Continuous Delivery..."

# Configuration variables
ARCHON_DIR=$(dirname "$(realpath "$0")")
PROJECT_ROOT=$(realpath "$ARCHON_DIR/../..")
ARCHON_API_URL=${ARCHON_API_URL:-"http://localhost:8181"}
ARCHON_MCP_URL=${ARCHON_MCP_URL:-"http://localhost:8051"}

echo "📁 Répertoires:"
echo "  Archon config: $ARCHON_DIR"
echo "  Project root: $PROJECT_ROOT"
echo "  API URL: $ARCHON_API_URL"
echo "  MCP URL: $ARCHON_MCP_URL"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker non trouvé. Installation requise."
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
    echo "❌ Docker Compose non trouvé. Installation requise."
    exit 1
fi

# Use docker compose if available, otherwise docker-compose
DOCKER_COMPOSE_CMD="docker compose"
if ! docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
fi

echo "🐳 Utilisation de: $DOCKER_COMPOSE_CMD"

# Stop any existing Archon containers
echo "🛑 Arrêt des conteneurs Archon existants..."
cd "$ARCHON_DIR"
$DOCKER_COMPOSE_CMD down --remove-orphans 2>/dev/null || echo "Aucun conteneur à arrêter"

# Create necessary directories
echo "📁 Création des répertoires de données..."
mkdir -p "$PROJECT_ROOT/data/archon/knowledge"
mkdir -p "$PROJECT_ROOT/data/archon/cache"
mkdir -p "$PROJECT_ROOT/data/archon/projects"

# Prepare environment file if it doesn't exist
ENV_FILE="$ARCHON_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "⚙️ Création du fichier d'environnement..."
    cat > "$ENV_FILE" << EOF
# Supabase Configuration (Project A - Archon data storage)
SUPABASE_A_URL=${SUPABASE_A_URL:-https://your-archon-project.supabase.co}
SUPABASE_A_SERVICE_KEY=${SUPABASE_A_SERVICE_KEY:-your-service-key}

# AI Model Configuration (optional - can be configured via UI)
OPENAI_API_KEY=${OPENAI_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}

# Archon Configuration
NODE_ENV=production
MCP_SERVER_PORT=8051
MCP_TRANSPORT=sse
ENABLE_WEB_CRAWLING=true
ENABLE_VECTOR_SEARCH=true
PROJECT_NAME=AI Continuous Delivery
PROJECT_DESCRIPTION=Autonomous continuous delivery system using AI agents
EOF
    
    echo "📝 Fichier d'environnement créé: $ENV_FILE"
    echo "⚠️  IMPORTANT: Configurez vos clés API dans $ENV_FILE"
fi

# Start Archon services
echo "🚀 Démarrage des services Archon..."
$DOCKER_COMPOSE_CMD up -d

# Wait for services to be ready
echo "⏳ Attente du démarrage des services..."
sleep 10

# Health check function
check_service() {
    local url=$1
    local service_name=$2
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s -f "$url" > /dev/null 2>&1; then
            echo "✅ $service_name accessible"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo "⏳ $service_name pas encore prêt (tentative $attempt/$max_attempts)..."
        sleep 2
    done
    
    echo "❌ $service_name non accessible après $max_attempts tentatives"
    return 1
}

# Check Archon API
if ! check_service "$ARCHON_API_URL/health" "Archon API"; then
    echo "❌ Archon API non démarré. Vérification des logs..."
    $DOCKER_COMPOSE_CMD logs archon
    exit 1
fi

# Check MCP server
if ! check_service "$ARCHON_MCP_URL" "Archon MCP Server"; then
    echo "❌ Archon MCP Server non démarré. Vérification des logs..."
    $DOCKER_COMPOSE_CMD logs archon
    exit 1
fi

# Initialize project knowledge base
echo "📚 Initialisation de la base de connaissances..."
initialize_knowledge() {
    local api_url=$1
    
    # Add project documentation to knowledge base
    echo "📖 Ajout de la documentation du projet..."
    
    # Add README and key documentation files
    if [[ -f "$PROJECT_ROOT/README.md" ]]; then
        curl -s -X POST "$api_url/api/knowledge/documents" \
            -H "Content-Type: application/json" \
            -d "{
                \"title\": \"AI CD System README\",
                \"content\": $(jq -Rs . < "$PROJECT_ROOT/README.md"),
                \"type\": \"documentation\",
                \"tags\": [\"system\", \"overview\"]
            }" || echo "⚠️ Erreur lors de l'ajout du README"
    fi
    
    # Add CLAUDE.md session history
    if [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
        curl -s -X POST "$api_url/api/knowledge/documents" \
            -H "Content-Type: application/json" \
            -d "{
                \"title\": \"Claude Code Session History\",
                \"content\": $(jq -Rs . < "$PROJECT_ROOT/CLAUDE.md"),
                \"type\": \"history\",
                \"tags\": [\"claude\", \"sessions\", \"implementation\"]
            }" || echo "⚠️ Erreur lors de l'ajout de CLAUDE.md"
    fi
    
    # Add architecture documentation
    if [[ -d "$PROJECT_ROOT/docs" ]]; then
        find "$PROJECT_ROOT/docs" -name "*.md" -type f | while read -r doc_file; do
            local doc_title=$(basename "$doc_file" .md)
            curl -s -X POST "$api_url/api/knowledge/documents" \
                -H "Content-Type: application/json" \
                -d "{
                    \"title\": \"$doc_title\",
                    \"content\": $(jq -Rs . < "$doc_file"),
                    \"type\": \"documentation\",
                    \"tags\": [\"docs\", \"architecture\"]
                }" || echo "⚠️ Erreur lors de l'ajout de $doc_file"
        done
    fi
}

# Try to initialize knowledge base (may fail if API not fully ready)
initialize_knowledge "$ARCHON_API_URL" || echo "⚠️ Initialisation de la base de connaissances échouée - à refaire manuellement"

# Create MCP configuration for Claude Code
echo "🔧 Création de la configuration MCP pour Claude Code..."
MCP_CONFIG_FILE="$PROJECT_ROOT/mcp-config.json"
cat > "$MCP_CONFIG_FILE" << EOF
{
  "mcpServers": {
    "archon": {
      "command": "node",
      "args": [],
      "env": {},
      "transport": {
        "type": "sse",
        "url": "$ARCHON_MCP_URL"
      },
      "capabilities": {
        "tools": true,
        "resources": true,
        "prompts": true
      }
    }
  }
}
EOF

echo "✅ Archon initialisé avec succès!"
echo ""
echo "📋 Informations de connexion:"
echo "  🌐 Interface Web: $ARCHON_API_URL"
echo "  🔌 MCP Server: $ARCHON_MCP_URL"
echo "  📄 Configuration MCP: $MCP_CONFIG_FILE"
echo ""
echo "🔧 Prochaines étapes:"
echo "  1. Ouvrir $ARCHON_API_URL dans votre navigateur"
echo "  2. Configurer vos clés API (OpenAI/Anthropic) dans l'interface"
echo "  3. Vérifier la base de connaissances"
echo "  4. Tester la connexion MCP avec Claude Code"
echo ""
echo "📚 Documentation Archon:"
echo "  https://github.com/coleam00/Archon"
echo ""
echo "🧪 Test de connexion:"
echo "  curl $ARCHON_API_URL/health"
echo "  curl $ARCHON_MCP_URL"