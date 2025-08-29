#!/bin/bash
set -euo pipefail

# Gemini API Token Limit Handler
# Handles token rotation and quota management for Gemini CLI

echo "🔷 Gemini Token Limit Handler Initialized"

# Configuration
GEMINI_TOKENS_FILE="ops/gemini_tokens.json"
SESSION_STATE_FILE="artifacts/gemini_session_state.json"
RETRY_DELAY=60 # 1 minute between attempts for API limits
MAX_RETRIES=3

# Token configuration structure:
# {
#   "tokens": [
#     {
#       "id": "token1",
#       "value": "AIza....",
#       "status": "active",
#       "last_used": "2025-08-28T10:00:00Z",
#       "daily_requests": 0,
#       "quota_reset": "2025-08-29T00:00:00Z"
#     }
#   ],
#   "current_token": "token1",
#   "rotation_strategy": "round_robin"
# }

initialize_tokens() {
    if [[ ! -f "$GEMINI_TOKENS_FILE" ]]; then
        echo "⚙️ Creating Gemini tokens configuration..."
        mkdir -p "$(dirname "$GEMINI_TOKENS_FILE")"
        cat > "$GEMINI_TOKENS_FILE" << 'EOF'
{
  "tokens": [
    {
      "id": "token1",
      "value": "REPLACE_WITH_TOKEN_1",
      "status": "active",
      "last_used": null,
      "daily_requests": 0,
      "quota_reset": null,
      "description": "Primary Gemini API token"
    },
    {
      "id": "token2", 
      "value": "REPLACE_WITH_TOKEN_2",
      "status": "active",
      "last_used": null,
      "daily_requests": 0,
      "quota_reset": null,
      "description": "Secondary Gemini API token"
    },
    {
      "id": "token3",
      "value": "REPLACE_WITH_TOKEN_3", 
      "status": "active",
      "last_used": null,
      "daily_requests": 0,
      "quota_reset": null,
      "description": "Tertiary Gemini API token"
    }
  ],
  "current_token": "token1",
  "rotation_strategy": "round_robin",
  "last_rotation": null
}
EOF
        echo "📝 Created $GEMINI_TOKENS_FILE"
        echo "⚠️  IMPORTANT: Replace REPLACE_WITH_TOKEN_X with your actual Gemini API tokens"
        return 1
    fi
    return 0
}

get_current_token() {
    if [[ ! -f "$GEMINI_TOKENS_FILE" ]]; then
        echo ""
        return 1
    fi
    jq -r '.current_token // "token1"' "$GEMINI_TOKENS_FILE"
}

get_token_value() {
    local token_id="$1"
    if [[ ! -f "$GEMINI_TOKENS_FILE" ]]; then
        echo ""
        return 1
    fi
    jq -r --arg token_id "$token_id" '.tokens[] | select(.id == $token_id) | .value' "$GEMINI_TOKENS_FILE"
}

get_next_token() {
    local current_token="$1"
    if [[ ! -f "$GEMINI_TOKENS_FILE" ]]; then
        echo "token1"
        return
    fi
    
    # Get next available token using round-robin
    jq -r --arg current "$current_token" '
        .tokens 
        | map(select(.status == "active"))
        | map(.id) 
        | . as $ids 
        | ($ids | map(. == $current) | index(true) + 1) % length 
        | $ids[.]
    ' "$GEMINI_TOKENS_FILE"
}

switch_to_token() {
    local target_token="$1"
    local reason="${2:-manual}"
    
    echo "🔄 Switching to Gemini token: $target_token (reason: $reason)"
    
    # Get token value
    local token_value=$(get_token_value "$target_token")
    if [[ -z "$token_value" || "$token_value" == "null" ]]; then
        echo "❌ Token not found: $target_token"
        return 1
    fi
    
    # Update current token in config
    if [[ -f "$GEMINI_TOKENS_FILE" ]]; then
        jq --arg token "$target_token" --arg timestamp "$(date -Iseconds)" '
            .current_token = $token |
            .last_rotation = $timestamp |
            .tokens |= map(
                if .id == $token then 
                    .last_used = $timestamp |
                    .daily_requests = (.daily_requests + 1)
                else . end
            )
        ' "$GEMINI_TOKENS_FILE" > "${GEMINI_TOKENS_FILE}.tmp"
        mv "${GEMINI_TOKENS_FILE}.tmp" "$GEMINI_TOKENS_FILE"
    fi
    
    # Set environment variable for Gemini CLI
    export GEMINI_API_KEY="$token_value"
    echo "✅ Switched to token: $target_token"
    
    return 0
}

