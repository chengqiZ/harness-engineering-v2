# AI Coding Harness Engineering (v2)

This repository is the reusable standards source for AI-assisted coding rollout. It is not a runtime application repository.

## What v2 Changes (vs v1)

v1 的评估结论是「理念对、机械重」：流程哲学（spec 四件套、submodule 版本锁定、单 task 单 PR）与业界收敛方向一致，全部保留；重做的是机械层：

- **去 Codex 绑定**：v1 的 `./ai` 用约 1300 行 bash 渲染提示词再调度 `codex exec`。v2 的 `./ai` 是纯机械层（分支/stash/检查/门禁/提交），AI 工作交给宿主 agent（Claude Code、Codex、OpenClaw、Gemini CLI 等）通过 `skills/` 按需加载执行。
- **流程模板 → SKILL.md**：v1 的 6 个 prompt 模板 + 4 个 prepare_* 渲染脚本收敛为 5 个 SKILL.md（spec-prep / task-dev / pr-prep / serial-task / parallel-task）。宿主 agent 用 `./ai skill <name>` 取路径加载；不再需要脚本渲染提示词，也不再只限 Codex 可跑。
- **补质量门禁**：新增 `scripts/run_gate.sh`。`04-acceptance.md` 为每个 task 声明 `- Validation Command:`（shell 可执行判据），`./ai done` 逐条执行、全过才放行提交。v1 验收是人工打勾，无机器判据。
- **吸收 v1 未提交改进**：v1 工作区里「编译/构建冒烟先行」的改动已并入 task-dev skill；带 `\r` 的 `.gitattributes` 笔误不带入。

保留不变：submodule 版本锁定（按 SHA 锁定、按 tag 升级、指针回退即回滚）、spec 四件套结构、task 卡片 schema、S/M/L 分级与高风险人工确认门、单 PR 单 task、changelog 与例外规则、Run Checkpoint 断点恢复。

## Repository Role

- Maintain shared agent rules, coding standards, templates, scripts, examples, and SOPs.
- Provide business repositories with a versioned `.ai-harness/.ai-standards` submodule.
- Keep business execution artifacts in business repositories, not in this source repository.

## Start Here

- Full design: `AI_CODING_HARNESS_完整方案.md`
- Operation guide: `AI_CODING_HARNESS_操作指导手册.md`
- Business repository SOP: `docs/业务仓库接入与执行SOP.md`
- Script usage: `scripts/README.md`
- Current TODOs: `docs/TODO.md`

## Business Repository Onboarding

Run from the business repository root:

```bash
bash /path/to/harness-engineering-v2/scripts/init_business_repo.sh <repo-url-of-this-repo>
```

Then verify:

```bash
./ai status
```

Daily commands (mechanical layer only; AI work is done by your host agent via skills):

```bash
./ai spec <spec-id> <source-doc>   # 骨架 + 占位检查 + 拷入需求文档
./ai next <spec-id>                # 下一个 ready task
./ai ready <spec-id>               # 并行模式：全部可同时开工的 task
./ai work <spec-id> <task-id>      # 切任务分支（脏区自动 stash）
./ai worktree <spec-id> <task-id>  # 并行模式：子代理隔离 worktree
./ai collect <spec-id> <task-id>  # 并行模式：主代理回收+勾进度+清 worktree
./ai done <spec-id> <task-id>      # 跑验收门禁 + 本地提交
./ai pr <spec-id> <task-id> main   # 生成 MR 材料 + 推送（有人工确认门）
./ai run <spec-id> <source-doc>    # spec→next→work→done 一键串行
./ai resume <spec-id>              # 从 Run Checkpoint 恢复
./ai skill <name>                  # 打印 SKILL.md 路径给宿主 agent
```

Upgrade standards in an already initialized business repository:

```bash
bash .ai-harness/.ai-standards/scripts/update_business_standards.sh [tag-or-sha]
```

## Source Repository Structure

本仓库是 AI Coding Harness 的规范源仓库，只维护可复用规则、标准、模板、脚本和 SOP；业务需求、任务执行记录、验收记录应留在业务仓库的 `.ai-harness/` 下。目录职责以 `AGENTS.md`、`standards/`、`skills/`、`templates/`、`scripts/` 和 `docs/` 的分工为准，README 仅保留导航和入口说明。

