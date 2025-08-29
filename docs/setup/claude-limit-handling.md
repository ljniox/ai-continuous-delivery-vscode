# Claude Code Subscription Limit Handling

Complete guide for handling Claude Code daily limits with account rotation and session continuity.

## 🎯 Problem Statement

Claude Code subscription accounts have a **5-hour daily limit**. When reached:
- Current development tasks are interrupted
- GitHub Actions workflows fail mid-execution  
- Manual intervention required to resume work

## ✅ Solution Overview

**Multi-layered approach:**
1. **Account Rotation**: Automatic switch to backup accounts
2. **Sleep/Resume**: Wait for limit reset and auto-resume
3. **Session Continuity**: Preserve context across interruptions
4. **Graceful Fallbacks**: Continue with basic operations when possible

## 🔧 Setup Instructions

### Step 1: Configure Multiple Claude Accounts

```bash
# Initialize account configuration
bash scripts/claude_limit_handler.sh init

# This creates ops/claude_accounts.json:
```

```json
{
  "accounts": [
    {
      "id": "primary",
      "auth_method": "login",
      "status": "active", 
      "description": "Primary subscription account"
    },
    {
      "id": "secondary",
      "auth_method": "token",
      "token_file": "/home/ubuntu/.claude/tokens/secondary.token",
      "status": "standby",
      "description": "Backup subscription account"
    }
  ],
  "current_account": "primary"
}
```

### Step 2: Setup Secondary Account Authentication

**Option A: Long-lived Token (Recommended)**
```bash
# Setup token for secondary account
claude setup-token  # Follow prompts for secondary account
mkdir -p /home/ubuntu/.claude/tokens
# Save token to /home/ubuntu/.claude/tokens/secondary.token
```

**Option B: GitHub Secret (For CI/CD)**
```bash
# Add to GitHub repository secrets:
CLAUDE_SECONDARY_TOKEN=your_secondary_account_token
```

### Step 3: Test Account Rotation

```bash
# Check current status
bash scripts/claude_limit_handler.sh status

# Test manual account switching
bash scripts/claude_limit_handler.sh switch secondary

# Test automatic execution with limit handling
bash scripts/claude_limit_handler.sh execute claude --print "test message"
```

## 🚀 Usage

### Automatic Integration

The system automatically handles limits in your CI/CD workflows:

```bash
# Instead of direct Claude calls:
claude --print "analyze this code"

# Use the limit handler:
bash scripts/claude_limit_handler.sh execute claude --print "analyze this code"
```

### GitHub Actions Integration

The workflow now includes automatic limit handling:

```yaml
- name: Claude Code — Planification & développement
  env:
    CLAUDE_SECONDARY_TOKEN: ${{ secrets.CLAUDE_SECONDARY_TOKEN }}
  run: |
    # Setup is automatic - accounts rotate when limits hit
    bash scripts/cc_plan_and_code.sh
```

### Manual Session Resume

If a session was interrupted:

```bash
# Resume from saved state
bash scripts/resume_claude_session.sh

# Check session state
cat artifacts/claude_session_state.json
```

## 🔄 How It Works

### Limit Detection

The system detects limits by monitoring Claude output for:
- "daily limit" / "rate limit" / "usage limit"
- "too many requests" / "quota exceeded"
- HTTP 429 status codes

### Account Rotation Flow

```
1. Execute Claude command
2. Detect limit reached
3. Try next available account
4. If successful, retry command
5. If all accounts limited, wait for reset
```

### Sleep/Resume Flow

```
1. Extract reset time from error message
2. Save current session state
3. Sleep until reset time
4. Resume from saved state
5. Continue execution
```

## 📊 Session State Management

### State File Structure

```json
{
  "timestamp": "2025-08-28T15:30:00Z",
  "current_task": "claude_execution",
  "progress": "analyzing_specification",
  "environment": {
    "RUN_ID": "abc123",
    "TARGET_REPO": "user/project",
    "PROJECT_NAME": "My Project"
  },
  "files": {
    "spec": "spec.yaml",
    "artifacts": "claude_prompt.md,analysis.txt"
  }
}
```

### Resume Scenarios