detect_quota_exceeded() {
    local gemini_output="$1"
    
    # Check for common Gemini API quota/limit messages
    if echo "$gemini_output" | grep -qi "quota exceeded\|rate limit\|too many requests\|429\|limit reached\|resource_exhausted"; then
        return 0
    fi
    
    # Check for authentication errors (invalid token)
    if echo "$gemini_output" | grep -qi "invalid api key\|authentication\|401\|forbidden\|403"; then
        return 0
    fi
    
    return 1
}

extract_reset_time() {
    local gemini_output="$1"
    
    # Try to extract reset time from Gemini API error response
    # Common formats: "Try again in X seconds", "Quota resets at ...", etc.
    
    local reset_time=""
    
    # Extract seconds from "try again in X seconds"
    local seconds=$(echo "$gemini_output" | grep -oP 'try again in \K[0-9]+(?= seconds?)' | head -1)
    if [[ -n "$seconds" ]]; then
        date -d "+${seconds} seconds" +%s
        return 0
    fi
    
    # Extract minutes
    local minutes=$(echo "$gemini_output" | grep -oP 'try again in \K[0-9]+(?= minutes?)' | head -1)
    if [[ -n "$minutes" ]]; then
        date -d "+${minutes} minutes" +%s
        return 0
    fi
    
    # Default to 1 hour if we can't parse (typical API quota reset)
    date -d "+1 hour" +%s
}

save_session_state() {
    local current_task="$1"
    local progress="$2"
    local context="${3:-}"
    local failed_token="${4:-}"
    
    echo "💾 Saving Gemini session state..."
    
    mkdir -p "$(dirname "$SESSION_STATE_FILE")"
    cat > "$SESSION_STATE_FILE" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "current_task": "$current_task",
    "progress": "$progress", 
    "context": "$context",
    "failed_token": "$failed_token",
    "environment": {
        "RUN_ID": "${RUN_ID:-}",
        "TARGET_REPO": "${TARGET_REPO:-}",
        "PROJECT_NAME": "${PROJECT_NAME:-}",
        "SPEC_ID": "${SPEC_ID:-}"
    },
    "files": {
        "test_results": "$(find artifacts -name "*test*" -o -name "*junit*" 2>/dev/null | head -5 | tr '\n' ',' || echo 'none')",
        "coverage": "$(find artifacts -name "*coverage*" 2>/dev/null | head -3 | tr '\n' ',' || echo 'none')"
    }
}
EOF
}

restore_session_state() {
    if [[ ! -f "$SESSION_STATE_FILE" ]]; then
        echo "⚠️ No Gemini session state to restore"
        return 1
    fi
    
    echo "🔄 Restoring Gemini session state..."
    
    # Restore environment variables
    if command -v jq &> /dev/null; then
        export RUN_ID=$(jq -r '.environment.RUN_ID // empty' "$SESSION_STATE_FILE")
        export TARGET_REPO=$(jq -r '.environment.TARGET_REPO // empty' "$SESSION_STATE_FILE")  
        export PROJECT_NAME=$(jq -r '.environment.PROJECT_NAME // empty' "$SESSION_STATE_FILE")
        export SPEC_ID=$(jq -r '.environment.SPEC_ID // empty' "$SESSION_STATE_FILE")
        
        local current_task=$(jq -r '.current_task // empty' "$SESSION_STATE_FILE")
        local progress=$(jq -r '.progress // empty' "$SESSION_STATE_FILE")
        local failed_token=$(jq -r '.failed_token // empty' "$SESSION_STATE_FILE")
        
        echo "📋 Restored session - Task: $current_task, Progress: $progress"
        if [[ -n "$failed_token" ]]; then
            echo "⚠️ Previous failure with token: $failed_token"
        fi
        return 0
    fi
    
    return 1
}

