---
name: pr-prep
description: "Use when a task-id is implemented and validated. Verify scope and evidence, then draft the MR description from the acceptance evidence. Do not merge."
---

# PR 准备

## 检查

1. 当前改动只覆盖目标 task；范围外改动必须显式列出
2. 仓库约束：一个 PR 对应一个 task-id；行为变化有测试；bug 修复有回归测试；风险与回滚已记录；注释要求已覆盖
3. `04-acceptance.md` 已有真实测试证据和验收结论；未更新则列出缺口

## MR 描述结构

- PR readiness summary
- scope check
- validation result（命令 + 结果）
- risks and rollback
- suggested commit message（subject `<type>(<scope>): <summary>`，body 含 Why/What/Validation）

## 边界

- PR = Pull Request，不是直接合并；除非明确要求，不执行合并
- 材料交给 `./ai pr` 生成的 MR 文件后，由人推送到平台
