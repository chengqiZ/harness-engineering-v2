# AI Coding Harness 操作指导手册 v2

## 1. 使用前提

- 当前仓库是规范源仓库，用于维护统一规则、模板、示例和 SOP。
- 你有一个规范源仓库：`harness-engineering-v2`（本仓库）
- 业务仓库通过 submodule 引入到：`/.ai-harness/.ai-standards`
- 业务仓库的规范相关内容统一放在：`/.ai-harness/`
- `/.ai-harness/AGENTS.md` 只放项目特例
- 你有一个具备仓库读写能力的宿主 agent（Claude Code、Codex、OpenClaw、Gemini CLI、Copilot CLI 或内部 AI 程序）

建议先阅读：
- 主方案：`AI_CODING_HARNESS_完整方案.md`
- 业务仓库接入与执行 SOP：`docs/业务仓库接入与执行SOP.md`
- 项目接入清单：`templates/project-onboarding-checklist.md`

## 2. 一次性初始化（新业务仓库）

推荐从业务仓库根目录执行：

```bash
bash /path/to/harness-engineering-v2/scripts/init_business_repo.sh <repo-url-of-harness-engineering-v2>
```

该命令会添加 submodule、执行 bootstrap，并运行 `./ai status`。

手工等价步骤用于排错或受限环境：

```bash
git submodule add <repo-url-of-harness-engineering-v2> .ai-harness/.ai-standards
git submodule update --init --recursive
bash .ai-harness/.ai-standards/scripts/bootstrap_repo.sh
git add .gitmodules .ai-harness .github
git commit -m "chore(harness): setup ai coding harness"
```

初始化后需要人工补齐：
- `/.ai-harness/AGENTS.md`
- 业务仓库的首个 `spec-id`

初始化后优先验证：

```bash
./ai status
```

## 3. 日常流程：机械层 + 宿主 agent 配合

v2 的分工：`./ai` 只做机械操作（骨架、检查、分支、提交、门禁）；AI 参与的工作由宿主 agent 加载 skills 执行。任何宿主 agent 都用同一套流程，没有 Codex 特权路径。

```bash
./ai status                          # 仓库/规范源/spec 概览
./ai spec <spec-id> <source-doc>     # 骨架 + 占位检查 + 拷入需求文档
./ai next <spec-id>                  # 下一个 ready task
./ai work <spec-id> <task-id>        # 切任务分支（脏区自动 stash）
./ai done <spec-id> <task-id>        # 跑验收门禁 + 本地提交
./ai pr <spec-id> <task-id> main     # 生成 MR 材料 + 推送（有人工确认门）
./ai run <spec-id> <source-doc>      # spec→next→work→done 一键串行
./ai resume <spec-id>                # 从 Run Checkpoint 恢复
./ai skill <name>                    # 打印 SKILL.md 路径
```

skills 一览（宿主 agent 按需加载）：
- `spec-prep`：需求文档 → spec 四件套（要求为每个 task 写 Validation Command）
- `task-dev`：单 task 开发 + 验证 + acceptance 更新
- `pr-prep`：MR 材料生成
- `serial-task`：宿主 agent 串行多 task 执行（含硬性暂停条件）

### 3.1 标准路径（每个需求的完整走法）

1. `./ai spec <spec-id> <source-doc>`
2. 对宿主 agent 说：「读取 `./ai skill spec-prep` 指向的 SKILL.md，补齐 spec 四件套」→ 人工确认 spec 和推荐 task
3. `./ai work <spec-id> <task-id>`
4. 对宿主 agent 说：「读取 `./ai skill task-dev` 指向的 SKILL.md，执行该 task」→ agent 实现、跑验证命令、更新 04-acceptance
5. `./ai done <spec-id> <task-id>` → 门禁全过 + 本地提交
6. 对宿主 agent 说：「读取 `./ai skill pr-prep` 指向的 SKILL.md，生成 MR 描述」
7. `./ai pr <spec-id> <task-id> main` → 推送 + MR 材料文件
8. 平台建 MR、评审、合并；合并后按 `templates/changelog-entry.md` 写 changelog

