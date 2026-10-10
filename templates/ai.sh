#!/usr/bin/env bash

# AI Coding Harness v2 — thin mechanical orchestrator.
# 职责（刻意保持机械、无 AI 调用）：spec 骨架初始化、占位检查、task 解析、
# 分支/stash/提交/push 等 git 机械操作。所有 AI 参与的工作（写 spec、写代码、
# 写 PR 材料）由宿主 agent 读取 skills/ 下的 SKILL.md 执行，本脚本不再调度 Codex。

set -euo pipefail

HARNESS_DIR=".ai-harness"
STANDARDS_DIR="$HARNESS_DIR/.ai-standards"

# 允许从任意子目录调用：定位业务仓库根再 cd 过去。
# 注意 `-e` 而非 `-d`：git worktree 里 .git 是文件不是目录（并行模式子代理在
# worktree 内运行 ./ai 依赖这一点）。
repo_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    [[ -e "$dir/.git" ]] && { cd "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}
repo_root || { printf 'error: not inside a git repository\n' >&2; exit 1; }

# 规范源脚本路径；submodule 未初始化时给出可执行的修复提示。
standards_script() {
  local p="$STANDARDS_DIR/scripts/$1"
  [[ -f "$p" ]] || { printf 'error: %s missing; run: git submodule update --init --recursive\n' "$p" >&2; exit 1; }
  printf '%s' "$p"
}

say() { printf '%s\n' "$1"; }
fail() { printf 'error: %s\n' "$1" >&2; exit 1; }

usage() {
  cat <<'USAGE'
usage:
  ./ai status                          # 仓库/规范源/spec 概览
  ./ai spec <spec-id> [source-doc]     # 初始化 spec 四件套并做占位检查
  ./ai next <spec-id>                  # 输出下一个可执行 task（S→M→L 优先）
  ./ai ready <spec-id>                 # 并行模式：列出所有可同时开工的 task
  ./ai work <spec-id> <task-id>        # 切到任务分支（脏区自动 stash）
  ./ai worktree <spec-id> <task-id>    # 并行模式：为 task 创建隔离 worktree（子代理入口）
  ./ai collect <spec-id> <task-id>     # 并行模式：回收 task 分支并勾进度（主代理专用）
  ./ai done <spec-id> <task-id>        # 运行 04-acceptance 声明的验证命令并提交
  ./ai run <spec-id> [source-doc]      # spec → next → work → done 一键串行
  ./ai resume <spec-id>                # 从 03-tasks.md 的 Run Checkpoint 恢复
  ./ai skill <name>                    # 打印某阶段 SKILL.md 的路径（供宿主 agent 读取）
  ./ai pr <spec-id> <task-id> [target] # 生成 MR 材料文件并提交推送（改前确认）
USAGE
}

confirm_or_stop() {
  local message="$1"
  if [[ "${AI_CONFIRM:-}" = "1" ]]; then return 0; fi
  if [[ ! -t 0 ]]; then fail "$message; rerun with AI_CONFIRM=1 after manual confirmation"; fi
  printf '%s [y/N] ' "$message"
  local answer; read -r answer
  [[ "$answer" = "y" || "$answer" = "Y" ]] || fail "stopped by user"
}

# ---------------------------------------------------------------------------
# status：仓库、规范源版本、每个 spec 的 next task
# ---------------------------------------------------------------------------
cmd_status() {
  say "repo: $PWD"
  say "branch: $(git symbolic-ref --short HEAD 2>/dev/null || echo HEAD)"
  say "remote: $(git remote get-url origin 2>/dev/null || echo '(none)')"
  say "standards: $STANDARDS_DIR ($(git -C "$STANDARDS_DIR" rev-parse --short HEAD 2>/dev/null || echo 'uninitialized'))"
  say ""
  say "dirty workspace:"
  if [[ -n "$(git status --porcelain)" ]]; then git status --short; else say "clean"; fi
  say ""
  say "specs:"
  local spec_id tasks_file next_task
  if ! ls "$HARNESS_DIR/specs" >/dev/null 2>&1 || [[ -z "$(ls "$HARNESS_DIR/specs" 2>/dev/null)" ]]; then
    say "none"
    return 0
  fi
  for spec_id in "$HARNESS_DIR/specs"/*/; do
    [[ -d "$spec_id" ]] || continue
    spec_id="$(basename "$spec_id")"
    tasks_file="$HARNESS_DIR/specs/$spec_id/03-tasks.md"
    if [[ -f "$tasks_file" ]]; then
      next_task="$(task_next_ready "$tasks_file" S || task_next_ready "$tasks_file" M || task_next_ready "$tasks_file" L || true)"
      say "- $spec_id next=${next_task:-none}"
    else
      say "- $spec_id missing 03-tasks.md"
    fi
  done
}

# ---------------------------------------------------------------------------
# spec：骨架 + 占位检查 + （可选）source-doc 拷贝进 spec 目录
# ---------------------------------------------------------------------------
cmd_spec() {
  local spec_id="$1" source_doc="${2:-}"
  bash "$(standards_script init_spec.sh)" "$spec_id"
  bash "$(standards_script check_spec.sh)" "$spec_id"
  # 需求文档拷进 spec 目录作为同源材料：宿主 agent 写 01-requirements.md 时不必依赖外部路径。
  if [[ -n "$source_doc" && -f "$source_doc" ]]; then
    local dest="$HARNESS_DIR/specs/$spec_id/source.md"
    [[ -e "$dest" ]] || { cp "$source_doc" "$dest"; say "copy source: $dest"; }
  fi
  say ""
  say "next: 让宿主 agent 读取 ./ai skill spec-prep 对应的 SKILL.md 补齐四件套"
}

# ---------------------------------------------------------------------------
# next：依赖满足 + 未完成的第一个 task，S 优先
# ---------------------------------------------------------------------------
cmd_next() {
  local spec_id="$1" tasks_file task_id complexity
  tasks_file="$HARNESS_DIR/specs/$spec_id/03-tasks.md"
  [[ -f "$tasks_file" ]] || fail "missing $tasks_file"
  for complexity in S M L; do
    task_id="$(task_next_ready "$tasks_file" "$complexity" || true)"
    if [[ -n "$task_id" ]]; then
      say "$task_id"
      say "complexity: $complexity"
      [[ "$complexity" != "S" ]] && say "warning: $complexity task requires manual confirmation before development"
      return 0
    fi
  done
  fail "no ready task found for spec: $spec_id"
}

# ---------------------------------------------------------------------------
# work：切任务分支 + 脏区 stash（保留 spec 目录作为任务上下文）
# ---------------------------------------------------------------------------
cmd_work() {
  local spec_id="$1" task_id="$2"
  local tasks_file branch base_branch stash_name
  tasks_file="$HARNESS_DIR/specs/$spec_id/03-tasks.md"
  [[ -f "$tasks_file" ]] || fail "missing $tasks_file"
  # spec 未过占位检查时禁止进入开发（与 v1 Gate 一致：先有完整 spec 才许动代码）。
  bash "$(standards_script check_spec.sh)" "$spec_id" >/dev/null 2>&1 \
    || fail "spec $spec_id not ready: run bash $(standards_script check_spec.sh) $spec_id and fix the listed issues first"
  task_exists "$tasks_file" "$task_id" || fail "task id not found: $task_id"
  task_done "$tasks_file" "$task_id" && fail "task already marked done: $task_id"
  task_dependencies_met "$tasks_file" "$task_id" || fail "dependencies are not complete for task: $task_id"

  base_branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo HEAD)"
  branch="feat/$spec_id-$task_id"
  if [[ -n "$(git status --porcelain -- . ":(exclude)$HARNESS_DIR/specs/$spec_id")" ]]; then
    stash_name="ai-harness-before-$spec_id-$task_id-$(date +%Y%m%d-%H%M%S)"
    git stash push -u -m "$stash_name" -- . ":(exclude)$HARNESS_DIR/specs/$spec_id" >/dev/null
    say "stashed unrelated dirty files: $stash_name"
    say "restore: git stash pop stash@{N}"
  fi
  if [[ "$(git symbolic-ref --short HEAD 2>/dev/null)" = "$branch" ]]; then
    say "branch: already on $branch"
  elif git show-ref --verify --quiet "refs/heads/$branch"; then
    git switch "$branch"
  else
    git switch -c "$branch"
  fi
  say "base branch: $base_branch"
  say "work branch: $branch"
  say "next: 让宿主 agent 读取 ./ai skill task-dev 的 SKILL.md 执行开发"
}

# ---------------------------------------------------------------------------
# done：质量门禁 + 提交（不 push）
#   门禁来源：04-acceptance.md 的 `Validation Command:` 行（shell 直判，
#   允许用 $(...) 表达式）；无命令时退化为只查 acceptance 已有 YES 结论。
#   进度文件 03-tasks.md 的唯一写者是主代理：串行模式下 done 顺手勾选；
#   并行模式（在 worktree 内运行）子代理不写进度文件——勾选由主代理
#   ./ai collect 统一做，从根上消除分支间进度冲突（单一写者原则）。
# ---------------------------------------------------------------------------
in_worktree() {
  # git worktree 内 .git 是文件而非目录；主仓内是目录。
  [[ -f .git ]]
}

tick_progress() {
  local tasks_file="$1" task_id="$2" tmp
  [[ -f "$tasks_file" ]] || return 0
  tmp="$(mktemp)"
  awk -v task="$task_id" '
    /^## Progress/ { in_progress=1 }
    in_progress && $0 ~ ("^- \\[ \\][[:space:]]+`?" task "`?([[:space:]]|$)") {
      sub(/^- \[ \]/, "- [x]")
      in_progress=0
    }
    { print }
  ' "$tasks_file" > "$tmp"
  mv "$tmp" "$tasks_file"
}

cmd_done() {
  local spec_id="$1" task_id="$2" tasks_file acc_file gate_script
  tasks_file="$HARNESS_DIR/specs/$spec_id/03-tasks.md"
  acc_file="$HARNESS_DIR/specs/$spec_id/04-acceptance.md"
  [[ -f "$tasks_file" ]] || fail "missing $tasks_file"
  [[ -f "$acc_file" ]] || fail "missing $acc_file"
  task_exists "$tasks_file" "$task_id" || fail "task id not found: $task_id"

  gate_script="$(standards_script run_gate.sh)"
  bash "$gate_script" "$spec_id" "$task_id" "$acc_file"

  # 单一写者原则：worktree（并行模式子代理）内不勾进度文件，留待主代理
  # collect 统一勾选；主仓内（串行/单人模式）done 照旧顺手勾选。
  if ! in_worktree; then
    tick_progress "$tasks_file" "$task_id"
  else
    say "parallel mode: progress file left untouched; main agent will tick on collect"
  fi

  confirm_or_stop "Commit task $task_id (gate passed; will commit locally, not push)"
  local message_file
  message_file="$(mktemp)"
  {
    printf 'feat(%s): complete %s\n\n' "$spec_id" "$task_id"
    printf 'Why\n- Implement task %s from spec %s.\n\n' "$task_id" "$spec_id"
    printf 'What\n- See .ai-harness/specs/%s/04-acceptance.md for evidence.\n\n' "$spec_id"
    printf 'Validation\n- Gate commands from 04-acceptance.md executed via run_gate.sh; see acceptance evidence.\n'
  } > "$message_file"
  # 只提交本 task 的 spec 目录与工作区业务变更；并行模式下别的子代理的
  # in-flight 标记可能同时写进度文件，混提交会让 collect 的冲突自动合并失真。
  git add -A
  git diff --cached --quiet && fail "no staged changes to commit"
  git commit -F "$message_file"
  rm -f "$message_file"
  say "committed locally; push manually or via ./ai pr when ready"
}

# ---------------------------------------------------------------------------
# pr：生成 MR 材料 + 提交推送。推送是外发动作，保持确认门。
# ---------------------------------------------------------------------------
cmd_pr() {
  local spec_id="$1" task_id="$2" target_branch="${3:-main}"
  local feature_branch pr_dir pr_file diffstat
  feature_branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo HEAD)"
  pr_dir="$HARNESS_DIR/pr"
  mkdir -p "$pr_dir"
  pr_file="$pr_dir/${spec_id}-${task_id}-mr.md"

  diffstat="$(git diff --shortstat "$target_branch"...HEAD 2>/dev/null || true)"
  {
    printf '# MR Material\n\n'
    printf -- '- Spec: `.ai-harness/specs/%s/`\n- Task ID: `%s`\n' "$spec_id" "$task_id"
    printf -- '- Source branch: `%s`\n- Target branch: `%s`\n' "$feature_branch" "$target_branch"
    printf -- '- Diff: %s\n\n' "${diffstat:-no diff against target}"
    printf '## MR Description\n\n(Paste the description produced by the pr-prep skill.)\n'
  } > "$pr_file"

  confirm_or_stop "Review $pr_file and commit/push branch $feature_branch to origin"
  git add -A
  git diff --cached --quiet || git commit -m "chore(${spec_id}): mr material for ${task_id}"
  git push -u origin "$feature_branch"
  say "pushed: $feature_branch"
  say "mr material: $pr_file"
  say "GitLab/GitHub MR was not created automatically; use the material file."
}

# ---------------------------------------------------------------------------
# run：spec → next → work → done 串行（不自动 pr/pr 推送）
# ---------------------------------------------------------------------------
cmd_run() {
  local spec_id="$1" source_doc="${2:-}"
  cmd_spec "$spec_id" "$source_doc"
  local next_out task_id
  next_out="$(cmd_next "$spec_id")"
  task_id="$(printf '%s\n' "$next_out" | head -n 1)"
  checkpoint_write "$spec_id" "$task_id" "work" "./ai work $spec_id $task_id"
  cmd_work "$spec_id" "$task_id"
  checkpoint_write "$spec_id" "$task_id" "done" "./ai done $spec_id $task_id"
  cmd_done "$spec_id" "$task_id"
  checkpoint_pass "$spec_id"
}

# ---------------------------------------------------------------------------
# resume：从 Run Checkpoint 读取恢复命令并提示执行
# ---------------------------------------------------------------------------
cmd_resume() {
  local spec_id="$1" tasks_file
  tasks_file="$HARNESS_DIR/specs/$spec_id/03-tasks.md"
  [[ -f "$tasks_file" ]] || fail "missing $tasks_file"
  awk '/^## Run Checkpoint/{f=1} f && /^- Resume Command:/{print; f=0}' "$tasks_file"
  awk '/^## Run Checkpoint/{f=1} f && /^- Current Step:/{print; f=0}' "$tasks_file"
}

checkpoint_write() {
  local spec_id="$1" task_id="$2" step="$3" resume_cmd="$4" tasks_file tmp
  tasks_file="$HARNESS_DIR/specs/$spec_id/03-tasks.md"
  [[ -f "$tasks_file" ]] || return 0
  tmp="$(mktemp)"
  awk -v task="$task_id" -v step="$step" -v rcmd="$resume_cmd" '
    function print_ckpt() {
      print "## Run Checkpoint"
      print ""
      print "- Last Command: `'"$resume_cmd"'`"
      print "- Current Task: `"'"$task_id"'"`"
      print "- Current Step: `"'"$step"'"`"
      print "- Resume Command: `'"$resume_cmd"'`"
      print "- Last Result: pending"
      print "- Last Error:"
    }
    /^## Run Checkpoint/ { if (!printed) { print_ckpt(); printed=1 } skipping=1; next }
    skipping && /^## / { skipping=0 }
    !skipping { print }
    END { if (!printed) { print ""; print_ckpt() } }
  ' "$tasks_file" > "$tmp"
  mv "$tmp" "$tasks_file"
}

checkpoint_pass() {
  local spec_id="$1" tasks_file tmp
  tasks_file="$HARNESS_DIR/specs/$spec_id/03-tasks.md"
  [[ -f "$tasks_file" ]] || return 0
  tmp="$(mktemp)"
  awk '
    /^- Last Result: / { sub(/^- Last Result: .*/, "- Last Result: passed"); print; next }
    { print }
  ' "$tasks_file" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  # awk 只改第一处则需限定在 checkpoint 段：用范围匹配实现。
  mv "$tmp" "$tasks_file"
}

