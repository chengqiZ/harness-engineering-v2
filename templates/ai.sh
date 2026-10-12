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
  ./ai unclaim <spec-id> <task-id>     # 并行模式：释放被领取的 task（阵亡重派前清尸体）
  ./ai done <spec-id> <task-id>        # 运行 04-acceptance 声明的验证命令并提交
  ./ai run <spec-id> [source-doc]      # spec → next → work → done 一键串行
  ./ai resume <spec-id>                # 从 03-tasks.md 的 Run Checkpoint 恢复
  ./ai skill <name>                    # 打印某阶段 SKILL.md 的路径（供宿主 agent 读取）
  ./ai pr <spec-id> <task-id> [target] # 生成 MR 材料文件并提交推送（改前确认）
  ./ai report <spec-id> <task-id> [target] # collect 后生成 MR 材料（并行模式收尾）
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
  # 与 ./ai ready 对齐：in-flight 的 task 不派发（已被并行子代理领走）。
  # 早期 next 不过滤 in-flight，与 ready 互相矛盾——主代理若按 next 派活
  # 会重复派发已领走的 task（实测实锤：阵亡重派场景死锁放大）。
  for complexity in S M L; do
    task_id="$(task_next_ready "$tasks_file" "$complexity" || true)"
    if [[ -n "$task_id" ]] && ! task_in_flight "$tasks_file" "$task_id"; then
      say "$task_id"
      say "complexity: $complexity"
      [[ "$complexity" != "S" ]] && say "warning: $complexity task requires manual confirmation before development"
      return 0
    fi
  done
  # 还有未完成任务却无 ready task 时，最常见的根因是依赖成环/悬空——
  # check_spec 能点名，提示排查路径而不是让用户对着「no ready task」发呆。
  fail "no ready task found for spec: $spec_id; if tasks are still open, run: bash .ai-harness/.ai-standards/scripts/check_spec.sh $spec_id (detects dependency cycles and dangling ids)"
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
  task_dependencies_met "$tasks_file" "$task_id" "$spec_id" || fail "dependencies are not complete for task: $task_id"
  # v2.1.2 依赖判定已放宽：勾选未进当前分支但依赖任务的 feat 分支存在时放行。
  # 若依赖分支只是存在而 work 入口被拒，提示里给出 stacked 语义的出路。
  task_exists "$tasks_file" "$task_id" || fail "task id not found: $task_id"
  task_done "$tasks_file" "$task_id" && fail "task already marked done: $task_id"

  base_branch="${AI_HARNESS_BASE_BRANCH:-main}"
  branch="feat/$spec_id-$task_id"
  # v2.1.2：一任务一 PR——base 不再取「当前分支」，改为按依赖判定：
  # - 无依赖任务从 base 分支（默认 main）建：早期取当前分支时串行 T2 从
  #   feat-T1 建，T2 的 PR 永远夹带 T1 的提交，「一任务一 PR」名存实亡。
  # - 依赖任务链在依赖的 feat 分支上（业界 stacked-PR 形态：每层 PR 只含
  #   增量，评审面积正确；T2 的 PR target 写 feat-T1）。
  # - 多个依赖各有 feat 分支时，base 取最后一个、其余 merge 进来（冲突即停，
  #   不自动解决）；依赖已 collect 进 base（分支已删）则天然包含。
  local dep dep_base merge_deps=()
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    if git show-ref --verify --quiet "refs/heads/feat/$spec_id-$dep"; then
      dep_base="feat/$spec_id-$dep"
      merge_deps+=("$dep_base")
    fi
  done < <(task_dependencies "$tasks_file" "$task_id")
  if [[ -n "${dep_base:-}" ]]; then
    base_branch="$dep_base"
  fi
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
    git switch -c "$branch" "$base_branch"
    # 多父依赖：其余依赖分支逐个 merge 进来（一般 0~1 个额外）；冲突即停，
    # 不自动解决——与 collect 的冲突纪律一致。
    for dep in "${merge_deps[@]:-${dep_base:-}}"; do
      [[ -z "$dep" || "$dep" = "$base_branch" ]] && continue
      # 依赖分支各自改进度文件（勾自己），双依赖 merge 必然在 03-tasks.md 撞车：
      # 冲突仅限进度文件时按勾选并集自动合并（与 collect 同策略）；其他文件冲突停下走人工。
      if ! git merge --no-edit "$dep" >/dev/null 2>&1; then
        local conflict_files
        conflict_files="$(git diff --name-only --diff-filter=U)"
        if printf '%s\n' "$conflict_files" | grep -qv "^$tasks_file$"; then
          git merge --abort >/dev/null 2>&1 || true
          fail "merge of dependency branch $dep into $branch conflicts on non-progress files; resolve manually and re-run"
        fi
        printf '%s\n' "$conflict_files" | grep -q "^$tasks_file$" \
          || fail "merge of dependency branch $dep into $branch conflicts; resolve manually and re-run"
        merge_progress_union "$tasks_file" "$dep" || { git merge --abort >/dev/null 2>&1 || true; fail "progress union merge failed for $dep; resolve manually"; }
        git add "$tasks_file"
        git -c core.editor=true merge --continue >/dev/null 2>&1 \
          || git commit -qm "chore: merge dependency branch $dep (progress union)" \
          || true
      fi
    done
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
      sub(/^- \\[ \\]/, "- [x]")
      in_progress=0
    }
    { print }
  ' "$tasks_file" > "$tmp"
  mv "$tmp" "$tasks_file"
}

