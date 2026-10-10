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
mapfile -t commands < <(grep -E '^- Validation Command:' "$ACC_FILE" | sed -E 's/^- Validation Command:[[:space:]]*//' | sed -E 's/^`//; s/`$//')

if [[ ${#commands[@]} -eq 0 ]]; then
  printf 'gate: no Validation Command found in %s\n' "$ACC_FILE"
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
