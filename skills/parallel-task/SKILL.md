---
name: parallel-task
description: "Use when a host agent drives maximum-concurrency sub-agents on one spec. The main agent only dispatches tasks and manages the progress file; each sub-agent develops one task in its own git worktree (ready → worktree → task-dev → done → collect)."
---

# 并行任务执行（主代理 + 最大并发子代理）

适用：宿主 agent 具备「子代理/并行会话」能力（Claude Code subagents、Codex 多实例、Hermes delegate_task、内部编排器等）。串行模式见 serial-task skill；本 skill 是它的并行版。

**并发上限：默认 10 个子代理同时跑**（可用 `AI_HARNESS_MAX_SUBAGENTS` 覆盖）。宿主平台自身上限低于此值时以平台为准。

## 角色分工（硬性）

主代理**不写码、不跑门禁**，只做三件事：

1. **派活**：`./ai ready <spec-id>` 拿可开工清单，把每个 task 派给一个子代理，并发开满到上限（默认 10，见文首；不为省事人为限速）。
2. **进度管理**：03-tasks.md 是唯一进度源（in-flight 标记 + Progress 勾选），主代理负责回收后统一勾选，禁止子代理互相改进度。
3. **回收**：子代理 done 后，主代理 `./ai collect <spec-id> <task-id>` 合分支、清 worktree；每回收一批就重跑 `./ai ready` 把刚解锁的任务立即补派，始终保持并发池满载。

子代理只做一件事：在自己分到的 worktree 里按 task-dev skill 完成一个 task 的闭环（实现 → 验证 → `AI_CONFIRM=1 ./ai done`）。

## 机械层命令（并行模式新增三个）

```bash
./ai ready <spec-id>                # 主代理：所有依赖满足、未完成、未派发的 task
./ai worktree <spec-id> <task-id>   # 子代理入口：创建隔离 worktree + feat/<spec>-<task> 分支
./ai collect <spec-id> <task-id>    # 主代理：合并回当前分支、勾进度、删 worktree 和分支
```

worktree 落在 `.ai-harness/worktrees/<spec>-<task>`（可用 `AI_HARNESS_WT_DIR` 重定向）。子代理在 worktree 内照常 `./ai work` → task-dev skill → `./ai done`，与串行流程完全一致。

## 主代理执行循环

1. 启动检查（与 serial-task 相同：仓库根、submodule、AGENTS/standards、git status）。
2. spec 不存在 → 先走 spec-prep；spec 未过 check_spec → 停，先补 spec。
3. `./ai ready <spec-id>` 取清单。空清单且全部完成 → 收尾出总报告。
4. 对清单里的每个 task 派一个子代理（并发开满），子代理提示词模板：

```text
请读取 <业务仓库根>/.ai-harness/.ai-standards/skills/task-dev/SKILL.md。
先执行 AI_CONFIRM=1 ./ai worktree <spec-id> <task-id> 创建你的隔离工作区，
然后 cd 到输出的 worktree 路径，执行 ./ai work <spec-id> <task-id>，
按 task-dev skill 完成 <task-id> 的实现与验证，
最后 AI_CONFIRM=1 ./ai done <spec-id> <task-id> 过门禁并提交。
不要编辑 .ai-harness/specs/<spec-id>/03-tasks.md（进度文件由主代理统一管理），
只做这一个 task，不要动其他文件，完成后报告 task-id、分支名、验证证据。
```

5. 子代理陆续完成后（每次回收一个）：
   - `./ai collect <spec-id> <task-id>`；冲突时停下报告，不自动解决。
   - 回收后重跑 `./ai ready`——新 task 的依赖可能刚被解锁，继续派发。
6. 所有 task 完成后：汇总每个 task 的 task-id、验证证据、diffstat，输出总报告（含 risks、rollback、pending items）；人工评审统一在 push 前（`./ai pr` 确认门），不是逐 task 评审。

# 派发纪律

- 依赖未满足的 task 不派（`./ai ready` 已过滤）；依赖被回收解锁的新 task 及时补派。
- 同一 task 只派一个子代理（`./ai worktree` 的 in-flight 标记拒绝重复领取）。
- **进度文件 03-tasks.md 只有主代理写**：子代理的 `./ai done` 在 worktree 内不会勾选 Progress（单一写者原则）；勾选和 in-flight 清理都发生在主代理 `./ai collect` 时。子代理也不要手动编辑 03-tasks.md。
- M/L 或高风险 task（DB migration、auth/权限、billing、风控、共享核心组件）**不进并发池**：降级为串行 + 每步人工确认（走 serial-task）。
- 子代理阵亡零产出 → 主代理重派前先清尸体：`git worktree remove --force` + 删除对应分支，再 `./ai worktree` 重建。
- 验证/门禁失败的 task：主代理不接管修码，选择「带错误反馈重派子代理」或「升级人工」。

## 禁止

- 主代理自己写码、自己跑门禁（分工就是派活 + 进度管理）
- 多个 task-id 混进一个分支/PR
- 并发收集时自动解决业务文件冲突（必须停下人工裁决）
- 子代理写进度文件（勾 Progress、改 In-Flight 都不行——03-tasks.md 由主代理在 collect 时统一更新）
- 破坏性命令（人工确认前）

## 完成输出

总报告：spec link、每个 task 的（task id、worktree 分支、changed files、test evidence）、collect 顺序、risks、rollback plan、pending items、是否建议继续 YES/NO + 原因。
