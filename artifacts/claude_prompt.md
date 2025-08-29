# Analyse et Planification de Projet avec Archon MCP

## Contexte Multi-Projet
- Repository cible: ljniox/ai-continuous-delivery
- Branche cible: main
- Nom du projet: ljniox/ai-continuous-delivery

## Spécification
```yaml
meta:
  project: archon-integration-test
  repo: ljniox/ai-continuous-delivery
  requester_email: test@example.com
planning:
  epics:
    - id: E1
      title: Test Archon Integration
      sprints:
        - id: S1
          goals: ["Validate Archon + Claude Code integration"]
          user_stories:
            - id: US1
              as: developer
              want: to validate archon integration
              so_that: the system works properly
              acceptance:
                - "Integration test passes"
runtime:
  stack:
    backend: "Python 3.11"
tests:
  unit: "pytest"
```

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
- Serveur MCP: http://localhost:8051
- API Archon: http://localhost:8181
- Transport: Server-Sent Events (SSE)

## Livrables attendus
- Structure de projet initialisée selon les patterns Archon
- Tests de base fonctionnels  
- Documentation technique extraite des connaissances Archon
- Premier commit avec l'ossature MVP
- Manifeste de sprint enrichi par les capacités d'Archon

## Contexte Archon RAG
Résultats de recherche dans la base de connaissances:
```json
{"results":[],"query":"meta:   project: archon-integration-test   repo: ljniox/ai-continuous-delivery   requester_email: test@example.com planning: ","source":null,"match_count":5,"total_found":0,"execution_path":"rag_service_pipeline","search_mode":"hybrid","reranking_applied":false,"success":true}
```

## Instructions Claude Code
1. Lis la spécification spec.yaml et le contexte ci-dessus
2. Analyse les besoins fonctionnels et techniques
3. Crée un plan de développement structuré
4. Initialise la structure de projet selon les bonnes pratiques
5. Crée les fichiers de base nécessaires
6. Génère un manifeste de sprint dans sprints/current_manifest.yaml