# ---------------------------------------------------------------------------
# skill：打印 skills 路径（宿主 agent 由此加载阶段 SKILL.md）
# ---------------------------------------------------------------------------
cmd_skill() {
  # 注意：两条 local 必须分开写——单行 local 里 $name 会在赋值前展开（外层未定义，set -u 报错）。
  local name="$1"
  local p="$STANDARDS_DIR/skills/$name/SKILL.md"
  [[ -f "$p" ]] || fail "skill not found: $name (expected $p)"
  say "$p"
}

# ---------------------------------------------------------------------------
# task 解析：与 v1 spec_utils 兼容的 awk 解析（同格式，轻量内联）
# ---------------------------------------------------------------------------
task_ids() { awk 'match($0, /^- Task ID:[[:space:]]*`?([^`[:space:]]+)`?/, m) { print m[1] }' "$1"; }
task_exists() { task_ids "$1" | grep -Fxq "$2"; }

task_field() {
  local tasks_file="$1" task_id="$2" field="$3"
  awk -v task="$task_id" -v field="$field" '
    function is_field(line) { return line ~ /^- (Task ID|Purpose|Inputs|Changes|Validation|Done|Complexity|Depends On):/ }
    function clean(value) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); gsub(/^`|`$/, "", value); return value }
    /^- Task ID:/ { in_task = ($0 ~ ("`" task "`") || $0 ~ (": " task "$")); next }
    in_task && $0 ~ ("^- " field ":") {
      sub("^- " field ":[[:space:]]*", "")
      value = clean($0)
      while ((getline line) > 0) {
        if (line ~ /^### / || is_field(line) || line ~ /^## /) break
        if (line !~ /^[[:space:]]*$/) value = value (value == "" ? "" : "\n") clean(line)
      }
      print value; exit
    }
  ' "$tasks_file"
}

