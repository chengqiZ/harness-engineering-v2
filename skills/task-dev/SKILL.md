---
name: task-dev
description: "Use when implementing a single task-id from 03-tasks.md. Read the task card, implement only its scope, run the validation commands, update acceptance evidence, then stop for review."
---

# 单任务开发

## 前置检查（写代码前）

1. `.ai-harness/specs/<spec-id>/01-requirements.md` 和 `03-tasks.md` 完整
2. 当前 task 未标记 Done；其 `Depends On` 已完成
3. M/L 任务确认 `02-design.md` 可用
4. 已读相关 `standards/*.md`（注释要求重点）

## 执行规则

1. 复述当前 task 的 `Purpose/Inputs/Changes/Validation/Done/Depends On`
2. 只实现该 task 范围；不实现 03-tasks.md 未声明的功能
3. 不做顺手重构；范围外问题单独列出，先说后动
4. 行为变化补测试；bug 修复补回归测试
5. 注释覆盖：类/模块、公开方法、重要字段/状态、非显式分支、边界、外部假设、事务约束、风险逻辑——讲职责/意图/业务含义/约束/不变量，不复述语法
6. 先跑编译/构建冒烟（如 `mvn compile`、`gradle classes`），失败即停并报告
7. 跑 task 的 Validation 命令（同 `04-acceptance.md` 的 Validation Command），报告：执行命令、通过/失败摘要、阻塞项
8. 更新 `04-acceptance.md`：测试证据、风险、回滚方案、comment review result、门禁自验结论（YES/NO——是 agent 的留痕记录，最终是否合并由 push 前人工评审决定）

## 完成输出

变更摘要、changed files、测试结果、风险、回滚方式、comment review result、建议 commit message（`<type>(<scope>): <summary>` 格式）。然后调用 `AI_CONFIRM=1 ./ai done <spec-id> <task-id>` 过门禁并本地提交，输出提交后的闭环摘要。人工评审统一放在 push 前（`./ai pr` 有确认门，push 是唯一的人工闸口）；不要自行 push。
