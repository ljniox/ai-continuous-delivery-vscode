# Troubleshooting Guide

## Common Issues and Solutions

### GitHub Actions Runner Issues

#### Runner Not Appearing in GitHub
**Symptoms**: Runner doesn't show up in repository settings

**Solutions**:
```bash
# Check runner status
sudo systemctl status actions.runner.ljniox-ai-continuous-delivery.ljniox-ai-continuous-delivery.service

# Restart runner service
sudo ./svc.sh stop
sudo ./svc.sh start

# Re-configure if token expired
./config.sh remove
./config.sh --url https://github.com/ljniox/ai-continuous-delivery --token $NEW_TOKEN
```

#### Architecture Mismatch
**Symptoms**: `Unsupported architecture` error

**Solutions**:
```bash
# Verify system architecture
uname -m  # Should return 'aarch64' for ARM64

# Download correct runner binary
curl -o actions-runner-linux-arm64.tar.gz \
  -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-arm64.tar.gz

# Update workflow labels
runs-on: [self-hosted, Linux, ARM64]
```

### Dependency Issues

#### Module Not Found Errors
**Symptoms**: `ModuleNotFoundError: No module named 'supabase'`

**Solutions**:
```bash
# Install missing Python dependencies
pip install -r requirements.txt

# For specific modules
pip install supabase
pip install 'websockets>=12.0'

# Verify installation
python -c "import supabase; print('OK')"
```

#### Node.js Dependencies
**Symptoms**: Playwright or npm errors

**Solutions**:
```bash
# Clean install
rm -rf node_modules package-lock.json
npm install

# Playwright browser installation
npx playwright install --with-deps

# Verify Playwright
npx playwright test --reporter=list
```

### Playwright Issues

#### JSON Reporter Error
**Symptoms**: `Error: Cannot resolve module './lib/json'`

**Solutions**:
```javascript
// Remove JSON reporter from playwright.config.js
reporter: [
  ['html', { outputFolder: 'artifacts/playwright-report' }],
  ['junit', { outputFile: 'artifacts/playwright-junit.xml' }]
  // Remove: ['json', { outputFile: 'artifacts/playwright-results.json' }]
],
```

#### UTF-8 Encoding Issues
**Symptoms**: Character encoding errors in tests

**Solutions**:
```javascript
// Use proper server instead of data URLs
const appUrl = process.env.APP_URL || 'http://localhost:8000';
await page.goto(appUrl);

// Ensure HTML files have proper charset
<meta charset="UTF-8">
```

#### WebServer Configuration
**Symptoms**: `Process from config.webServer exited early`

**Solutions**:
```javascript
// Use external URL to bypass local server
webServer: process.env.APP_URL ? undefined : {
  command: 'echo "No local server needed - using external APP_URL"',
  port: 8000,
  reuseExistingServer: true,
},
```

### Database Issues

#### Connection Errors
**Symptoms**: Supabase connection failures

**Solutions**:
```bash
# Verify environment variables
echo $SUPABASE_URL
echo $SUPABASE_SERVICE_KEY

# Test connection
curl -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
     "$SUPABASE_URL/rest/v1/specs"

# Check database schema
supabase db diff
```

#### RLS Policy Errors
**Symptoms**: Permission denied on table access

**Solutions**:
```sql
-- Check existing policies
SELECT * FROM pg_policies WHERE tablename = 'specs';

-- Re-apply RLS policies
DROP POLICY IF EXISTS "policy_name" ON table_name;
CREATE POLICY "new_policy_name" ON table_name FOR operation USING (condition);
```

### Claude Code Issues

#### Authentication Problems
**Symptoms**: API authentication errors

**Solutions**:
```bash
# Re-authenticate
claude logout
claude login

# Verify session
claude auth status

# Check MCP connection
claude mcp list
```

#### MCP Connection Issues
**Symptoms**: Cannot connect to Archon MCP

**Solutions**:
```bash
# Verify Archon services
curl http://localhost:8181/health
curl http://localhost:8051/health

# Check Docker containers
docker ps | grep archon
docker logs archon-container

# Restart if needed
docker restart archon-container
```

### Workflow Execution Issues

#### Missing Secrets
**Symptoms**: Environment variable errors in workflow

**Solutions**:
1. Go to GitHub repository Settings > Secrets and variables > Actions
2. Add required secrets:
   - `SUPABASE_B_URL`
   - `SUPABASE_B_SERVICE_ROLE`
3. Verify secret names match workflow file

#### Timeout Issues
**Symptoms**: Workflow times out after 60 minutes

**Solutions**:
```yaml
# Increase timeout if needed
timeout-minutes: 120

# Or optimize performance
# - Use npm ci instead of npm install
# - Cache dependencies between runs
# - Parallelize test execution
```

## Diagnostic Commands

### System Health Check
```bash
# Check all services
curl http://localhost:8181/health  # Archon API
curl http://localhost:8051/health  # Archon MCP
sudo systemctl status actions.runner.*  # GitHub runner

# Check dependencies
python -c "import supabase, pytest; print('Python OK')"
npx playwright --version

# Test database connection
python -c "
import os
from supabase import create_client
client = create_client(os.getenv('SUPABASE_URL'), os.getenv('SUPABASE_SERVICE_KEY'))
print('DB OK')
"
```

### Log Analysis
```bash
# GitHub Actions runner logs
journalctl -u actions.runner.* -f

# Workflow execution logs
# Available in GitHub Actions web interface

# System logs
tail -f /var/log/syslog | grep -E "(docker|actions-runner)"
```

### Performance Monitoring
```bash
# System resources
htop
df -h
docker stats

# Network connectivity
ping github.com
curl -I https://api.github.com
```

## Recovery Procedures

### Runner Recovery
```bash
# Complete runner reset
sudo ./svc.sh stop
sudo ./svc.sh uninstall
./config.sh remove

# Re-install
./config.sh --url https://github.com/ljniox/ai-continuous-delivery --token $NEW_TOKEN
sudo ./svc.sh install
sudo ./svc.sh start
```

### Database Recovery
```bash
# Reset database (CAUTION: destroys data)
supabase db reset

# Re-apply schema
supabase db push
```

### Clean Slate Setup
```bash
# Complete environment reset
rm -rf actions-runner/
rm -rf node_modules/
pip uninstall -y supabase pytest playwright

# Start fresh installation
# Follow deployment guide from step 1
```