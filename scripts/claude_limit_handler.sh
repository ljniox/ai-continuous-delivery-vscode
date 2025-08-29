#!/bin/bash
set -euo pipefail

# Claude Code Subscription Limit Handler
# Handles account rotation and session continuity

echo "🔄 Claude Code Limit Handler Initialized"

# Configuration
CLAUDE_ACCOUNTS_FILE="ops/claude_accounts.json"
SESSION_STATE_FILE="artifacts/claude_session_state.json"
RETRY_DELAY=300 # 5 minutes between attempts

# Account configuration structure:
# {
#   "accounts": [
#     {
#       "id": "primary",
#       "auth_method": "login", 
#       "status": "active",
#       "last_used": "2025-08-28T10:00:00Z",
#       "daily_limit_reset": "2025-08-29T00:00:00Z"
#     },
#     {
#       "id": "secondary", 
#       "auth_method": "token",
#       "token_file": "/home/ubuntu/.claude/tokens/secondary.token",
#       "status": "standby",
#       "last_used": null,
#       "daily_limit_reset": "2025-08-29T00:00:00Z"
#     }
#   ],
#   "current_account": "primary"
# }

initialize_accounts() {
    if [[ ! -f "$CLAUDE_ACCOUNTS_FILE" ]]; then
        echo "⚙️ Creating default Claude accounts configuration..."
        mkdir -p "$(dirname "$CLAUDE_ACCOUNTS_FILE")"
        cat > "$CLAUDE_ACCOUNTS_FILE" << 'EOF'
{
  "accounts": [
    {
      "id": "primary",
      "auth_method": "login",
      "status": "active",
      "last_used": null,
      "daily_limit_reset": null,
      "description": "Primary subscription account"
    },
    {
      "id": "secondary", 
      "auth_method": "token",
      "token_file": "/home/ubuntu/.claude/tokens/secondary.token",
      "status": "standby",
      "last_used": null,
      "daily_limit_reset": null,
      "description": "Backup subscription account"
    }
  ],
  "current_account": "primary",
  "last_rotation": null
}
EOF
        echo "📝 Created $CLAUDE_ACCOUNTS_FILE - configure your backup accounts"
        return 1
    fi
    return 0
}

get_current_account() {
    if [[ ! -f "$CLAUDE_ACCOUNTS_FILE" ]]; then
        echo "primary"
        return
    fi
    jq -r '.current_account // "primary"' "$CLAUDE_ACCOUNTS_FILE"
}

get_next_account() {
    local current_account="$1"
    if [[ ! -f "$CLAUDE_ACCOUNTS_FILE" ]]; then
        echo "primary"
        return
    fi
    
    # Get next available account
    jq -r --arg current "$current_account" '
        .accounts 
        | map(select(.status == "active" or .status == "standby"))
        | map(.id) 
        | . as $ids 
        | ($ids | map(. == $current) | index(true) + 1) % length 
        | $ids[.]
    ' "$CLAUDE_ACCOUNTS_FILE"
}

switch_to_account() {
    local target_account="$1"
    local reason="${2:-manual}"
    
    echo "🔄 Switching to Claude account: $target_account (reason: $reason)"
    
    # Update current account in config
    if [[ -f "$CLAUDE_ACCOUNTS_FILE" ]]; then
        jq --arg account "$target_account" --arg timestamp "$(date -Iseconds)" '
            .current_account = $account |
            .last_rotation = $timestamp |
            .accounts |= map(
                if .id == $account then 
                    .last_used = $timestamp 
                else . end
            )
        ' "$CLAUDE_ACCOUNTS_FILE" > "${CLAUDE_ACCOUNTS_FILE}.tmp"
        mv "${CLAUDE_ACCOUNTS_FILE}.tmp" "$CLAUDE_ACCOUNTS_FILE"
    fi
    
    # Configure Claude CLI for the account
    case "$target_account" in
        "primary")
            # Use default logged-in session
            unset ANTHROPIC_API_KEY
            echo "✅ Switched to primary account (login session)"
            ;;
        "secondary")
            # Use token authentication if available
            local token_file=$(jq -r --arg account "$target_account" '.accounts[] | select(.id == $account) | .token_file // empty' "$CLAUDE_ACCOUNTS_FILE")
            if [[ -n "$token_file" && -f "$token_file" ]]; then
                export ANTHROPIC_API_KEY=$(cat "$token_file")
                echo "✅ Switched to secondary account (token auth)"
            else
                echo "❌ Secondary account token not found: $token_file"
                return 1
            fi
            ;;
        *)
            echo "❌ Unknown account: $target_account"
            return 1
            ;;
    esac
}