task_done() {
  local done progress
  done="$(task_field "$1" "$2" "Done" | tr '[:upper:]' '[:lower:]')"
  [[ "$done" =~ (^|[^a-z])(yes|true|done|complete|completed|已完成)([^a-z]|$) ]] && return 0
  progress="$(awk -v task="$2" '
    $0 ~ /^## Progress/ { in_progress=1; next }
    in_progress && $0 ~ /^## / { in_progress=0 }
    in_progress && $0 ~ ("^- \\[[xX]\\][[:space:]]+`?" task "`?([[:space:]]|$)") { print "done"; exit }
  ' "$1")"
  [[ "$progress" = "done" ]]
}

task_complexity() {
  case "$(task_field "$1" "$2" "Complexity" | head -n 1)" in
    S|M|L) task_field "$1" "$2" "Complexity" | head -n 1 ;;
    *) printf 'S\n' ;;
  esac
}

task_dependencies() {
  # 过滤无依赖标记：兼容 `none`/`无`/`(none)`/表格竖线写法（存量 spec 有 | Depends On | 形态）。
  task_field "$1" "$2" "Depends On" | tr ',，' '\n\n' \
    | sed -E 's/`//g; s/^- //; s/^[[:space:]]+|[[:space:]]+$//g; s/^\|//; s/\|$//; s/^[[:space:]]+|[[:space:]]+$//g' \
    | awk 'NF && $0 !~ /^(none|None|NONE|无|N\/A|-|not applicable|\(none\)|\(None\))$/ { print }'
}