# 进度文件勾选并集（work 的双依赖 merge 冲突时用，与 collect 同策略）：
# 以当前分支版本为基底，叠加被合分支的新增勾选；In-Flight 标记取并集。
merge_progress_union() {
  local tasks_file="$1" dep_branch="$2"
  command -v python3 >/dev/null 2>&1 || return 1
  local ours
  ours="$(mktemp)"
  git show ":2:$tasks_file" > "$ours" 2>/dev/null || return 1
  python3 - "$ours" "$tasks_file" "$dep_branch" <<'PYEOF'
import re, subprocess, sys
ours_p, tasks_p, dep_branch = sys.argv[1:4]
ours = open(ours_p).read().splitlines()
theirs = subprocess.run(["git", "show", f"{dep_branch}:{tasks_p}"], capture_output=True, text=True).stdout.splitlines()
def ticks(lines):
    return set(re.findall(r"^- \[x\][\s`]*([^\s`]+)", "\n".join(lines), re.M))
merged = ticks(ours) | ticks(theirs)
out = []
for l in ours:
    m = re.match(r"^- \[ \][\s`]+([^\s`]+)", l)
    if m and m.group(1).strip("`") in merged:
        l = l.replace("- [ ]", "- [x]", 1)
    out.append(l)
open(tasks_p, "w").write("\n".join(out) + "\n")
PYEOF
}

