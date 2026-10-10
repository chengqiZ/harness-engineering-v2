---
name: spec-prep
description: "Use when initializing or completing a spec four-piece set (01-requirements/02-design/03-tasks/04-acceptance) from a business requirement document. Read the source doc, fill all four files, resolve open questions with the user before any code."
---

# Spec 准备

## 输入

- Spec ID: 由调用方提供（`./ai spec <spec-id> [source-doc>` 已创建骨架）
- 需求文档：`.ai-harness/specs/<spec-id>/source.md`（如调用时给了 source-doc，已拷贝）

## 规则来源（按优先级）

1. 当前会话约束
2. `.ai-harness/AGENTS.md`（项目特例）
3. `.ai-harness/.ai-standards/AGENTS.md`
4. `.ai-harness/.ai-standards/standards/*.md`

规则冲突时：输出冲突点、采用的来源、理由。

## 语言

默认中文输出和文档维护；命令、路径、代码标识符、协议字段、错误码、commit/PR 固定格式保留原文。

## 任务

基于需求文档补齐四件套：

1. `01-requirements.md`：一句话业务目标、In/Out Scope、约束、成功指标、假设、Open Questions
2. `02-design.md`：按 `standards/` 对应栈的设计模板填写（M/L 任务必填，S 任务可留骨架）
3. `03-tasks.md`：拆 task，每个 task 必须含 `Task ID/Purpose/Inputs/Changes/Validation/Done/Complexity/Depends On`
4. `04-acceptance.md`：为每个 task 写验收判据

**v2 关键要求**：每个 task 在 `04-acceptance.md` 至少一条 `- Validation Command:` 行（shell 可执行，如 `pytest tests/unit -k foo`、`mvn compile`）。这是 `./ai done` 质量门禁的输入，没有它门禁退化为仅查 YES 结论。

## 约束

- 不写、不改运行时代码
- 不改 `.ai-harness/specs/<spec-id>/` 之外的文件
- 每个 task 控制在一个 PR 内可完成
- 复杂度规则：单模块=S；跨 2-3 模块=M（须 02-design）；跨端或跨服务=L（必须再拆）
- 涉及 DB migration、auth/权限、billing、风控、共享核心 SDK 时至少 M

## 输出

完成后输出：每个文件的完成摘要、未解决的 Open Questions 清单、推荐的第一个 ready task。等待人工确认后才进入开发。