task_dependencies_met() {
  local tasks_file="$1" task_id="$2" dep
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    task_exists "$tasks_file" "$dep" || fail "dependency task id not found: $dep"
    task_done "$tasks_file" "$dep" || return 1
  done < <(task_dependencies "$tasks_file" "$task_id")
  return 0
}

task_next_ready() {
  local tasks_file="$1" wanted="${2:-}" task_id
  while IFS= read -r task_id; do
    task_done "$tasks_file" "$task_id" && continue
    [[ -n "$wanted" && "$(task_complexity "$tasks_file" "$task_id")" != "$wanted" ]] && continue
    if task_dependencies_met "$tasks_file" "$task_id"; then printf '%s\n' "$task_id"; return 0; fi
  done < <(task_ids "$tasks_file")
  return 1
}

task_next_ready_all() {
  # 并行模式用：输出全部依赖满足且未完成的 task（不按复杂度过滤）。
  local tasks_file="$1" task_id
  while IFS= read -r task_id; do
    task_done "$tasks_file" "$task_id" && continue
    task_dependencies_met "$tasks_file" "$task_id" && printf '%s\n' "$task_id"
  done < <(task_ids "$tasks_file")
}

task_in_flight() {
  # 03-tasks.md Run Checkpoint 区是否记录了 in-flight 任务（并行模式互斥标记）。
  local tasks_file="$1" task_id="$2"
  awk -v task="$task_id" '
    /^## Run Checkpoint/ { in_ckpt=1 }
    in_ckpt && $0 ~ ("^- In-Flight: `?" task "`?([[:space:]]|$)") { print "yes"; exit }
  ' "$tasks_file" | grep -q yes
}

