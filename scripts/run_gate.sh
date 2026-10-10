#!/usr/bin/env bash

# run_gate.sh — v2 新增的质量门禁执行器。
# 从 04-acceptance.md 读取 `- Validation Command:` 行（每行一条 shell 命令，
# 允许 `$(...)` 表达式），逐条执行；全部通过才放行提交。
# 设计意图：把「什么算验收通过」从人工打勾变成机器可判据（方案 B 的核心补强）。

set -euo pipefail

if [[ $# -ne 3 ]]; then
  printf 'usage: bash run_gate.sh <spec-id> <task-id> <acceptance-file>\n' >&2
  exit 1
fi

SPEC_ID="$1"
TASK_ID="$2"
ACC_FILE="$3"

[[ -f "$ACC_FILE" ]] || { printf 'error: acceptance file not found: %s\n' "$ACC_FILE" >&2; exit 1; }

# 提取 Validation Command 行（去掉行首 "- " 前缀）。
# 若文件存在 `### <task-id>` 分节（并行模式/多 task spec 推荐写法），只跑当前
# task 分节下的命令——并行子代理在隔离 worktree 里只产出自己 task 的产物，
# 混跑全部命令会因缺他人产物而必然失败。无分节时保持旧语义：跑全部命令。
extract_commands() {
  local acc_file="$1" task_id="$2"
  if grep -qE '^### ' "$acc_file"; then
    awk -v task="$task_id" '
      /^### / { in_task = ($0 ~ ("^### `?" task "`?[[:space:]]*$")) }
      in_task && /^- Validation Command:/ { print }
    ' "$acc_file"
  else
    grep -E '^- Validation Command:' "$acc_file"
  fi | sed -E 's/^- Validation Command:[[:space:]]*//' | sed -E 's/^`//; s/`$//'
}

mapfile -t commands < <(extract_commands "$ACC_FILE" "$TASK_ID")

if [[ ${#commands[@]} -eq 0 ]]; then
  printf 'gate: no Validation Command found for task %s in %s\n' "$TASK_ID" "$ACC_FILE"
  printf 'gate: degenerate check — requiring explicit YES in Final Decision\n'
  if grep -A1 '^## Final Decision' "$ACC_FILE" | grep -qiE 'yes'; then
    printf 'gate: PASS (degenerate, no machine criteria)\n'
    exit 0
  fi
  printf 'gate: FAIL — no Validation Command and no explicit YES decision\n' >&2
  exit 1
fi

fail_count=0
for cmd in "${commands[@]}"; do
  [[ -z "$cmd" ]] && continue
  printf 'gate: running: %s\n' "$cmd"
  if eval "$cmd" >/tmp/ai_gate_last_output.$$ 2>&1; then
    printf 'gate: PASS\n'
  else
    printf 'gate: FAIL — output tail:\n' >&2
    tail -n 20 /tmp/ai_gate_last_output.$$ >&2 || true
    fail_count=$((fail_count + 1))
  fi
  rm -f /tmp/ai_gate_last_output.$$
done

if [[ "$fail_count" -gt 0 ]]; then
  printf 'gate: %d command(s) failed for task %s\n' "$fail_count" "$TASK_ID" >&2
  exit 1
fi
printf 'gate: all validation commands passed for task %s (spec %s)\n' "$TASK_ID" "$SPEC_ID"
