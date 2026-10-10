#!/usr/bin/env bash

set -euo pipefail

# This is intentionally lightweight; it catches obvious placeholders, not business correctness.
if [[ $# -ne 1 ]]; then
  printf 'usage: bash .ai-harness/.ai-standards/scripts/check_spec.sh <spec-id>\n' >&2
  exit 1
fi

SPEC_ID="$1"
SPEC_DIR=".ai-harness/specs/$SPEC_ID"
REQUIRED_FILES=(
  "01-requirements.md"
  "02-design.md"
  "03-tasks.md"
  "04-acceptance.md"
)
PLACEHOLDER_PATTERNS=(
  "<spec-id>"
  "Describe the business goal"
  "List concrete capabilities"
  "Requirement A verified"
)

EMPTY_FIELD_PATTERNS=(
  "Task ID"
  "Purpose"
  "Inputs"
  "Changes"
  "Validation"
  "Done"
  "Complexity"
  "Depends On"
)

fail_count=0

report_fail() {
  printf 'fail: %s\n' "$1"
  fail_count=$((fail_count + 1))
}

if [[ ! -e .git ]]; then
  # worktree 内 .git 是文件不是目录（`-e` 而非 `-d`）。
  report_fail "current directory is not a git repository root"
fi

if [[ ! -d "$SPEC_DIR" ]]; then
  report_fail "$SPEC_DIR not found"
else
  for file in "${REQUIRED_FILES[@]}"; do
    path="$SPEC_DIR/$file"
    if [[ ! -f "$path" ]]; then
      report_fail "missing $path"
      continue
    fi

    for pattern in "${PLACEHOLDER_PATTERNS[@]}"; do
      if grep -Fq "$pattern" "$path"; then
        report_fail "$path still contains placeholder text: $pattern"
      fi
    done

    for field in "${EMPTY_FIELD_PATTERNS[@]}"; do
      if awk -v field="$field" '
        function is_field_line(line) {
          return line ~ /^- (Task ID|Purpose|Inputs|Changes|Validation|Done|Complexity|Depends On):/
        }

        function finish_pending() {
          if (pending != "" && !has_content) {
            print pending
          }
          pending = ""
          has_content = 0
        }

        $0 ~ ("^- " field ":") {
          finish_pending()
          pending = field
          has_content = ($0 !~ ("^- " field ":[[:space:]]*$"))
          next
        }

        pending != "" && is_field_line($0) {
          finish_pending()
          next
        }

        pending != "" && $0 ~ /^##/ {
          finish_pending()
          next
        }

        pending != "" && $0 !~ /^[[:space:]]*$/ {
          has_content = 1
        }

        END {
          finish_pending()
        }
      ' "$path" | grep -q .; then
        report_fail "$path still contains empty required field: $field"
      fi
    done
  done
fi

if [[ "$fail_count" -eq 0 ]]; then
  printf 'pass: %s looks ready for review before development\n' "$SPEC_DIR"
  exit 0
fi

printf 'summary: %s issue(s) found in %s\n' "$fail_count" "$SPEC_DIR"
exit 1
