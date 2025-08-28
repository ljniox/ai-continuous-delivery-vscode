# System Memory & Configuration Reference

## Complete Setup History

### Infrastructure Foundation
- **VPS**: swfs.niox.ovh (Ubuntu 22.04, ARM64, Docker pre-installed)
- **Archon MCP**: Pre-existing, running on ports 8181 (API) + 8051 (MCP)
- **Supabase A**: Pre-existing project for Archon data storage
- **Supabase B**: Created specifically for AI CD control-plane

### Implementation Timeline

#### Phase 1: Database Schema (Completed)
- Created complete PostgreSQL schema in `supabase-b/schema.sql`
- Tables: specs, sprints, runs, artifacts, status_events
- Implemented Row Level Security (RLS) policies
- Created indexes for performance

#### Phase 2: GitHub Actions Setup (Completed)
- Downloaded ARM64 GitHub Actions runner
- Configured service: `actions.runner.ljniox-ai-continuous-delivery.ljniox-ai-continuous-delivery.service`
- Created workflow: `.github/workflows/sprint.yml`
- Set up repository secrets for Supabase B access

#### Phase 3: Claude Code Integration (Completed)
- Created `scripts/cc_plan_and_code.sh` for planning
- Configured MCP connection to Archon
- Implemented subscription-based authentication
- Added specification processing and code generation

#### Phase 4: Testing Framework (Completed)
- Configured pytest for Python unit testing
- Set up Playwright for E2E testing
- Created test files: `tests/test_basic.py`, `e2e/basic.spec.js`
- Fixed UTF-8 encoding issues and JSON reporter problems

#### Phase 5: Operations Scripts (Completed)
- `ops/create_run_record.py`: Database run initialization
- `ops/upload_artifacts.py`: Artifact management
- `ops/dod_gate.py`: Definition of Done validation
- `scripts/qwen_run_tests.sh`: Test execution script

### Current Configuration

#### Environment Variables (GitHub Secrets)
```bash
SUPABASE_B_URL=https://gqxfqyunslnqmggztrfd.supabase.co
SUPABASE_B_SERVICE_ROLE=[service-role-key]
```

#### Key File Locations
```
/home/ubuntu/ai-continuous-delivery/
├── .github/workflows/sprint.yml          # Main CI/CD pipeline
├── supabase-b/schema.sql                 # Database schema
├── scripts/
│   ├── cc_plan_and_code.sh               # Claude Code planning
│   └── qwen_run_tests.sh                 # Test execution
├── ops/
│   ├── create_run_record.py              # Run initialization
│   ├── upload_artifacts.py               # Artifact management
│   └── dod_gate.py                       # DoD validation
├── tests/test_basic.py                   # Python unit tests
├── e2e/basic.spec.js                     # Playwright E2E tests
├── playwright.config.js                 # Playwright configuration
├── requirements.txt                      # Python dependencies
├── package.json                          # Node.js dependencies
└── public/index.html                     # Test application
```

#### Runner Configuration
- **Location**: `/opt/actions-runner/`
- **Service**: Systemd service running as ubuntu user
- **Architecture**: ARM64 (aarch64)
- **Labels**: `[self-hosted, Linux, ARM64]`

#### Dependency Versions
- **Python**: 3.11+ (system has 3.10.12)
- **Node.js**: 20
- **Playwright**: Latest with browser dependencies
- **Supabase**: 2.18.1 with websockets 15.0.1
- **pytest**: 7.4.0 with coverage support

### Critical Fixes Applied

#### 1. Architecture Compatibility
- **Issue**: x64 runner binary on ARM64 system
- **Solution**: Downloaded ARM64 runner, updated workflow labels

#### 2. Authentication Method
- **Issue**: z.ai API insufficient balance
- **Solution**: Switched to Claude Code subscription authentication

#### 3. Missing Dependencies
- **Issue**: Various module not found errors
- **Solution**: Added jq, updated requirements.txt, installed Playwright browsers

#### 4. Playwright Configuration
- **Issue**: JSON reporter module resolution error
- **Solution**: Removed JSON reporter, kept HTML and JUnit

#### 5. UTF-8 Encoding
- **Issue**: Character encoding in E2E tests
- **Solution**: Created proper test server with UTF-8 HTML

#### 6. Websockets Compatibility
- **Issue**: Supabase client websockets version mismatch
- **Solution**: Upgraded to websockets>=12.0

### Test Results Status

#### Python Tests: ✅ PASSING
```bash
$ python -m pytest -v
============================= test session starts ==============================
collected 3 items

tests/test_basic.py::test_basic PASSED                                   [ 33%]
tests/test_basic.py::test_imports PASSED                                 [ 66%]
tests/test_basic.py::test_python_version PASSED                          [100%]

============================== 3 passed in 0.02s ===============================
```

#### Playwright E2E Tests: ✅ PASSING
```bash
$ npx playwright test --reporter=list
Running 2 tests using 1 worker

  ✓ [chromium] › e2e/basic.spec.js:4:3 › Tests E2E basiques › page d'accueil accessible (567ms)
  ✓ [chromium] › e2e/basic.spec.js:24:3 › Tests E2E basiques › test de fonctionnalité basique (439ms)

  2 passed (2.7s)
```

### Monitoring Endpoints

#### Service Health Checks
- **Archon API**: `http://localhost:8181/health`
- **Archon MCP**: `http://localhost:8051/health`
- **Test App**: `http://localhost:8000` (when running)

#### Database Queries
```sql
-- Check recent runs
SELECT r.*, s.label, sp.repo 
FROM runs r 
JOIN sprints s ON r.sprint_id = s.id 
JOIN specs sp ON s.spec_id = sp.id 
ORDER BY r.started_at DESC LIMIT 10;

-- Check system status
SELECT phase, count(*) 
FROM status_events 
WHERE created_at > now() - interval '1 day' 
GROUP BY phase;
```

### Backup and Recovery

#### Critical Data
- **Database**: Automatic Supabase backups
- **Runner Configuration**: `/opt/actions-runner/` directory
- **Secrets**: GitHub repository secrets (manual backup required)
- **Source Code**: Git repository (GitHub)

#### Recovery Commands
```bash
# Backup runner config
sudo tar -czf actions-runner-backup.tar.gz /opt/actions-runner/

# Restore runner config
sudo tar -xzf actions-runner-backup.tar.gz -C /

# Database restore (via Supabase dashboard)
# Source code restore (git clone)
```

## Maintenance Schedule

### Daily
- Check runner status
- Monitor workflow executions
- Review failed runs

### Weekly  
- Update dependencies
- Review disk space usage
- Check artifact cleanup

### Monthly
- Update Archon MCP
- Review and optimize database performance
- Update GitHub Actions runner version
- Security updates and patches