```text
harness-engineering-v2/
├── AGENTS.md                         # 本规范源仓库的强制执行规则
├── README.md                         # 仓库导航、接入入口和结构说明
├── AI_CODING_HARNESS_完整方案.md       # 总体设计、角色划分、版本锁定和流程边界
├── AI_CODING_HARNESS_操作指导手册.md   # 完整操作指南和可复制提示词
├── standards/                        # 可复用工程标准
│   ├── frontend.md                   # FE 规范
│   ├── backend.md                    # BE 规范
│   ├── api-contract.md               # API 契约规范
│   └── testing.md                    # 测试与验收规范
├── skills/                           # v2：宿主 agent 按需加载的阶段技能
│   ├── spec-prep/SKILL.md            # 需求文档 → spec 四件套
│   ├── task-dev/SKILL.md             # 单 task 开发 + 验证 + acceptance 更新
│   ├── pr-prep/SKILL.md              # MR 材料生成
│   ├── serial-task/SKILL.md          # 宿主 agent 串行多 task 执行
│   └── parallel-task/SKILL.md        # 主代理派活 + 最大并发子代理 worktree 并行执行
├── templates/                        # 写入业务仓库或供 AI 读取的模板
│   ├── ai.sh                         # 业务仓库根目录 `./ai` 薄编排器
│   ├── business-repo-AGENTS.md       # 业务仓库 `.ai-harness/AGENTS.md` 模板
│   ├── pull_request_template.md      # PR 模板
│   ├── changelog-entry.md            # 业务仓库 changelog 条目模板
│   ├── exception-rule.md             # 例外规则模板
│   ├── project-onboarding-checklist.md
│   ├── standards-upgrade-review.md
│   └── specs/                        # 业务仓库 `.ai-harness/specs/<spec-id>/` 四件套骨架
│       ├── 01-requirements.md
│       ├── 02-design.md
│       ├── 03-tasks.md
│       └── 04-acceptance.md          # v2：含 Validation Command 门禁声明
├── scripts/                          # 业务仓库接入、执行和验证脚本
│   ├── README.md                     # 脚本使用说明
│   ├── init_business_repo.sh         # 一键接入业务仓库
│   ├── bootstrap_repo.sh             # 初始化 `.ai-harness/`、PR 模板和 `./ai`
│   ├── update_business_standards.sh  # 升级业务仓库中的规范源 submodule
│   ├── run_gate.sh                   # v2：执行 04-acceptance 的 Validation Command 门禁
│   ├── init_spec.sh                  # 创建 spec 四件套
│   └── check_spec.sh                 # 检查 spec 是否仍有明显占位内容
└── docs/                             # SOP、简明流程、TODO 和 changelog 说明
    ├── 业务仓库接入与执行SOP.md
    ├── 业务仓库执行流程简明版.md
    ├── TODO.md
    └── changelog/README.md
```

## Notes

- 这份 README 只承担仓库导航和入口说明，不再展开逐文件审计。
- 需要了解各文件的职责时，以对应目录下的说明文档为准。
- v1 业务仓（如 harness-base-test）升级到 v2：在业务仓库执行 `bash .ai-harness/.ai-standards/scripts/update_business_standards.sh <v2-tag-or-sha>`，bootstrap 会自动把旧版 Codex 编排器 `./ai` 升级为 v2 薄编排器；存量 spec 四件套格式不变，仅建议逐步为 `04-acceptance.md` 补 `Validation Command:` 行。

## Maintenance Rules

- Follow `AGENTS.md` before changing this repository.
- Use Chinese by default for future documents, templates, SOPs, reports, and user-facing replies; keep commands, paths, identifiers, protocol fields, error codes, and fixed PR/commit keywords in their original form.
- Do not add source-repo maintenance records under top-level `specs/`; use `docs/TODO.md`, decision records, changelog notes, or PR/report evidence instead.
- Business repositories should create execution specs under `.ai-harness/specs/<spec-id>/`.
- Keep source-repo maintenance PRs scoped to one coherent maintenance topic.
- Do not commit secrets, tokens, PII, or business-only execution artifacts.
