#!/bin/bash
set -euo pipefail

# Resume Claude Code Session Script
# Handles resuming interrupted Claude Code sessions

echo "🔄 Claude Code Session Resume Handler"

SESSION_STATE_FILE="artifacts/claude_session_state.json"
RESUME_LOG="artifacts/resume.log"

if [[ ! -f "$SESSION_STATE_FILE" ]]; then
    echo "❌ No session state found to resume"
    echo "Looking for: $SESSION_STATE_FILE"
    exit 1
fi

# Log resume attempt
echo "[$(date -Iseconds)] Resume attempt started" >> "$RESUME_LOG"

# Restore session state
echo "📋 Restoring session state..."
if bash scripts/claude_limit_handler.sh restore; then
    echo "✅ Session state restored"
else
    echo "⚠️ Could not restore full session state, proceeding with available context"
fi

# Check current task from state
CURRENT_TASK=$(jq -r '.current_task // "unknown"' "$SESSION_STATE_FILE" 2>/dev/null || echo "unknown")
PROGRESS=$(jq -r '.progress // "unknown"' "$SESSION_STATE_FILE" 2>/dev/null || echo "unknown")

echo "📊 Session Details:"
echo "  Task: $CURRENT_TASK"  
echo "  Progress: $PROGRESS"
echo "  Saved: $(jq -r '.timestamp // "unknown"' "$SESSION_STATE_FILE" 2>/dev/null || echo "unknown")"

# Check if Claude limit has reset
echo "🔍 Checking Claude account status..."
bash scripts/claude_limit_handler.sh status

# Resume based on the task that was interrupted
case "$CURRENT_TASK" in
    "claude_execution"|"planning")
        echo "🤖 Resuming Claude Code planning phase..."
        
        # Continue from where we left off
        if [[ -f "artifacts/claude_prompt.md" ]]; then
            echo "📝 Found existing prompt, continuing analysis..."
            
            # Try to execute with limit handling again
            if bash scripts/claude_limit_handler.sh execute claude --print "$(cat artifacts/claude_prompt.md)" > artifacts/claude_analysis_resumed.txt; then
                echo "✅ Claude Code analysis resumed and completed"
                
                # Merge with any previous partial analysis
                if [[ -f "artifacts/claude_analysis.txt" ]]; then
                    echo -e "\n\n---\n# Resumed Analysis\n" >> artifacts/claude_analysis.txt
                    cat artifacts/claude_analysis_resumed.txt >> artifacts/claude_analysis.txt
                else
                    mv artifacts/claude_analysis_resumed.txt artifacts/claude_analysis.txt
                fi
                
                # Continue with project initialization if needed
                if [[ ! -d "src" ]] && [[ ! -f "pyproject.toml" ]]; then
                    echo "🔧 Continuing project initialization..."
                    bash scripts/cc_plan_and_code.sh
                fi
                
                echo "[$(date -Iseconds)] Resume completed successfully" >> "$RESUME_LOG"
                
            else
                echo "❌ Claude Code still limited, session state preserved"
                echo "[$(date -Iseconds)] Resume failed - still limited" >> "$RESUME_LOG"
                exit 1
            fi
        else
            echo "⚠️ No prompt found, restarting from beginning"
            bash scripts/cc_plan_and_code.sh
        fi
        ;;
        
    "testing")
        echo "🧪 Resuming testing phase..."
        bash scripts/qwen_run_tests.sh
        ;;
        
    "waiting_for_reset")
        echo "⏰ Previous session was waiting for limit reset"
        
        # Check if we can execute now
        if bash scripts/claude_limit_handler.sh execute claude --print "test connection" > /dev/null 2>&1; then
            echo "✅ Claude limit appears to be reset, resuming..."
            bash scripts/resume_claude_session.sh
        else
            echo "⚠️ Claude still limited, continuing to wait"
            exit 1
        fi
        ;;
        
    *)
        echo "❓ Unknown task state: $CURRENT_TASK"
        echo "🔄 Attempting full restart..."
        bash scripts/cc_plan_and_code.sh
        ;;
esac

# Clean up session state on successful completion
if [[ $? -eq 0 ]]; then
    echo "🧹 Cleaning up session state..."
    rm -f "$SESSION_STATE_FILE"
    echo "[$(date -Iseconds)] Session fully resumed and cleaned up" >> "$RESUME_LOG"
fi

echo "✅ Session resume complete"