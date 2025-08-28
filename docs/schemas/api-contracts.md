# API Contracts and Interfaces

## Workflow Trigger API

### Repository Dispatch Event
Triggers the sprint workflow via GitHub API.

```http
POST /repos/{owner}/{repo}/dispatches
Authorization: token {github_token}
Content-Type: application/json

{
  "event_type": "spec_ingested",
  "client_payload": {
    "spec_url": "https://signed-url-to-spec.yaml",
    "spec_id": "uuid-of-specification"
  }
}
```

### Workflow Dispatch Event
Manual workflow trigger with parameters.

```http
POST /repos/{owner}/{repo}/actions/workflows/sprint.yml/dispatches
Authorization: token {github_token}
Content-Type: application/json

{
  "ref": "main",
  "inputs": {
    "spec_url": "https://signed-url-to-spec.yaml"
  }
}
```

## Supabase Edge Functions

### Notification Report
Sends completion reports via email or webhook.

```http
POST /functions/v1/notify_report
Authorization: Bearer {supabase_service_key}
Content-Type: application/json

{
  "run_id": "uuid",
  "status": "PASSED|FAILED",
  "summary": {
    "tests": {
      "python": {"passed": 3, "failed": 0},
      "e2e": {"passed": 2, "failed": 0}
    },
    "coverage": 0.85,
    "duration_seconds": 180
  },
  "artifacts": [
    {"kind": "junit", "url": "https://signed-url"},
    {"kind": "coverage", "url": "https://signed-url"}
  ]
}
```

### Spec Ingestion
Processes incoming specifications from email.

```http
POST /functions/v1/spec_ingestion
Authorization: Bearer {supabase_service_key}
Content-Type: application/json

{
  "email_id": "gmail-message-id",
  "sender": "user@example.com",
  "subject": "Project Specification",
  "attachments": [
    {
      "filename": "spec.yaml",
      "content_base64": "base64-encoded-yaml"
    }
  ]
}
```

## Archon MCP Protocol

### Connection
```javascript
// Claude Code MCP connection
const connection = await mcpConnect('http://localhost:8051');
```

### Project Context Request
```json
{
  "method": "get_project_context",
  "params": {
    "repo": "ljniox/ai-continuous-delivery",
    "branch": "main"
  }
}
```

### Response Format
```json
{
  "result": {
    "files": [
      {"path": "src/main.py", "type": "source"},
      {"path": "tests/test_main.py", "type": "test"}
    ],
    "dependencies": {
      "python": ["pytest", "requests"],
      "node": ["playwright", "@types/node"]
    },
    "architecture": "microservices",
    "patterns": ["mvc", "dependency-injection"]
  }
}
```

## Database API (Supabase REST)

### Runs Query
Get run status and results.

```http
GET /rest/v1/runs?sprint_id=eq.{uuid}&order=started_at.desc
Authorization: Bearer {service_key}
```

### Status Events
Real-time status updates.

```http
POST /rest/v1/status_events
Authorization: Bearer {service_key}
Content-Type: application/json

{
  "run_id": "uuid",
  "phase": "PLANNING",
  "message": "Starting code generation",
  "metadata": {
    "agent": "claude-code",
    "mcp_connected": true
  }
}
```

### Artifacts Upload
Store test artifacts and reports.

```http
POST /rest/v1/artifacts
Authorization: Bearer {service_key}
Content-Type: application/json

{
  "run_id": "uuid",
  "kind": "junit",
  "storage_path": "artifacts/run-123/junit-results.xml",
  "size": 2048
}
```

## Specification Format

### YAML Structure
```yaml
meta:
  project: "my-awesome-app"
  repo: "user/repository"
  requester_email: "user@example.com"

planning:
  epics:
    - id: E1
      title: "User Authentication System"
      sprints:
        - id: S1
          goals: ["Implement login", "Add user registration"]
          user_stories:
            - id: US1
              as: "user"
              want: "to log in securely"
              so_that: "I can access my account"
              acceptance:
                - "Login form validates credentials"
                - "JWT tokens are generated"
                - "Session management works"
          dod:
            coverage_min: 0.80
            e2e_pass: true
            lighthouse_min: 85

runtime:
  stack:
    backend: "Python 3.11 + FastAPI"
    frontend: "React + TypeScript"
    database: "PostgreSQL"

tests:
  unit: "pytest"
  e2e: "Playwright"
  performance: "Lighthouse"

policies:
  coding_standards: "Black, ESLint, TypeScript strict"
  branch: "feature/auth-*"
  review_required: true
```

## Test Report Formats

### Python Coverage Report
```json
{
  "meta": {
    "version": "7.4.0",
    "timestamp": "2025-08-28T11:30:00Z"
  },
  "totals": {
    "covered_lines": 85,
    "num_statements": 100,
    "percent_covered": 85.0
  },
  "files": {
    "src/main.py": {
      "executed_lines": [1, 2, 5, 8],
      "missing_lines": [10, 15],
      "coverage": 80.0
    }
  }
}
```

### Playwright JUnit Report
```xml
<testsuites tests="2" failures="0" time="2.836">
  <testsuite name="basic.spec.js" tests="2" failures="0" time="1.205">
    <testcase name="page d'accueil accessible" time="0.538"/>
    <testcase name="test de fonctionnalité basique" time="0.667"/>
  </testsuite>
</testsuites>
```

## Error Handling

### Standard Error Response
```json
{
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "DoD criteria not met",
    "details": {
      "coverage": {"required": 0.80, "actual": 0.65},
      "e2e_tests": {"required": "pass", "actual": "failed"},
      "failed_tests": ["test_authentication", "test_user_registration"]
    }
  }
}
```

### Status Event Error
```json
{
  "run_id": "uuid",
  "phase": "FAILED",
  "message": "Test execution failed",
  "metadata": {
    "error_type": "test_failure",
    "failed_count": 2,
    "exit_code": 1,
    "logs_path": "artifacts/run-123/execution.log"
  }
}
```