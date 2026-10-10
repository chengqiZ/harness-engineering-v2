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

**任务拆分原则——为并行而拆（重要）**：

- **能并行的尽量并行**：task 之间默认追求 `(none)` 依赖。只有真实的运行时/数据依赖（B 的输入是 A 的产物）才写 `Depends On`；「顺手一起做」不是依赖，禁止为了串行省事把独立改动捆成一个 task。
- **颗粒度适配并发，但不过度拆**：倾向多拆、拆小，让 ready task 数量尽量接近并发子代理数（默认 10）——拆不够时并发池吃不满，白等。但**不是越细越好**：每个 task 必须仍是一个有业务意义的完整闭环（能独立过门禁、独立成一个 PR）；为了凑数把一个连贯改动拆成原子碎片（每个碎片单独跑不过门禁、或 PR 小到没有评审价值）是错误方向。经验上：ready 数量达到并发数就停止加拆，优先靠合并小 task 收敛而不是继续切。
- **拆分判定**：写 task 时自问「这两个 task 在两个隔离工作区里同时开发，会不会改同一个文件 / 需要对方的产物」——会 → 保留依赖或合并；不会 → 拆开标 `(none)`。
- **公共底座先行**：多个 task 都要改的共享文件（类型定义、接口契约、公共组件）先拆成一个前置 task，让其他 task `Depends On` 它，避免并行子代理在同文件上撞车。

**v2 关键要求**：每个 task 在 `04-acceptance.md` 至少一条 `- Validation Command:` 行（shell 可执行，如 `pytest tests/unit -k foo`、`mvn compile`）。这是 `./ai done` 质量门禁的输入，没有它门禁退化为仅查 YES 结论。

**多 task spec 的分节格式（并行模式必须）**：多个 task 时，`04-acceptance.md` 的 Validation Commands 区按 `### <task-id>` 分节组织（如 `### T1` 下挂 T1 的命令行）。门禁执行器遇分节只跑当前 task 小节内的命令——不分节则退回旧语义（跑全部命令），并行子代理在隔离 worktree 里会因缺其他 task 的产物而误杀。

**信任边界警示**：Validation Command 由 shell 直接执行（`eval`）。谁写 spec 谁就拥有门禁的代码执行权——生成 spec 的 agent 与执行门禁的 agent 通常是同一个，门禁的独立性来自**人工确认 spec 四件套**这道关。因此 spec 四件套在开发前必须经过人工评审（尤其 Validation Command 行），确认判据本身可信、且命令只做验证不做副作用。

## 约束

- 不写、不改运行时代码
- 不改 `.ai-harness/specs/<spec-id>/` 之外的文件
- 每个 task 控制在一个 PR 内可完成
- 复杂度规则：单模块=S；跨 2-3 模块=M（须 02-design）；跨端或跨服务=L（必须再拆）
- 涉及 DB migration、auth/权限、billing、风控、共享核心 SDK 时至少 M

## 输出

完成后输出：每个文件的完成摘要、未解决的 Open Questions 清单、推荐的第一个 ready task，以及**并行度评估**（当前 ready task 数量、依赖链最深路径、按并发上限估算的批次划分；ready 数明显低于并发数时说明原因——是拆分不足还是业务依赖所限）。等待人工确认后才进入开发。