### 3.2 一键路径（低风险 S 级）

```bash
./ai run <spec-id> <source-doc>
```

失败后：

```bash
./ai resume <spec-id>
```

按输出的 Resume Command 继续（如 `./ai work <spec-id> <task-id>`）。

### 3.3 多 task 串行（宿主 agent 驱动）

对宿主 agent 说：「读取 `./ai skill serial-task` 指向的 SKILL.md，按 03-tasks.md 依赖顺序串行执行」。agent 会在每个 task 闭环后暂停；M/L、高风险、验证失败、规则冲突等场景强制暂停（见 SKILL.md 的暂停条件）。

## 4. 质量门禁（v2 新增，重点）

- spec 阶段（spec-prep skill）就要求为每个 task 写 `- Validation Command:` 行到 `04-acceptance.md`，内容是 shell 可执行命令，如 `pytest tests/unit -k note_format`、`mvn compile`。
- `./ai done <spec-id> <task-id>` 会调 `run_gate.sh` 逐条执行这些命令；任何一条失败即拒绝提交并打印输出尾部。
- 没有任何 Validation Command 时门禁退化为：`Final Decision` 必须已写 YES。这只是兜底，不是常态——新 spec 必须有机器判据。
- 修 bug 的回归测试、行为变化的测试更新同样走这个门禁（命令里体现）。

## 5. 高级/排错流程：逐脚本使用

1. `bash .ai-harness/.ai-standards/scripts/init_spec.sh <spec-id>` 创建四件套骨架
2. 宿主 agent 走 spec-prep skill 补齐
3. `bash .ai-harness/.ai-standards/scripts/check_spec.sh <spec-id>` 检查占位残留
4. `bash .ai-harness/.ai-standards/scripts/run_gate.sh <spec-id> <task-id> .ai-harness/specs/<spec-id>/04-acceptance.md` 单独跑门禁排错

## 6. 子模块升级操作

推荐从业务仓库根目录执行：

```bash
bash .ai-harness/.ai-standards/scripts/update_business_standards.sh [tag-or-sha]
```

- 不传参数：更新到 submodule 配置的远端跟踪版本。
- 传入 `tag-or-sha`：锁定到指定规范源 tag 或 commit SHA。
- 脚本会执行 bootstrap 和 `./ai status`，但不会自动提交。

确认无误后提交：

```bash
git add .ai-harness .github ai
git commit -m "chore(standards): upgrade ai coding standards"
```

升级后让宿主 agent 执行「规范升级评估」：读取 `templates/standards-upgrade-review.md`，输出新规范可能影响的流程点、需要调整的项目特例、可能导致失败的测试、修复顺序（P0/P1/P2）。

## 7. 规范源库维护记录

当前仓库维护自身 standards、docs、templates 时，不在顶层 `specs/` 下沉淀每次维护任务。业务仓库 spec 骨架只保留在 `templates/specs/`。

源库维护事项通过以下资料留痕：
- `docs/TODO.md`
- 决策记录或 SOP 更新
- changelog 说明
- PR/report 中的验证证据

业务仓库执行产物仍使用 `.ai-harness/specs/<spec-id>/` 四件套。

## 8. 可直接复制的启动提示词

默认要求：后续文档、模板、SOP、报告和 AI 回复以中文为主；命令、路径、代码标识符、协议字段、错误码、commit/PR 固定格式可保留原文。

### 8.1 通用启动提示词（每个需求第一条）

```text
请按以下优先级读取并遵循规范：
1) 当前会话约束
2) .ai-harness/AGENTS.md
3) .ai-harness/.ai-standards/AGENTS.md
4) .ai-harness/.ai-standards/standards/*.md

如果规则冲突，请在输出中明确：冲突点、采用的规则来源、理由。

后续回复、文档和报告默认使用中文；命令、路径、代码标识符、协议字段、错误码、commit/PR 固定格式可保留原文。

先不要写代码，先读取 ./ai skill spec-prep 指向的 SKILL.md，
然后审阅 .ai-harness/specs/<spec-id>/01-requirements.md 并输出缺失项与歧义问题清单。
```