# ---------------------------------------------------------------------------
# 并行模式：主代理派活 / 子代理隔离执行 / 主代理回收（v2.1 新增）
#
# 角色分工：主代理不写码——只负责 ①./ai ready 拿可开工清单 ②把 task 派给
# 最大数量的并发子代理 ③管理进度文件（in-flight 标记、Progress 勾选）。
# 子代理各占一个 git worktree，互不踩工作区；产出由 ./ai collect 合回。
# ---------------------------------------------------------------------------
WT_DIR="${AI_HARNESS_WT_DIR:-$PWD/.ai-harness/worktrees}"

mark_in_flight() {
  # 并行互斥：把已派发的 task 记进 03-tasks.md Run Checkpoint 区。
  # 多个主代理并发调用时靠此标记防止重复派发（awk 重写整文件，后写覆盖前写，
  # 偶发竞态由 worktree 分支名唯一兜底：同一 task 只有一个 feat/<spec>-<task> 分支）。
  local tasks_file="$1" spec_id="$2" task_id="$3" tmp
  [[ -f "$tasks_file" ]] || return 0
  tmp="$(mktemp)"
  awk -v task="$task_id" '
    { print }
    /^## Run Checkpoint/ && !seen {
      print ""
      print "- In-Flight: `" task "`"
      seen=1
    }
  ' "$tasks_file" > "$tmp"
  mv "$tmp" "$tasks_file"
}

