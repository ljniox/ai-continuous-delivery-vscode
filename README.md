# AI Continuous Delivery System

An autonomous continuous delivery system that uses AI agents to plan, develop, test, and deploy code based on natural language specifications received via email or API.

## 🚀 System Status: FULLY OPERATIONAL

- **Python Tests**: 3/3 ✅
- **Playwright E2E**: 2/2 ✅  
- **Database Operations**: Working ✅
- **Gmail Push Integration**: Implemented ✅
- **Complete Documentation**: Available ✅

## 📧 Email-Triggered Workflows

Send project specifications via email and watch the system automatically:

1. **📥 Receive** - Gmail Push API monitors inbox for specs
2. **🧠 Plan** - Claude Code analyzes requirements with Archon MCP
3. **💻 Code** - Generates implementation with proper architecture
4. **🧪 Test** - Runs comprehensive testing (unit + E2E)
5. **✅ Validate** - Checks Definition of Done criteria
6. **📊 Report** - Sends completion notification

## ⚡ Quick Start

### For Email Triggers
```bash
# Set up Gmail Push notifications
./scripts/setup-gmail-push.sh
python3 scripts/gmail-oauth-setup.py

# Deploy Supabase Edge Function
supabase functions deploy gmail-webhook

# Send email with YAML spec attachment to monitored Gmail account
```

### For API Triggers
```bash
# Trigger workflow directly via GitHub API
curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/ljniox/ai-continuous-delivery/actions/workflows/sprint.yml/dispatches \
  -d '{"ref":"main"}'
```

## 🏗️ Architecture

```
📧 Gmail → ☁️ Google Cloud Pub/Sub → ⚡ Supabase Edge Function → 🔄 GitHub Actions
                                                                          ↓
🤖 Claude Code + 🎯 Archon MCP ← 🐍 Python Tests + 🎭 Playwright E2E ← 🔧 Self-Hosted Runner
                ↓                                    ↓
📊 Database + 📁 Artifacts ← ✅ DoD Validation ← 📈 Reports & Metrics
```

## 🛠️ Key Components

- **Archon MCP**: Model Context Protocol server for AI agent communication
- **Claude Code**: AI planning and development agent with subscription auth
- **Supabase Projects**: A (Archon data) + B (Control-plane with Edge Functions)
- **GitHub Actions**: Self-hosted ARM64 runner for consistent execution
- **Gmail Integration**: Real-time email monitoring with OAuth 2.0
- **Testing Stack**: pytest (Python) + Playwright (E2E) with comprehensive reporting

## 📚 Documentation

- **[Architecture](./docs/architecture/)** - System design and component diagrams
- **[Setup Guides](./docs/setup/)** - Installation, Gmail Push, and troubleshooting
- **[Schemas](./docs/schemas/)** - Database design and API contracts
- **[Workflows](./docs/workflows/)** - GitHub Actions and pipeline details
- **[Session Memory](./CLAUDE.md)** - Complete implementation history

## 🧪 Testing

```bash
# Test Python components
python -m pytest -v

# Test E2E components  
npx playwright test

# Test Gmail integration
python3 test-gmail-integration.py
```

## 🔐 Security Features

- **OAuth 2.0** - Secure Gmail API access with refresh tokens
- **Row Level Security** - Database access control with RLS policies
- **Signed URLs** - Temporary access to specifications and artifacts
- **Service Authentication** - Separate keys for different components

## Configuration

### GitHub Secrets
- `SUPABASE_B_URL` - Control-plane Supabase project URL
- `SUPABASE_B_SERVICE_ROLE` - Service role key for database access

### Supabase Edge Functions Environment
- `GMAIL_CLIENT_ID` - OAuth 2.0 client ID for Gmail API
- `GMAIL_CLIENT_SECRET` - OAuth 2.0 client secret
- `GMAIL_REFRESH_TOKEN` - OAuth 2.0 refresh token
- `GITHUB_TOKEN` - GitHub personal access token for workflow triggering

---

**Latest Update**: August 28, 2025 - Gmail Push Integration Complete  
**System Version**: 2.0 - Full Email-to-Deployment Pipeline  
**Powered by**: Claude Code (Sonnet 4) + Archon MCP