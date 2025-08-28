# AI Continuous Delivery

Système de livraison continue automatisée avec IA utilisant Claude Code, Qwen3-Coder, et Archon MCP.

## Architecture

- **Archon MCP** : Serveur de contexte et gestion des projets
- **Supabase A** : Base de données Archon (contextes, backlog)
- **Supabase B** : Plan de contrôle (specs, sprints, runs, artefacts)
- **Claude Code** : Planification et développement
- **Qwen3-Coder** : Exécution des tests et validation
- **GitHub Actions** : Orchestration CI/CD avec runner self-hosted

## Déploiement

### 1. Configuration VPS
```bash
./setup-vps.sh
claude login
```

### 2. GitHub Actions Runner
```bash
cd /opt/actions-runner
./config.sh --url https://github.com/ljniox/ai-continuous-delivery --token YOUR_TOKEN
sudo systemctl enable github-runner
sudo systemctl start github-runner
```

## Workflow

1. **Email** → Supabase Edge Function
2. **GitHub Actions** déclenché
3. **Planification** avec Claude Code + Archon MCP
4. **Tests** avec Qwen3-Coder
5. **Validation DoD** et merge automatique
6. **Notification** par email avec artefacts

## Configuration requise

### GitHub Secrets
- `SUPABASE_B_URL`
- `SUPABASE_B_SERVICE_ROLE` 
- `DASHSCOPE_API_KEY`

### Variables Supabase Edge Functions
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `GITHUB_TOKEN`
- `TARGET_REPO=ljniox/ai-continuous-delivery`