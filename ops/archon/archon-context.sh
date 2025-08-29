#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACTS_DIR="$ROOT_DIR/artifacts"
OUT_MD="$ARTIFACTS_DIR/archon_dev_brief.md"

mkdir -p "$ARTIFACTS_DIR"

{
  echo "# Development Brief"
  echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%SZ')"
  echo
  echo "## Git Snapshot"
  git -C "$ROOT_DIR" log --oneline -n 5 || echo "(no git history)"
  echo
  echo "## Project Tree (top)"
  find "$ROOT_DIR" -maxdepth 2 -type f | head -n 30
  echo
  echo "## README.md"
  head -n 40 "$ROOT_DIR/README.md" || echo "(no README)"
  echo
  echo "👉 Copy sections above into Copilot Chat to guide code generation."
} > "$OUT_MD"

echo "✅ Brief generated at: $OUT_MD"