execute_with_token_fallback() {
    local command="$@"
    local max_retries=3
    local retry_count=0
    local current_token=$(get_current_token)
    local tokens_tried=()
    
    while [[ $retry_count -lt $max_retries ]]; do
        echo "🔷 Executing Gemini command (attempt $((retry_count + 1))/$max_retries with token: $current_token)..."
        
        # Switch to current token
        if ! switch_to_token "$current_token" "execution_attempt"; then
            echo "❌ Failed to switch to token: $current_token"
            retry_count=$((retry_count + 1))
            continue
        fi
        
        # Execute command and capture output
        local output_file=$(mktemp)
        local exit_code=0
        
        $command > "$output_file" 2>&1 || exit_code=$?
        local gemini_output=$(cat "$output_file")
        
        # Check if quota/limit was reached
        if detect_quota_exceeded "$gemini_output"; then
            echo "⚠️ Gemini API quota/limit reached for token: $current_token"
            echo "Output: $(echo "$gemini_output" | head -3)"
            
            # Add to tried tokens
            tokens_tried+=("$current_token")
            
            # Try next token
            local next_token=$(get_next_token "$current_token")
            
            # Check if we've tried all tokens
            if [[ " ${tokens_tried[@]} " =~ " ${next_token} " ]]; then
                echo "❌ All tokens exhausted, waiting for quota reset..."
                
                # Extract reset time and wait
                local reset_time=$(extract_reset_time "$gemini_output")
                local current_time=$(date +%s)
                local wait_seconds=$((reset_time - current_time))
                
                echo "🕐 Quota resets at: $(date -d "@$reset_time")"
                echo "⏱️ Wait time: $(($wait_seconds / 60))m $(($wait_seconds % 60))s"
                
                if [[ $wait_seconds -gt 0 && $wait_seconds -lt 7200 ]]; then # Max 2 hours
                    echo "😴 Sleeping until quota reset..."
                    save_session_state "gemini_execution" "waiting_for_quota_reset" "$command" "$current_token"
                    sleep "$wait_seconds"
                    echo "⏰ Quota should be reset, retrying with first token..."
                    current_token=$(jq -r '.tokens[0].id' "$GEMINI_TOKENS_FILE")
                    tokens_tried=()
                else
                    echo "❌ Wait time too long or invalid, failing"
                    rm -f "$output_file"
                    return 1
                fi
            else
                echo "🔄 Trying next token: $next_token"
                current_token="$next_token"
            fi
            
        elif [[ $exit_code -eq 0 ]]; then
            # Success!
            echo "✅ Gemini command completed successfully"
            echo "$gemini_output"
            rm -f "$output_file"
            return 0
        else
            # Other error
            echo "❌ Gemini command failed with exit code $exit_code"
            echo "$gemini_output"
            
            # If it's a token/auth error, try next token
            if echo "$gemini_output" | grep -qi "invalid api key\|authentication\|401\|403"; then
                tokens_tried+=("$current_token")
                current_token=$(get_next_token "$current_token")
                echo "🔑 Authentication error, trying next token: $current_token"
            else
                # Non-quota error, fail immediately
                rm -f "$output_file"
                return 1
            fi
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

# Check if Gemini CLI is installed
check_gemini_cli() {
    if ! command -v gemini &> /dev/null; then
        echo "❌ Gemini CLI not found. Please install it first:"
        echo "npm install -g @google/generative-ai-cli"
        echo "# or"  
        echo "pip install google-generativeai"
        return 1
    fi
    
    echo "✅ Gemini CLI found: $(which gemini)"
    return 0
}

# Main execution
case "${1:-help}" in
    "init")
        initialize_tokens
        ;;
    "switch")
        switch_to_token "${2:-token1}" "${3:-manual}"
        ;;
    "status")
        echo "Current token: $(get_current_token)"
        if [[ -f "$GEMINI_TOKENS_FILE" ]]; then
            echo "Available tokens:"
            jq -r '.tokens[] | "  \(.id): \(.status) (\(.description)) - Used: \(.daily_requests // 0) times"' "$GEMINI_TOKENS_FILE"
        fi
        ;;
    "execute")
        shift
        if check_gemini_cli; then
            execute_with_token_fallback "$@"
        else
            exit 1
        fi
        ;;
    "restore")
        restore_session_state
        ;;
    "test")
        echo "🧪 Testing Gemini API connection..."
        if check_gemini_cli; then
            execute_with_token_fallback gemini "Hello, test connection"
        fi
        ;;
    "help"|*)
        echo "Usage: $0 {init|switch|status|execute|restore|test|help}"
        echo ""
        echo "Commands:"
        echo "  init     - Initialize token configuration"
        echo "  switch   - Switch to specified token"  
        echo "  status   - Show current token status"
        echo "  execute  - Execute Gemini command with token fallback"
        echo "  restore  - Restore previous session state"
        echo "  test     - Test Gemini API connection"
        ;;
esac