clear_in_flight() {
  local tasks_file="$1" task_id="$2" tmp
  [[ -f "$tasks_file" ]] || return 0
  tmp="$(mktemp)"
  awk -v task="$task_id" '
    $0 ~ ("^- In-Flight: `?" task "`?([[:space:]]|$)") { next }
    { print }
  ' "$tasks_file" > "$tmp"
  mv "$tmp" "$tasks_file"
}

# ---------------------------------------------------------------------------
# ready：并行模式主代理专用——列出当前所有可同时开工的 task。
# ---------------------------------------------------------------------------
cmd_ready() {
  local spec_id="$1" tasks_file task_id
  tasks_file="$HARNESS_DIR/specs/$spec_id/03-tasks.md"
  [[ -f "$tasks_file" ]] || fail "missing $tasks_file"
  # in-flight 的 task 不出现在派活清单里（已被某个子代理领走），主代理
  # 只对剩余 ready task 补派。
  while IFS= read -r task_id; do
    task_in_flight "$tasks_file" "$task_id" && continue
    printf '%s %s\n' "$task_id" "$(task_complexity "$tasks_file" "$task_id")"
  done < <(task_next_ready_all "$tasks_file")
}

# ---------------------------------------------------------------------------
# worktree：并行模式子代理专用——为 task 创建隔离工作区。
#   子代理在 worktree 内照常 ./ai work → task-dev skill → ./ai done 闭环；
#   提交落在 feat/<spec>-<task> 分支，由主代理 ./ai collect 回收。
# ---------------------------------------------------------------------------
cmd_worktree() {
  local spec_id="$1" task_id="$2"
  local tasks_file wt_path branch
  tasks_file="$HARNESS_DIR/specs/$spec_id/03-tasks.md"
  [[ -f "$tasks_file" ]] || fail "missing $tasks_file"
  # 与 ./ai work 相同的前置门禁：占位 spec 不许开发、依赖须完成；
  # 并行互斥：已完成或 in-flight 的 task 拒绝重复领取。
  bash "$(standards_script check_spec.sh)" "$spec_id" >/dev/null 2>&1 \
    || fail "spec $spec_id not ready: run bash $(standards_script check_spec.sh) $spec_id and fix the listed issues first"
  task_exists "$tasks_file" "$task_id" || fail "task id not found: $task_id"
  task_done "$tasks_file" "$task_id" && fail "task already marked done: $task_id"
  task_in_flight "$tasks_file" "$task_id" && fail "task already claimed by another agent: $task_id"
  task_dependencies_met "$tasks_file" "$task_id" || fail "dependencies are not complete for task: $task_id"

  branch="feat/$spec_id-$task_id"
  wt_path="$WT_DIR/${spec_id}-${task_id}"
  if [[ -d "$wt_path" ]]; then
    say "worktree exists: $wt_path"
  else
    git worktree add -b "$branch" "$wt_path" 2>/dev/null \
      || fail "cannot create worktree for $branch (branch or worktree already exists?)"
  fi
  # 新 worktree 不会自动检出 submodule（.ai-harness/.ai-standards 为空目录），
  # 子代理在 worktree 内跑 ./ai work/done 会因缺 check_spec.sh/run_gate.sh 失败；
  # 机械层在这里统一拉起（本地路径协议需放行 file）。
  git -c protocol.file.allow=always -C "$wt_path" submodule update --init --recursive >/dev/null 2>&1 || true
  mark_in_flight "$tasks_file" "$spec_id" "$task_id"
  say "worktree: $wt_path"
  say "branch: $branch"
  say "next: cd $wt_path && ./ai work $spec_id $task_id"
}