detect_limit_reached() {
    local claude_output="$1"
    
    # Check for common limit messages
    if echo "$claude_output" | grep -qi "daily limit\|rate limit\|usage limit\|too many requests"; then
        return 0
    fi
    
    # Check for specific error patterns
    if echo "$claude_output" | grep -qi "429\|quota exceeded"; then
        return 0
    fi
    
    return 1
}

extract_reset_time() {
    local claude_output="$1"
    
    # Try to extract reset time from various formats
    # "limit resets at 2025-08-29 00:00:00 UTC"
    # "try again in 4 hours" 
    # "limit resets in 6 hours 23 minutes"
    
    local reset_time=""
    
    # Extract absolute time
    reset_time=$(echo "$claude_output" | grep -oP 'resets? at \K[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)
    if [[ -n "$reset_time" ]]; then
        date -d "$reset_time UTC" +%s
        return 0
    fi
    
    # Extract relative time
    local hours=$(echo "$claude_output" | grep -oP 'in \K[0-9]+(?= hours?)' | head -1)
    local minutes=$(echo "$claude_output" | grep -oP '([0-9]+) minutes?' | tail -1 | grep -oP '[0-9]+')
    
    if [[ -n "$hours" ]]; then
        local total_seconds=$((hours * 3600))
        if [[ -n "$minutes" ]]; then
            total_seconds=$((total_seconds + minutes * 60))
        fi
        date -d "+${total_seconds} seconds" +%s
        return 0
    fi
    
    # Default to next day if we can't parse
    date -d "tomorrow 00:00:00 UTC" +%s
}

save_session_state() {
    local current_task="$1"
    local progress="$2"
    local context="${3:-}"
    
    echo "💾 Saving session state..."
    
    mkdir -p "$(dirname "$SESSION_STATE_FILE")"
    cat > "$SESSION_STATE_FILE" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "current_task": "$current_task",
    "progress": "$progress", 
    "context": "$context",
    "environment": {
        "RUN_ID": "${RUN_ID:-}",
        "TARGET_REPO": "${TARGET_REPO:-}",
        "PROJECT_NAME": "${PROJECT_NAME:-}",
        "SPEC_ID": "${SPEC_ID:-}"
    },
    "files": {
        "spec": "$([ -f spec.yaml ] && echo 'spec.yaml' || echo 'none')",
        "artifacts": "$(find artifacts -type f 2>/dev/null | head -10 | tr '\n' ',' || echo 'none')"
    }
}
EOF
}

restore_session_state() {
    if [[ ! -f "$SESSION_STATE_FILE" ]]; then
        echo "⚠️ No session state to restore"
        return 1
    fi
    
    echo "🔄 Restoring session state..."
    
    # Restore environment variables
    if command -v jq &> /dev/null; then
        export RUN_ID=$(jq -r '.environment.RUN_ID // empty' "$SESSION_STATE_FILE")
        export TARGET_REPO=$(jq -r '.environment.TARGET_REPO // empty' "$SESSION_STATE_FILE")  
        export PROJECT_NAME=$(jq -r '.environment.PROJECT_NAME // empty' "$SESSION_STATE_FILE")
        export SPEC_ID=$(jq -r '.environment.SPEC_ID // empty' "$SESSION_STATE_FILE")
        
        local current_task=$(jq -r '.current_task // empty' "$SESSION_STATE_FILE")
        local progress=$(jq -r '.progress // empty' "$SESSION_STATE_FILE")
        
        echo "📋 Restored session - Task: $current_task, Progress: $progress"
        return 0
    fi
    
    return 1
}

