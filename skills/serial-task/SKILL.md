---
name: serial-task
description: "Use when a host agent (Claude Code, Codex, OpenClaw, Gemini CLI, etc.) with repo read/write ability drives multiple tasks of one spec in dependency order. One task-id per loop: read card, implement, validate, update acceptance, pause."
---

# 串行任务执行（宿主 agent 通用）

适用：Claude Code、Codex、OpenClaw、Gemini CLI、Copilot CLI、内部 AI 程序等具备仓库读写能力的宿主 agent。不依赖 `./ai` 的调度；机械步骤（分支/stash/提交）可以直接用 `./ai work` / `./ai done`。

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
4. `./ai done <spec-id> <task-id>` 跑质量门禁并本地提交
5. 输出任务闭环摘要，暂停等待人工确认

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
- 未经人工确认自动继续下一个 task（即使都是 S 级）

## 完成输出

spec link、task id、changed files、test evidence、risks、rollback plan、comment review result、pending items、next ready task、是否建议继续（YES/NO + 原因）。