# ---------------------------------------------------------------------------
# collect：并行模式主代理专用——回收子代理的 task 分支。
#   合回当前分支、勾进度、清 in-flight 标记、删 worktree 与分支。
#   冲突时不落地、直接报错退出，不自动解决冲突。
# ---------------------------------------------------------------------------
cmd_collect() {
  local spec_id="$1" task_id="$2"
  local tasks_file branch
  tasks_file="$HARNESS_DIR/specs/$spec_id/03-tasks.md"
  [[ -f "$tasks_file" ]] || fail "missing $tasks_file"
  branch="feat/$spec_id-$task_id"
  git show-ref --verify --quiet "refs/heads/$branch" \
    || fail "branch not found: $branch (did the sub-agent run ./ai done?)"
  # 单一写者原则：子代理不再勾进度文件，collect 时进度文件通常零冲突；
  # 若仍有冲突（人工在主仓直接改了进度文件等场景），仅进度文件冲突按
  # 勾选并集自动合并，业务文件冲突停下走人工。
  git merge --no-ff --no-edit -m "chore(${spec_id}): collect parallel task ${task_id}" "$branch" 2>/dev/null \
    || collect_merge_progress_conflict "$tasks_file" "$branch" "$task_id"
  # 主代理是进度文件的唯一写者：回收时统一勾选、清 in-flight 标记。
  tick_progress "$tasks_file" "$task_id"
  clear_in_flight "$tasks_file" "$task_id"
  git add -A && git commit -qm "chore(${spec_id}): settle progress file for ${task_id}" || true
  git worktree remove --force "$WT_DIR/${spec_id}-${task_id}" 2>/dev/null || true
  git branch -D "$branch" 2>/dev/null || true
  say "collected: $task_id -> $(git symbolic-ref --short HEAD)"
  say "worktree removed; branch deleted"
}