execute_with_limit_handling() {
    local command="$@"
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        echo "🤖 Executing Claude command (attempt $((retry_count + 1))/$max_retries)..."
        
        # Execute command and capture output
        local output_file=$(mktemp)
        local exit_code=0
        
        $command > "$output_file" 2>&1 || exit_code=$?
        local claude_output=$(cat "$output_file")
        
        # Check if limit was reached
        if detect_limit_reached "$claude_output"; then
            echo "⚠️ Claude subscription limit reached!"
            echo "Output: $(echo "$claude_output" | head -3)"
            
            # Extract reset time
            local reset_time=$(extract_reset_time "$claude_output")
            local current_time=$(date +%s)
            local wait_seconds=$((reset_time - current_time))
            
            echo "🕐 Limit resets at: $(date -d "@$reset_time")"
            echo "⏱️ Wait time: $(($wait_seconds / 3600))h $(($wait_seconds % 3600 / 60))m"
            
            # Try account rotation first
            local current_account=$(get_current_account)
            local next_account=$(get_next_account "$current_account")
            
            if [[ "$next_account" != "$current_account" ]]; then
                echo "🔄 Attempting account rotation..."
                if switch_to_account "$next_account" "limit_reached"; then
                    retry_count=$((retry_count + 1))
                    continue
                fi
            fi
            
            # If rotation failed or no other account, wait for reset
            if [[ $wait_seconds -gt 0 && $wait_seconds -lt 43200 ]]; then # Max 12 hours
                echo "😴 Sleeping until limit reset..."
                save_session_state "claude_execution" "waiting_for_reset" "$command"
                sleep "$wait_seconds"
                echo "⏰ Limit should be reset, resuming..."
            else
                echo "❌ Wait time too long or invalid, failing"
                rm -f "$output_file"
                return 1
            fi
        elif [[ $exit_code -eq 0 ]]; then
            # Success!
            echo "$claude_output"
            rm -f "$output_file"
            return 0
        else
            # Other error
            echo "❌ Claude command failed with exit code $exit_code"
            echo "$claude_output"
        fi
        
        retry_count=$((retry_count + 1))
        rm -f "$output_file"
        
        if [[ $retry_count -lt $max_retries ]]; then
            echo "🔄 Retrying in $RETRY_DELAY seconds..."
            sleep $RETRY_DELAY
        fi
    done
    
    echo "❌ Max retries exceeded"
    return 1
}

# Main execution
case "${1:-help}" in
    "init")
        initialize_accounts
        ;;
    "switch")
        switch_to_account "${2:-primary}" "${3:-manual}"
        ;;
    "status")
        echo "Current account: $(get_current_account)"
        if [[ -f "$CLAUDE_ACCOUNTS_FILE" ]]; then
            echo "Available accounts:"
            jq -r '.accounts[] | "  \(.id): \(.status) (\(.description))"' "$CLAUDE_ACCOUNTS_FILE"
        fi
        ;;
    "execute")
        shift
        execute_with_limit_handling "$@"
        ;;
    "restore")
        restore_session_state
        ;;
    "help"|*)
        echo "Usage: $0 {init|switch|status|execute|restore|help}"
        echo ""
        echo "Commands:"
        echo "  init     - Initialize account configuration"
        echo "  switch   - Switch to specified account"  
        echo "  status   - Show current account status"
        echo "  execute  - Execute Claude command with limit handling"
        echo "  restore  - Restore previous session state"
        ;;
esac