cmd_done() {
  local spec_id="$1" task_id="$2" tasks_file acc_file gate_script
  tasks_file="$HARNESS_DIR/specs/$spec_id/03-tasks.md"
  acc_file="$HARNESS_DIR/specs/$spec_id/04-acceptance.md"
  [[ -f "$tasks_file" ]] || fail "missing $tasks_file"
  [[ -f "$acc_file" ]] || fail "missing $acc_file"
  task_exists "$tasks_file" "$task_id" || fail "task id not found: $task_id"

  # 冲突残留守卫：work 的依赖 merge 冲突（或其他来源的冲突状态）未解决时，
  # add -A 会把冲突标记直接提交进分支（实测实锤：T4 双依赖冲突后 done 把
  # <<<<<<< ======= >>>>>>> 提交进了 feat 分支）。门禁前先拒绝。
  [[ -z "$(git ls-files -u | head -1)" ]] \
    || fail "unresolved merge conflicts in workspace (git ls-files -u non-empty); resolve before ./ai done"

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
  # pr 必须在任务分支上执行：在 main/detached 上误跑会生成 Source=Target 的废材料，
  # 且把 MR 材料提交进目标分支本身。
  local expected_branch="feat/$spec_id-$task_id"
  if [[ "$feature_branch" != "$expected_branch" ]]; then
    fail "not on task branch: expected $expected_branch, current is $feature_branch; switch and retry (after collect in parallel mode, use ./ai pr on the collected main instead of running it inside a worktree)"
  fi
  # target 分支拼错（如 mian）没人拦：材料里 Target 写着错字照样推送，
  # 开 MR 的人照着错字开分支。本地或远端存在性都认。
  git show-ref --verify --quiet "refs/heads/$target_branch" \
    || git ls-remote --exit-code --heads origin "$target_branch" >/dev/null 2>&1 \
    || fail "target branch not found locally or on origin: $target_branch (typo?)"
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
  # push 是外发动作：失败必须显式失败（set -e 会中断，这里补一句可读错误提示）。
  git push -u origin "$feature_branch" \
    || fail "push failed for $feature_branch (remote/permissions?); MR material kept at $pr_file"
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
  local next_out task_id tasks_file complexity
  next_out="$(cmd_next "$spec_id")"
  task_id="$(printf '%s\n' "$next_out" | head -n 1)"
  tasks_file="$HARNESS_DIR/specs/$spec_id/03-tasks.md"
  complexity="$(task_complexity "$tasks_file" "$task_id")"
  # 一键串行不旁路风险分级：M/L 任务要求人工确认后才能自动推进。
  # AI_CONFIRM=1 只豁免「已完成人工评审」的交互确认门，不豁免本门——
  # M/L 的确认点在「看设计、定影响面」，属于 never-skip 类（见 serial-task SKILL）。
  if [[ "$complexity" != "S" && "${AI_RUN_ALLOW_ML:-}" != "1" ]]; then
    checkpoint_write "$spec_id" "$task_id" "work" "./ai work $spec_id $task_id"
    fail "run stopped: task $task_id is $complexity; review 02-design.md, then run './ai work $spec_id $task_id' manually (or export AI_RUN_ALLOW_ML=1 to override)"
  fi
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
  # 注意 awk 程序体必须整体单引号：早期版本在单双引号间穿插 bash 展开，
  # Current Task/Current Step 被展开成空值写进进度文件，resume 恢复时拿不到任务号。
  # 值一律走 -v 传入（awk 内用反引号字面量拼接，不再靠 shell 展开注入）。
  awk -v task="$task_id" -v step="$step" -v rcmd="$resume_cmd" '
    function print_ckpt() {
      print "## Run Checkpoint"
      print ""
      print "- Last Command: `" rcmd "`"
      print "- Current Task: `" task "`"
      print "- Current Step: `" step "`"
      print "- Resume Command: `" rcmd "`"
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
  # 完成判定的唯一权威：## Progress 区的 [x] 勾选（由 done/collect 机械回写）。
  # Done: 字段是「完成判据描述」（如「脚本幂等」），语义上不是完成声明——
  # 早期版本把含 yes/已完成 等词的 Done 描述误判为已完成，导致未干任务被跳过。
  local progress
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
  # v2.1.2：spec_id 由调用方传入（依赖放宽判定需要探测 feat 分支是否已存在）。
  local tasks_file="$1" task_id="$2" spec_id="${3:-}" dep
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    task_exists "$tasks_file" "$dep" || fail "dependency task id not found: $dep"
    task_done "$tasks_file" "$dep" && continue
    # v2.1.2 放宽：勾选未进当前分支但依赖任务的 feat 分支已存在（串行 stacked
    # 形态：done 的勾选提交落在 feat/<spec>-<dep> 上，还没合回 base）。
    # 分支存在=依赖已闭环过门禁，放行并让 work 把它 merge 进新分支。
    [[ -n "$spec_id" ]] && git show-ref --verify --quiet "refs/heads/feat/$spec_id-$dep" && continue
    return 1
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
# unclaim：主代理专用——释放被领取的 task（子代理阵亡/中断重派前清尸体）。
#   只清 in-flight 标记，不动分支与 worktree（尸体清理由调用方按需做）；
#   task 已完成时拒绝（应走 collect，而不是 unclaim）。
# ---------------------------------------------------------------------------
cmd_unclaim() {
  local spec_id="$1" task_id="$2"
  local tasks_file
  tasks_file="$HARNESS_DIR/specs/$spec_id/03-tasks.md"
  [[ -f "$tasks_file" ]] || fail "missing $tasks_file"
  task_exists "$tasks_file" "$task_id" || fail "task id not found: $task_id"
  task_done "$tasks_file" "$task_id" && fail "task already done: $task_id (collect it instead)"
  task_in_flight "$tasks_file" "$task_id" \
    || fail "task not in-flight: $task_id (nothing to release)"
  clear_in_flight "$tasks_file" "$task_id"
  say "released: $task_id is claimable again"
  say "hint: remove leftover worktree/branch manually if the sub-agent died: git worktree remove --force $WT_DIR/${spec_id}-${task_id}; git branch -D feat/$spec_id-$task_id"
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
  # v2.1.2：worktree 从上次提交建，主仓未提交的 spec 进不去——子代理会因
  # missing 03-tasks.md 盲跑（实测实锤）。派发前 spec 必须干净且已提交。
  local spec_uncommitted
  spec_uncommitted="$(git status --porcelain -- "$HARNESS_DIR/specs/$spec_id" | head -1)"
  if [[ -n "$spec_uncommitted" ]]; then
    fail "spec $spec_id has uncommitted changes (worktree is created from the last commit, the sub-agent would miss them); commit the spec first: git add $HARNESS_DIR/specs/$spec_id && git commit"
  fi
  # 与 ./ai work 相同的前置门禁：占位 spec 不许开发、依赖须完成；
  # 并行互斥：已完成或 in-flight 的 task 拒绝重复领取。
  bash "$(standards_script check_spec.sh)" "$spec_id" >/dev/null 2>&1 \
    || fail "spec $spec_id not ready: run bash $(standards_script check_spec.sh) $spec_id and fix the listed issues first"
  task_exists "$tasks_file" "$task_id" || fail "task id not found: $task_id"
  task_done "$tasks_file" "$task_id" && fail "task already marked done: $task_id"
  task_in_flight "$tasks_file" "$task_id" && fail "task already claimed by another agent: $task_id"
  task_dependencies_met "$tasks_file" "$task_id" "$spec_id" || fail "dependencies are not complete for task: $task_id"

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
  # 领取标记必须随提交落盘：留在工作区会污染后续任务分支（task_done 的
  # add -A 不区分 spec 内文件，标记会被捎带进子代理提交）。
  git add "$tasks_file" && git commit -qm "chore(${spec_id}): claim task ${task_id} (in-flight)" \
    || say "note: claim commit skipped (nothing to commit)"
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
  # collect 只属于主代理、只在主仓执行：在 worktree 内误跑会把 task 分支合进
  # 子代理分支而非目标分支（e2e 实测过此事故形态）。
  if in_worktree; then
    fail "collect must run in the main repository, not inside a worktree; cd <repo-root> first"
  fi
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
# report：collect 后生成 PR 材料（并行模式收尾专用）。
#   collect 已把 task 分支合进当前分支并删除分支，此时 ./ai pr 因「不在任务
#   分支上」被拒——并行模式的 PR 材料由本命令从 collect 提交反推：
#   source=当前分支、diff=该 task 的 collect 合并提交（--first-parent 视角）。
# ---------------------------------------------------------------------------
cmd_report() {
  local spec_id="$1" task_id="$2" target_branch="${3:-main}"
  local current_branch merge_commit diffstat pr_dir pr_file
  current_branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo HEAD)"
  [[ "$current_branch" != "$target_branch" ]] \
    || fail "already on target branch $target_branch; nothing to report — push directly: git push origin $target_branch"
  # 找该 task 的 collect 合并提交（chore(<spec>): collect parallel task <task>）
  merge_commit="$(git log --first-parent --grep="chore(${spec_id}): collect parallel task ${task_id}\$" -n1 --format=%H || true)"
  [[ -n "$merge_commit" ]] \
    || fail "no collect commit found for $task_id (collect runs: chore(${spec_id}): collect parallel task ${task_id}); did you run ./ai collect?"
  diffstat="$(git show --first-parent --shortstat --format= "$merge_commit" 2>/dev/null | head -1)"
  pr_dir="$HARNESS_DIR/pr"
  mkdir -p "$pr_dir"
  pr_file="$pr_dir/${spec_id}-${task_id}-mr.md"
  {
    printf '# MR Material (collected)\n\n'
    printf -- '- Spec: `.ai-harness/specs/%s/`\n- Task ID: `%s`\n' "$spec_id" "$task_id"
    printf -- '- Source branch: `%s` (task branch collected via merge %s)\n' "$current_branch" "$(git rev-parse --short "$merge_commit")"
    printf -- '- Target branch: `%s`\n' "$target_branch"
    printf -- '- Diff (this task only): %s\n\n' "${diffstat:-no diff}"
    printf '## MR Description\n\n(Paste the description produced by the pr-prep skill.)\n'
    printf '## Merge Commit\n\n%s\n\n' "$(git show --no-patch --format='%h %s' "$merge_commit")"
    printf '## Task-level Validation Evidence\n\nSee .ai-harness/specs/%s/04-acceptance.md and .gate-log/\n' "$spec_id"
  } > "$pr_file"
  say "mr material: $pr_file"
  say "next: push $current_branch and open MR into $target_branch using the material file"
  say "note: GitLab/GitHub MR was not created automatically; use the material file."
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
    unclaim) [[ $# -eq 2 ]] || { usage; exit 1; }; cmd_unclaim "$1" "$2" ;;
    report) [[ $# -ge 2 && $# -le 3 ]] || { usage; exit 1; }; cmd_report "$@" ;;
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
