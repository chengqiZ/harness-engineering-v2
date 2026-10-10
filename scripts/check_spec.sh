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

# 依赖健康检查（v2.1）：AI 拆任务时容易写出指向不存在/成环的依赖，
# 运行期才暴露会变成「no ready task」的静默死锁——在 spec 门禁就拦下。
if [[ -f "$SPEC_DIR/03-tasks.md" ]]; then
  tasks_file="$SPEC_DIR/03-tasks.md"
  # 提取 Task ID 与 Depends On（依赖归一化：去反引号、按逗号/顿号切分、滤空和 none 标记）。
  deps_map="$(python3 - "$tasks_file" <<'PYEOF'
import re, sys
text = open(sys.argv[1]).read()
ids = re.findall(r"^- Task ID:[ `]*([^\s`]+)", text, re.M)
id_set = set(ids)
blocks = re.split(r"^### ", text, flags=re.M)[1:]
for b in blocks:
    m = re.search(r"^- Task ID:[ `]*([^\s`]+)", b, re.M)
    d = re.search(r"^- Depends On:[ \t]*(.*)$", b, re.M)
    if not m:
        continue
    raw = d.group(1) if d else ""
    raw = raw.replace("`", "")
    parts = re.split(r"[,，]", raw)
    for p in parts:
        p = p.strip().strip("|").strip()
        if not p or re.match(r"^(none|None|NONE|无|N/A|-|not applicable|\(none\)|\(None\))$", p):
            continue
        print(f"{m.group(1)}\t{p}")
PYEOF
)" || deps_map=""
  if [[ -n "$deps_map" ]]; then
    # 1) 悬空依赖：Depends On 指向不存在的 task id。
    while IFS=$'\t' read -r from to; do
      [[ -z "$from" ]] && continue
      if ! awk -v t="$to" 'match($0, /^- Task ID:[[:space:]]*`?([^`[:space:]]+)`?/, m) { if (m[1]==t) found=1 } END { exit !found }' "$tasks_file"; then
        report_fail "task $from depends on unknown task id: $to"
      fi
    done <<< "$deps_map"
    # 2) 循环依赖：从每个 task 出发 DFS，走不回起点即无环。
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$tasks_file" <<'PYEOF' || fail_cycles=1
import re, sys
text = open(sys.argv[1]).read()
blocks = re.split(r"^### ", text, flags=re.M)[1:]
deps = {}
for b in blocks:
    m = re.search(r"^- Task ID:[ `]*([^\s`]+)", b, re.M)
    d = re.search(r"^- Depends On:[ \t]*(.*)$", b, re.M)
    if not m:
        continue
    raw = (d.group(1) if d else "").replace("`", "")
    lst = []
    for p in re.split(r"[,，]", raw):
        p = p.strip().strip("|").strip()
        if not p or re.match(r"^(none|None|NONE|无|N/A|-|not applicable|\(none\)|\(None\))$", p):
            continue
        lst.append(p)
    deps[m.group(1)] = lst

def cycle_from(start):
    stack = [(start, [start])]
    seen_paths = set()
    while stack:
        node, path = stack.pop()
        for nxt in deps.get(node, []):
            if nxt == start:
                return path + [nxt]
            key = (nxt, tuple(path))
            if key in seen_paths or nxt not in deps:
                continue
            seen_paths.add(key)
            stack.append((nxt, path + [nxt]))
    return None

bad = []
for t in deps:
    c = cycle_from(t)
    if c:
        bad.append(" -> ".join(c))
if bad:
    for b in sorted(set(bad)):
        print(f"fail: circular dependency detected: {b}")
    sys.exit(1)
PYEOF
      [[ "${fail_cycles:-0}" = "1" ]] && report_fail "circular dependency detected in $tasks_file (see details above)"
    fi
  fi
fi

if [[ "$fail_count" -eq 0 ]]; then
  printf 'pass: %s looks ready for review before development\n' "$SPEC_DIR"
  exit 0
fi

printf 'summary: %s issue(s) found in %s\n' "$fail_count" "$SPEC_DIR"
exit 1