| Saved Task | Resume Action |
|------------|---------------|
| `claude_execution` | Re-run Claude with saved prompt |
| `planning` | Continue project initialization |  
| `testing` | Run test suite |
| `waiting_for_reset` | Check limit and retry |

## 🛠️ Configuration Options

### Account Management

```bash
# Add new account
jq '.accounts += [{"id": "tertiary", "auth_method": "token", "status": "standby"}]' \
   ops/claude_accounts.json > ops/claude_accounts.json.tmp && \
   mv ops/claude_accounts.json.tmp ops/claude_accounts.json

# Disable account
jq '.accounts |= map(if .id == "secondary" then .status = "disabled" else . end)' \
   ops/claude_accounts.json > ops/claude_accounts.json.tmp && \
   mv ops/claude_accounts.json.tmp ops/claude_accounts.json
```

### Timing Configuration

```bash
# In claude_limit_handler.sh:
RETRY_DELAY=300      # Seconds between retry attempts
MAX_WAIT_TIME=43200  # Maximum sleep time (12 hours)
```

## 📈 Monitoring & Logging

### Check Account Status

```bash
bash scripts/claude_limit_handler.sh status
```

Output:
```
Current account: primary
Available accounts:
  primary: active (Primary subscription account)
  secondary: standby (Backup subscription account)
```

### Resume Logs

```bash
# Check resume history
cat artifacts/resume.log

# Monitor session state
watch -n 60 "cat artifacts/claude_session_state.json 2>/dev/null || echo 'No active session'"
```

## 🚨 Troubleshooting

### Common Issues

**1. Secondary Account Not Working**
```bash
# Verify token file exists and has correct permissions
ls -la /home/ubuntu/.claude/tokens/secondary.token

# Test token directly
ANTHROPIC_API_KEY=$(cat /home/ubuntu/.claude/tokens/secondary.token) \
claude --print "test connection"
```

**2. Session Resume Fails**
```bash
# Check session state file
cat artifacts/claude_session_state.json

# Manually restore environment
source <(jq -r '.environment | to_entries[] | "export \(.key)=\(.value)"' artifacts/claude_session_state.json)
```

**3. Limit Detection Not Working**
```bash
# Test limit detection manually
echo "daily limit reached" | bash scripts/claude_limit_handler.sh detect_limit_reached -
echo $? # Should return 0 (true)
```

### Recovery Procedures

**Complete Reset**
```bash
# Clear all session state
rm -f artifacts/claude_session_state.json ops/claude_accounts.json

# Reinitialize
bash scripts/claude_limit_handler.sh init
```

**Force Account Switch**
```bash
# Switch accounts manually
bash scripts/claude_limit_handler.sh switch secondary manual
```

## 🔒 Security Considerations

### Token Storage

- Store tokens in restricted directories: `chmod 600 /home/ubuntu/.claude/tokens/*`
- Use GitHub secrets for CI/CD environments
- Rotate tokens regularly

### Session State

- Session state may contain sensitive project information
- Stored in `artifacts/` directory (included in .gitignore)
- Automatically cleaned up on successful completion

## 📚 Integration Examples

### Development Workflow

```bash
#!/bin/bash
# Enhanced development script

# Initialize limit handling
bash scripts/claude_limit_handler.sh init

# Execute development tasks with auto-resume
bash scripts/claude_limit_handler.sh execute \
  claude --print "Analyze codebase and suggest improvements"

# If interrupted, resume later:
bash scripts/resume_claude_session.sh
```

### CI/CD Pipeline

```yaml
# .github/workflows/development.yml
- name: AI-Powered Development
  run: |
    # Setup multi-account handling
    if [[ -n "${{ secrets.CLAUDE_SECONDARY_TOKEN }}" ]]; then
      mkdir -p ~/.claude/tokens
      echo "${{ secrets.CLAUDE_SECONDARY_TOKEN }}" > ~/.claude/tokens/secondary.token
    fi
    
    # Execute with automatic limit handling
    bash scripts/cc_plan_and_code.sh
    
    # Upload session state if interrupted
  - uses: actions/upload-artifact@v3
    if: always()
    with:
      name: claude-session-state
      path: artifacts/claude_session_state.json
```

This comprehensive limit handling system ensures your AI Continuous Delivery pipeline remains resilient and can operate continuously even with Claude subscription limits.