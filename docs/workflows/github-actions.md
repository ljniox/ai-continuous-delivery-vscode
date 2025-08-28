# GitHub Actions Pipeline Documentation

## Sprint Runner Workflow

The main workflow (`.github/workflows/sprint.yml`) implements the complete AI continuous delivery pipeline.

### Trigger Events

```yaml
on:
  repository_dispatch:
    types: [spec_ingested]      # External API trigger
  workflow_dispatch:
    inputs:
      spec_url:                 # Manual trigger with spec URL
        description: 'URL signée vers la spec YAML'
        required: false
        type: string
```

### Environment Configuration

```yaml
env:
  # Supabase B (Control-Plane)
  SUPABASE_URL: ${{ secrets.SUPABASE_B_URL }}
  SUPABASE_SERVICE_KEY: ${{ secrets.SUPABASE_B_SERVICE_ROLE }}
  
  # Archon (MCP sur VPS)
  ARCHON_URL: http://localhost:8181
  ARCHON_MCP_URL: http://localhost:8051
  
  # Spec processing
  SPEC_SIGNED_URL: ${{ github.event.client_payload.spec_url || inputs.spec_url }}
  SPEC_ID: ${{ github.event.client_payload.spec_id }}
```

### Pipeline Stages

#### 1. Environment Setup
```yaml
- name: Setup Python & Node
  uses: actions/setup-python@v5
  with: 
    python-version: "3.11"

- uses: actions/setup-node@v4
  with: 
    node-version: "20"

- name: Install dependencies
  run: |
    sudo apt-get update
    sudo apt-get install -y jq
    python -m pip install --upgrade pip
    pip install -r requirements.txt
    npm install
    npx playwright install --with-deps
```

#### 2. Service Validation
```yaml
- name: Start Archon (Docker)
  run: |
    # Verify Archon services are accessible
    if ! curl -s http://localhost:8181 > /dev/null; then
      echo "❌ Archon API non accessible"
      exit 1
    fi
    if ! curl -s http://localhost:8051 > /dev/null; then
      echo "❌ Archon MCP non accessible"  
      exit 1
    fi
    echo "✅ Archon opérationnel"
```

#### 3. Specification Processing
```yaml
- name: Fetch or create specification
  run: |
    if [ -n "$SPEC_SIGNED_URL" ]; then
      curl -L "$SPEC_SIGNED_URL" -o spec.yaml
    else
      # Create default test specification
      cat > spec.yaml << 'EOF'
      # Default test spec content...
      EOF
    fi
```

#### 4. Planning & Development
```yaml
- name: Claude Code — Planification & développement
  env:
    RUN_ID: ${{ steps.create_run.outputs.run_id }}
  run: bash scripts/cc_plan_and_code.sh
```

#### 5. Testing & Validation
```yaml
- name: Tests et validation
  env:
    RUN_ID: ${{ steps.create_run.outputs.run_id }}
  run: bash scripts/qwen_run_tests.sh
```

#### 6. Artifact Management
```yaml
- name: Upload artifacts to Supabase B
  env:
    RUN_ID: ${{ steps.create_run.outputs.run_id }}
  run: python ops/upload_artifacts.py
```

#### 7. Definition of Done Validation
```yaml
- name: DoD Gate — Validation finale
  env:
    RUN_ID: ${{ steps.create_run.outputs.run_id }}
  run: python ops/dod_gate.py
```

#### 8. Notification
```yaml
- name: Send notification report
  if: always()
  env:
    RUN_ID: ${{ steps.create_run.outputs.run_id }}
  run: |
    curl -X POST "$SUPABASE_URL/functions/v1/notify_report" \
         -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
         -H "Content-Type: application/json" \
         -d @artifacts/summary.json
```

## Script Components

### `cc_plan_and_code.sh`
Claude Code planning and development script:
- Downloads and analyzes specifications
- Connects to Archon MCP for context
- Generates project structure and code
- Creates feature branches and commits

### `qwen_run_tests.sh` 
Testing and validation script:
- Runs Python unit tests with coverage
- Executes Playwright E2E tests
- Generates test reports and artifacts
- Creates summary JSON for DoD validation

### `ops/create_run_record.py`
Database initialization script:
- Creates or retrieves specification records
- Initializes sprint and run tracking
- Sets up GitHub Actions output variables

### `ops/upload_artifacts.py`
Artifact management script:
- Uploads test reports to Supabase storage
- Creates artifact metadata records
- Generates signed URLs for access

### `ops/dod_gate.py`
Definition of Done validation script:
- Parses test results and coverage data
- Validates against DoD criteria
- Updates run status and sprint state

## Runner Configuration

### Self-Hosted ARM64 Runner
```yaml
runs-on: [self-hosted, Linux, ARM64]
timeout-minutes: 60
```

### Installation
```bash
# Download ARM64 runner
curl -o actions-runner-linux-arm64.tar.gz \
  -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-arm64.tar.gz

# Configure and start
./config.sh --url https://github.com/ljniox/ai-continuous-delivery --token $GITHUB_TOKEN
sudo ./svc.sh install && sudo ./svc.sh start
```

## Monitoring

### Workflow Status
- GitHub Actions provides built-in monitoring
- Custom status events logged to database
- Real-time progress tracking via status_events table

### Artifacts
- Test reports: HTML and JUnit formats
- Coverage reports: JSON and HTML
- Screenshots/videos: Playwright test artifacts
- Logs: Complete execution logs