### 8.2 需求澄清提示词

```text
基于 .ai-harness/specs/<spec-id>/01-requirements.md，
请输出：
1) 缺失信息（按高/中/低优先级）
2) 歧义点
3) 可执行的补充建议
要求：仅输出可落地结论，不输出泛化建议。
```

### 8.3 单任务开发提示词

```text
请读取 ./ai skill task-dev 指向的 SKILL.md，
只实现 .ai-harness/specs/<spec-id>/03-tasks.md 中的 <task-id>。
完成后运行该 task 的 Validation Command 并更新 04-acceptance.md，
然后停止等我评审；不要自行调用 ./ai done。
```

### 8.4 代码评审提示词

```text
请按“高风险优先”评审本次改动，基于 .ai-harness/.ai-standards 规范输出：
1) 严重问题（必须修复）
2) 潜在回归风险
3) 缺失测试
4) API/数据库兼容性问题
5) 可选优化项

每条问题给出：影响、证据（文件/逻辑点）、修复建议。
```

### 8.5 PR 说明生成提示词

```text
请读取 ./ai skill pr-prep 指向的 SKILL.md，
为 <task-id> 生成 MR 描述，必须包含：
1) Spec 链接
2) Task ID
3) 变更文件清单
4) 测试命令与结果
5) 风险
6) 回滚方案
7) Exception/Reason/Scope/Expiry（如有例外）
```

### 8.6 发布前验收提示词

```text
请按 .ai-harness/specs/<spec-id>/04-acceptance.md 与 .ai-harness/.ai-standards/standards/testing.md 规范做最终验收。
输出：通过项、不通过项、阻塞项、是否允许合并（YES/NO），并给出依据。
```

### 8.7 规范升级提示词（子模块版本升级后）

```text
当前项目已将 .ai-harness/.ai-standards 升级到 <tag-or-sha>。
请按 .ai-harness/.ai-standards/templates/standards-upgrade-review.md 扫描本仓库并输出：
1) 新规范可能影响的流程点
2) 需要调整的项目特例（AGENTS.md）
3) 可能导致失败的测试或门禁
4) 建议的修复顺序（P0/P1/P2）
```

## 9. 常见问题

### Q1：宿主 agent 没有读取子模块规范怎么办？
- 在第一条提示词里明确列出规范读取顺序（见 8.1）。
- 要求 agent 先「复述已读取的规范来源」。

### Q2：项目需要例外规则怎么办？
- 写在 `/.ai-harness/AGENTS.md`，并加 `Reason/Scope/Expiry`。

### Q3：规范升级后有回归怎么办？
- 回退 `.ai-harness/.ai-standards` 到上一个稳定 tag/SHA，单独提 PR。

### Q4：门禁命令在本机跑不了（环境缺依赖）怎么办？
- 把阻塞原因写进 `04-acceptance.md` 的 Testing Evidence 段，人工评审决定是否放行；门禁本身不做静默跳过。

## 10. 日常最短使用法（3 条）

1. 新需求：`./ai spec <spec-id> <source-doc>` + 「读取 spec-prep skill 补齐四件套」
2. 单任务：`./ai work <spec-id> <task-id>` + 「读取 task-dev skill 执行」+ `./ai done <spec-id> <task-id>`
3. 合并前：`./ai pr <spec-id> <task-id> main`

## 11. 规范源仓库维护者补充动作

当你维护当前规范源仓库时，建议同步维护以下资料：
- `templates/*.md`、`templates/specs/`
- `skills/*/SKILL.md`
- `docs/业务仓库接入与执行SOP.md`、`docs/changelog/README.md`
- `scripts/*.sh`、`scripts/README.md`

当规范升级时，除更新规则本身外，也应检查：
- 模板是否需要同步补字段
- 示例是否仍符合当前规则
- SOP 是否仍适配当前推荐流程
- SKILL.md 的阶段边界是否仍与 `./ai` 子命令对齐
