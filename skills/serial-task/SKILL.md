---
name: serial-task
description: "Use when a host agent (Claude Code, Codex, OpenClaw, Gemini CLI, etc.) with repo read/write ability drives multiple tasks of one spec in dependency order. One task-id per loop: read card, implement, validate, update acceptance, pause."
---

# 串行任务执行（宿主 agent 通用）

适用：Claude Code、Codex、OpenClaw、Gemini CLI、Copilot CLI、内部 AI 程序等具备仓库读写能力的宿主 agent。不依赖 `./ai` 的调度；机械步骤（分支/stash/提交）可以直接用 `./ai work` / `./ai done`。

执行模式（二选一，由提示词声明，默认 `step-confirm`）：

- `step-confirm`：每个 task 闭环后暂停，等人工确认再继续（适合首次接入、高风险 spec）。
- `full-auto`：全程不暂停，串行跑完所有 ready task（见下方「full-auto 模式」）。声明方式：提示词明确写「full-auto 执行」；机械层命令统一带 `AI_CONFIRM=1` 前缀（如 `AI_CONFIRM=1 ./ai done <spec> <task>`），跳过交互确认门。

## 启动检查

1. 确认在业务仓库根目录
2. `.ai-harness/.ai-standards` 存在（submodule 已初始化）
3. 读 `.ai-harness/AGENTS.md`（项目特例）与 `.ai-harness/.ai-standards/AGENTS.md`、`standards/*.md`
4. 检查 `git status`，工作区含无关脏文件时先报告
5. 确认目标 spec 目录存在；不存在则先走 spec-prep skill

## 执行循环

1. `./ai next <spec-id>` 取下一个 ready task（或人工指定 task-id）
2. `./ai work <spec-id> <task-id>` 切任务分支（脚本会 stash 无关脏区）
3. 按 task-dev skill 的规则实现 + 验证 + 更新 04-acceptance
4. `AI_CONFIRM=1 ./ai done <spec-id> <task-id>` 跑质量门禁并本地提交（两种模式都自动提交，不在此处等人）
5. 输出任务闭环摘要；`step-confirm` 模式下暂停等待人工确认是否继续下一个 task，`full-auto` 模式下直接进入下一个 task

## 评审时机（两种模式一致）

- 提交是机械动作：门禁（Validation Command）过了就本地提交，不需要人工点头——人工评审不放在每个 task 的提交前。
- push 是唯一的人工闸口：所有 task 完成后（或阶段性收口时），人工审 diff/测试证据/风险/回滚，通过 `./ai pr` 推送（自带确认门）。
- `step-confirm` 与 `full-auto` 的唯一差别是「每个 task 闭环后是否暂停等确认继续」，不是评审位置。

## full-auto 模式

- `full-auto` 只对满足全部以下条件的 task 生效，任一不满足即**自动降级为暂停**并说明原因：
  - `Complexity` 为 `S`
  - `Depends On` 已完成
  - 非高风险（DB migration、auth/权限、billing、风控、共享核心组件）
  - 该 task 的验证与门禁刚刚通过
- 机械层命令统一带 `AI_CONFIRM=1` 前缀，跳过 `./ai work` / `./ai done` 的交互确认。
- push/MR 仍走人工确认（`full-auto` 不覆盖 `./ai pr`）；全 spec 串完后输出总报告，统一进入人工评审。
- 每个 task 闭环的摘要（task id、验证证据、diffstat）仍然完整输出，只是不再等待确认。

## 暂停条件（硬性）

- 下一个 task 是 M/L
- 高风险变更（DB migration、auth/权限、billing、风控、共享核心组件）
- 验证失败或门禁失败
- Open Questions 未解决
- 规则冲突或需要 rebase/冲突处理
- 工作区存在不属于当前 task 的改动
- 无法确认上一个 task 的 PR/commit 边界

## 禁止

- 多个 task-id 混入一个 PR/commit
- 超出当前 task-id 的重构或功能
- 未经确认直接合并到目标分支
- 破坏性命令（人工确认前）
- 验证未执行就声称测试通过
- `step-confirm` 模式下未经人工确认自动继续下一个 task（`full-auto` 模式下 S 级任务连续执行是明确授权的例外）

## 完成输出

spec link、task id、changed files、test evidence、risks、rollback plan、comment review result、pending items、next ready task、是否建议继续（YES/NO + 原因）。