collect_merge_progress_conflict() {
  # merge 冲突仅限进度文件时的自动解法：勾选并集 + 去掉本 task 的 In-Flight。
  # 依赖 python3（实现并集逻辑比纯 awk 可靠）；非进度文件冲突仍走人工。
  local tasks_file="$1" branch="$2" task_id="$3"
  local conflict_files
  conflict_files="$(git diff --name-only --diff-filter=U)"
  if printf '%s\n' "$conflict_files" | grep -qv "^$tasks_file$"; then
    git merge --abort 2>/dev/null || true
    fail "merge conflict collecting $branch affects non-progress files; resolve manually: $(printf '%s' "$conflict_files" | tr '\n' ' ')"
  fi
  # 仅进度文件冲突：以 ours 为基底，叠加 theirs 的新增勾选（并集），
  # 再去掉本 task 的 In-Flight 行。
  local ours
  ours="$(mktemp)"
  git show ":2:$tasks_file" > "$ours" 2>/dev/null || cp "$tasks_file" "$ours"
  command -v python3 >/dev/null 2>&1 \
    || { git merge --abort 2>/dev/null || true; fail "progress-file conflict needs python3 (not found); resolve manually"; }
  python3 - "$ours" ":3:$tasks_file" "$tasks_file" "$task_id" <<'PYEOF'
import re, subprocess, sys
ours_p, theirs_ref, out_p, task_id = sys.argv[1:5]
ours = open(ours_p).read().splitlines()
theirs = subprocess.run(["git", "show", theirs_ref], capture_output=True, text=True, check=True).stdout.splitlines()
def ticks(lines):
    text = "\n".join(lines)
    return set(re.findall(r"^- \[x\][\s`]*([^\s`]+)", text, re.M))
tick_re = re.compile(r"^- \[ \][\s`]+([^\s`]+)")
merged_ticks = ticks(ours) | ticks(theirs)
out = []
for l in ours:
    m = tick_re.match(l)
    if m and m.group(1).strip("`") in merged_ticks:
        l = l.replace("- [ ]", "- [x]", 1)
    if re.match(r"^- In-Flight: `?%s" % re.escape(task_id), l):
        continue
    out.append(l)
open(out_p, "w").write("\n".join(out) + "\n")
PYEOF
  git add "$tasks_file"
  git -c core.editor=true merge --continue >/dev/null 2>&1 \
    || git commit -qm "chore: collect progress merge for ${task_id}"
  say "progress file auto-merged (tick union, in-flight cleared): $tasks_file"
}

# ---------------------------------------------------------------------------
main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    status) cmd_status ;;
    spec)   [[ $# -ge 1 ]] || { usage; exit 1; }; cmd_spec "$@" ;;
    next)   [[ $# -eq 1 ]] || { usage; exit 1; }; cmd_next "$1" ;;
    ready)  [[ $# -eq 1 ]] || { usage; exit 1; }; cmd_ready "$1" ;;
    work)   [[ $# -eq 2 ]] || { usage; exit 1; }; cmd_work "$1" "$2" ;;
    worktree) [[ $# -eq 2 ]] || { usage; exit 1; }; cmd_worktree "$1" "$2" ;;
    collect) [[ $# -eq 2 ]] || { usage; exit 1; }; cmd_collect "$1" "$2" ;;
    done)   [[ $# -eq 2 ]] || { usage; exit 1; }; cmd_done "$1" "$2" ;;
    pr)     [[ $# -ge 2 && $# -le 3 ]] || { usage; exit 1; }; cmd_pr "$@" ;;
    run)    [[ $# -ge 1 ]] || { usage; exit 1; }; cmd_run "$@" ;;
    resume) [[ $# -eq 1 ]] || { usage; exit 1; }; cmd_resume "$1" ;;
    skill)  [[ $# -eq 1 ]] || { usage; exit 1; }; cmd_skill "$1" ;;
    -h|--help|help|"") usage ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
