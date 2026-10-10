#!/usr/bin/env bash

set -euo pipefail

HARNESS_DIR=".ai-harness"
STANDARDS_DIR="$HARNESS_DIR/.ai-standards"
SPEC_DIR="$HARNESS_DIR/specs"
CHANGELOG_DIR="$HARNESS_DIR/docs/changelog"
REPO_AGENTS="$HARNESS_DIR/AGENTS.md"
PR_TEMPLATE_DIR=".github"
PR_TEMPLATE="$PR_TEMPLATE_DIR/pull_request_template.md"
AI_ENTRY="./ai"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

say() {
  printf '%s\n' "$1"
}

copy_if_missing() {
  local src="$1"
  local dest="$2"
  if [[ -e "$dest" ]]; then
    say "skip: $dest already exists"
    return
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  say "create: $dest"
}

if [[ ! -d .git ]]; then
  say "error: current directory is not a git repository root"
  exit 1
fi

if [[ ! -d "$STANDARDS_DIR" ]]; then
  say "error: $STANDARDS_DIR not found"
  say "hint: run 'git submodule add <repo-url> $STANDARDS_DIR' first, then rerun this script"
  exit 1
fi

mkdir -p "$SPEC_DIR" "$CHANGELOG_DIR" "$PR_TEMPLATE_DIR"
say "ensure: $SPEC_DIR"
say "ensure: $CHANGELOG_DIR"

copy_if_missing "$ROOT_DIR/templates/business-repo-AGENTS.md" "$REPO_AGENTS"
copy_if_missing "$ROOT_DIR/templates/pull_request_template.md" "$PR_TEMPLATE"
copy_if_missing "$ROOT_DIR/docs/changelog/README.md" "$CHANGELOG_DIR/README.md"
# v2：ai.sh 是薄机械编排器（无 Codex 依赖）；已初始化过的仓库若还是旧版 ./ai，则升级替换。
if [[ -f "$AI_ENTRY" && -z "$(grep -l 'thin mechanical orchestrator' "$AI_ENTRY" 2>/dev/null)" ]]; then
  cp "$ROOT_DIR/templates/ai.sh" "$AI_ENTRY"
  chmod +x "$AI_ENTRY"
  say "upgrade: $AI_ENTRY (v1 Codex orchestrator -> v2 thin orchestrator)"
elif [[ ! -f "$AI_ENTRY" ]]; then
  cp "$ROOT_DIR/templates/ai.sh" "$AI_ENTRY"
  chmod +x "$AI_ENTRY"
  say "create: $AI_ENTRY"
fi

say ""
say "bootstrap complete"
say "manual follow-up:"
say "1. Fill $REPO_AGENTS with project-specific exceptions only."
say "2. Run './ai status' to verify the daily entrypoint."
say "3. New request: './ai spec <spec-id> <source-doc>', then let your host agent read the spec-prep skill: './ai skill spec-prep'."
