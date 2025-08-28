# Deployment Guide

## Prerequisites

### Required Infrastructure
- **VPS**: Ubuntu 22.04+ (ARM64 recommended)
- **Docker**: For Archon MCP containerization
- **GitHub Repository**: For code hosting and Actions
- **Supabase Projects**: Two projects (A for Archon, B for Control-plane)

### Required Services
- **Archon MCP**: Running on ports 8181 (API) and 8051 (MCP)
- **Claude Code**: Subscription with authentication configured
- **Email Service**: Gmail with Push notifications (optional)

## Step-by-Step Setup

### 1. Supabase Configuration

#### Project A (Archon Data)
- Create project for Archon MCP data storage
- Configure authentication and API keys

#### Project B (Control-Plane)
```bash
# Deploy schema
cd supabase-b/
supabase db push

# Deploy Edge Functions
supabase functions deploy notify_report
supabase functions deploy spec_ingestion
```

### 2. GitHub Actions Runner Setup

#### Install Runner on VPS
```bash
# Download ARM64 runner (adjust version as needed)
mkdir actions-runner && cd actions-runner
curl -o actions-runner-linux-arm64.tar.gz \
  -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-arm64.tar.gz
tar xzf actions-runner-linux-arm64.tar.gz

# Configure runner
./config.sh --url https://github.com/YOUR_ORG/ai-continuous-delivery --token $GITHUB_TOKEN

# Install as service
sudo ./svc.sh install
sudo ./svc.sh start
```

#### Verify Runner
```bash
# Check runner status
sudo ./svc.sh status

# Verify in GitHub repository settings
```

### 3. Environment Secrets

Configure the following secrets in GitHub repository settings:

```bash
# Supabase B (Control-Plane)
SUPABASE_B_URL=https://your-project.supabase.co
SUPABASE_B_SERVICE_ROLE=your-service-role-key

# Optional: Email integration
GMAIL_CLIENT_ID=your-gmail-client-id
GMAIL_CLIENT_SECRET=your-gmail-client-secret
```

### 4. Repository Setup

```bash
# Clone repository
git clone https://github.com/YOUR_ORG/ai-continuous-delivery.git
cd ai-continuous-delivery

# Install dependencies
pip install -r requirements.txt
npm install
npx playwright install --with-deps

# Verify tests work
python -m pytest -v
npx playwright test
```

### 5. Claude Code Configuration

```bash
# Login to Claude Code (if not already done)
claude login

# Verify authentication
claude auth status

# Test MCP connection
claude mcp connect http://localhost:8051
```

### 6. Archon MCP Verification

```bash
# Check Archon services
curl http://localhost:8181/health
curl http://localhost:8051/health

# Verify Docker containers
docker ps | grep archon
```

## Configuration Files

### Key Configuration Files

| File | Purpose |
|------|---------|
| `.github/workflows/sprint.yml` | Main CI/CD pipeline |
| `playwright.config.js` | E2E test configuration |
| `requirements.txt` | Python dependencies |
| `package.json` | Node.js dependencies |
| `supabase-b/schema.sql` | Database schema |

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `SUPABASE_URL` | Control-plane Supabase URL | Yes |
| `SUPABASE_SERVICE_KEY` | Service role key | Yes |
| `ARCHON_URL` | Archon API endpoint | Yes |
| `ARCHON_MCP_URL` | Archon MCP endpoint | Yes |
| `SPEC_SIGNED_URL` | Specification file URL | Optional |
| `SPEC_ID` | Specification identifier | Optional |

## Testing the Setup

### Manual Workflow Trigger
```bash
# Trigger workflow via API
curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/YOUR_ORG/ai-continuous-delivery/actions/workflows/sprint.yml/dispatches \
  -d '{"ref":"main"}'
```

### Local Testing
```bash
# Test Python components
python -m pytest -v

# Test E2E components
npx playwright test

# Test database operations (requires env vars)
python ops/create_run_record.py
```

### Verification Checklist

- [ ] Archon MCP responding on ports 8181/8051
- [ ] GitHub Actions runner online and labeled
- [ ] Supabase projects deployed with correct schemas
- [ ] Claude Code authenticated and connected
- [ ] All dependencies installed
- [ ] Test suite passing (Python + Playwright)
- [ ] Workflow can be triggered manually
- [ ] Artifacts generated and uploaded

## Post-Deployment

### Monitoring
- Monitor workflow runs in GitHub Actions
- Check run status in Supabase dashboard
- Review artifacts in storage buckets

### Maintenance
- Update dependencies regularly
- Monitor runner disk space and performance
- Review and clean old artifacts periodically
- Update Archon MCP as needed

### Scaling
- Add additional GitHub Actions runners as needed
- Implement load balancing for Archon MCP
- Configure Supabase autoscaling for high loads