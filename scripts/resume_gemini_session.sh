#!/bin/bash
set -euo pipefail

# Resume Gemini AI Session Script
# Handles resuming interrupted Gemini AI testing sessions

echo "🔄 Gemini AI Session Resume Handler"

SESSION_STATE_FILE="artifacts/gemini_session_state.json"
RESUME_LOG="artifacts/gemini_resume.log"

if [[ ! -f "$SESSION_STATE_FILE" ]]; then
    echo "❌ No Gemini session state found to resume"
    echo "Looking for: $SESSION_STATE_FILE"
    exit 1
fi

# Log resume attempt
echo "[$(date -Iseconds)] Gemini resume attempt started" >> "$RESUME_LOG"

# Restore session state
echo "📋 Restoring Gemini session state..."
if bash scripts/gemini_limit_handler.sh restore; then
    echo "✅ Session state restored"
else
    echo "⚠️ Could not restore full session state, proceeding with available context"
fi

# Check current task from state
CURRENT_TASK=$(jq -r '.current_task // "unknown"' "$SESSION_STATE_FILE" 2>/dev/null || echo "unknown")
PROGRESS=$(jq -r '.progress // "unknown"' "$SESSION_STATE_FILE" 2>/dev/null || echo "unknown")
FAILED_TOKEN=$(jq -r '.failed_token // empty' "$SESSION_STATE_FILE" 2>/dev/null || echo "")

echo "📊 Gemini Session Details:"
echo "  Task: $CURRENT_TASK"  
echo "  Progress: $PROGRESS"
echo "  Failed Token: ${FAILED_TOKEN:-'none'}"
echo "  Saved: $(jq -r '.timestamp // "unknown"' "$SESSION_STATE_FILE" 2>/dev/null || echo "unknown")"

# Check Gemini token status
echo "🔍 Checking Gemini token status..."
bash scripts/gemini_limit_handler.sh status

# Resume based on the task that was interrupted
case "$CURRENT_TASK" in
    "gemini_execution"|"testing"|"analysis")
        echo "🔷 Resuming Gemini AI testing phase..."
        
        # Switch to different token if previous one failed
        if [[ -n "$FAILED_TOKEN" ]]; then
            echo "🔄 Switching away from failed token: $FAILED_TOKEN"
            CURRENT_TOKEN=$(bash scripts/gemini_limit_handler.sh status | grep "Current token:" | cut -d' ' -f3)
            NEXT_TOKEN=$(jq -r --arg current "$CURRENT_TOKEN" '.tokens | map(select(.id != $current and .status == "active")) | first | .id // empty' ops/gemini_tokens.json 2>/dev/null || echo "")
            
            if [[ -n "$NEXT_TOKEN" ]]; then
                bash scripts/gemini_limit_handler.sh switch "$NEXT_TOKEN" "resume_after_failure"
            fi
        fi
        
        # Continue from where we left off
        if [[ -f "artifacts/test_analysis_prompt.md" ]] || [[ -f "artifacts/post_test_analysis_prompt.md" ]]; then
            echo "📝 Found existing analysis prompts, continuing testing..."
            
            # Try to execute tests with token handling again
            if bash scripts/gemini_run_tests.sh; then
                echo "✅ Gemini AI testing resumed and completed"
                echo "[$(date -Iseconds)] Resume completed successfully" >> "$RESUME_LOG"
            else
                echo "❌ Gemini AI testing still failed, session state preserved"
                echo "[$(date -Iseconds)] Resume failed - still limited" >> "$RESUME_LOG"
                exit 1
            fi
        else
            echo "⚠️ No previous analysis found, restarting from beginning"
            bash scripts/gemini_run_tests.sh
        fi
        ;;
        
    "waiting_for_quota_reset")
        echo "⏰ Previous session was waiting for quota reset"
        
        # Check if we can execute now
        if bash scripts/gemini_limit_handler.sh test > /dev/null 2>&1; then
            echo "✅ Gemini quota appears to be reset, resuming..."
            bash scripts/resume_gemini_session.sh
        else
            echo "⚠️ Gemini still limited, continuing to wait"
            exit 1
        fi
        ;;
        
    "planning")
        echo "🧠 Previous session was in planning phase, continuing with testing..."
        bash scripts/gemini_run_tests.sh
        ;;
        
    *)
        echo "❓ Unknown task state: $CURRENT_TASK"
        echo "🔄 Attempting full test restart..."
        bash scripts/gemini_run_tests.sh
        ;;
esac

# Clean up session state on successful completion
if [[ $? -eq 0 ]]; then
    echo "🧹 Cleaning up Gemini session state..."
    rm -f "$SESSION_STATE_FILE"
    echo "[$(date -Iseconds)] Gemini session fully resumed and cleaned up" >> "$RESUME_LOG"
fi

echo "✅ Gemini session resume complete"