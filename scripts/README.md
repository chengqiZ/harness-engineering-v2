# Scripts

这些脚本用于在业务仓库中快速接入 AI Coding Harness v2。

v2 分工：`./ai` 只做机械操作（骨架、检查、分支、提交、门禁）；AI 参与的工作（写 spec、写代码、写 MR 材料）由宿主 agent 加载 `skills/` 下的 SKILL.md 执行。脚本不再调度任何 AI 程序，任何宿主 agent（Claude Code、Codex、OpenClaw、Gemini CLI 等）走同一套流程。

## Daily Entry

初始化后，在业务仓库根目录使用：

```bash
./ai status                          # 仓库/规范源/spec 概览
./ai spec <spec-id> [source-doc]     # 初始化 spec 四件套并做占位检查
./ai next <spec-id>                  # 输出下一个可执行 task（S→M→L 优先）
./ai work <spec-id> <task-id>        # 切到任务分支（脏区自动 stash）
./ai done <spec-id> <task-id>        # 运行 04-acceptance 的 Validation Command 并本地提交
./ai run <spec-id> [source-doc]      # spec → next → work → done 一键串行
./ai resume <spec-id>                # 从 03-tasks.md 的 Run Checkpoint 恢复
./ai skill <name>                    # 打印 SKILL.md 路径（spec-prep/task-dev/pr-prep/serial-task）
./ai pr <spec-id> <task-id> [target] # 生成 MR 材料文件并提交推送（有人工确认门）
```

推荐日常路径：

- 新需求：`./ai spec <spec-id> <source-doc>` → 宿主 agent 走 spec-prep → `./ai run` 或分步
- 已有 spec，只执行一个任务：`./ai work <spec-id> <task-id>` + task-dev skill + `./ai done`
- 任务完成后：pr-prep skill + `./ai pr <spec-id> <task-id> main`

`./ai run` 会在 `.ai-harness/specs/<spec-id>/03-tasks.md` 的 `Run Checkpoint` 中记录当前 task、当前步骤和恢复命令。失败后执行 `./ai resume <spec-id>`，按输出的 Resume Command 继续。

## Bootstrap

推荐从业务仓库根目录执行一条初始化命令：

```bash
bash /path/to/harness-engineering-v2/scripts/init_business_repo.sh <repo-url-of-harness-engineering-v2>
```

该命令会添加 submodule、执行 bootstrap，并运行 `./ai status` 验证入口。

手动等价步骤如下：

1. 添加规范源仓库 submodule：

```bash
git submodule add <repo-url> .ai-harness/.ai-standards
git submodule update --init --recursive
```

2. 初始化业务仓库 Harness 目录：

```bash
bash .ai-harness/.ai-standards/scripts/bootstrap_repo.sh
```

3. 初始化后验证入口：

```bash
./ai status
```

## Standards Upgrade

业务仓库已经接入 Harness 后，推荐从业务仓库根目录执行：

```bash
bash .ai-harness/.ai-standards/scripts/update_business_standards.sh [tag-or-sha]
```

- 不传参数：更新 `.ai-harness/.ai-standards` 到 submodule 配置的远端跟踪版本。
- 传入 `tag-or-sha`：拉取规范源 tag 后，将 submodule 锁定到指定 tag 或 commit SHA。

脚本会执行 bootstrap 和 `./ai status`，但不会自动提交。确认无误后手工提交：

```bash
git add .ai-harness .github ai
git commit -m "chore(standards): upgrade ai coding standards"
```

v1 → v2 升级：bootstrap 检测到旧版 Codex 编排器 `./ai` 时自动替换为 v2 薄编排器；存量 spec 四件套格式不变，仅建议逐步为 `04-acceptance.md` 补 `Validation Command:` 行。

## Advanced Script Usage

底层脚本仍可单独调用（排错/受限环境）：

1. 创建 spec 骨架：

```bash
bash .ai-harness/.ai-standards/scripts/init_spec.sh <spec-id>
```

2. 检查 spec 是否仍有明显未填写内容：

```bash
bash .ai-harness/.ai-standards/scripts/check_spec.sh <spec-id>
```

3. 单独执行质量门禁（`./ai done` 内部即调它）：

```bash
bash .ai-harness/.ai-standards/scripts/run_gate.sh <spec-id> <task-id> .ai-harness/specs/<spec-id>/04-acceptance.md
```

## Script Summary

- `templates/ai.sh` → `./ai`
- 业务仓库根目录的薄机械编排器，承载 `status/spec/next/work/done/pr/run/resume/skill` 子命令。不调用任何 AI 程序。

- `bootstrap_repo.sh`
- 初始化 `.ai-harness/`、业务仓库 `AGENTS.md`、PR 模板、changelog 目录和根目录 `./ai`；检测旧版 Codex 编排器并自动升级替换。

- `init_business_repo.sh`
- 从业务仓库根目录执行的一键初始化入口，负责添加规范源 submodule、运行 bootstrap，并验证 `./ai status`。

- `update_business_standards.sh`
- 从业务仓库根目录执行的规范升级入口，负责更新规范源 submodule、运行 bootstrap，并验证 `./ai status`。

- `run_gate.sh`
- v2 质量门禁：从 `04-acceptance.md` 读取 `Validation Command:` 行并逐条执行，全过才放行提交；无命令时退化为要求 `Final Decision` 已写 YES。

- `init_spec.sh`
- 创建 `.ai-harness/specs/<spec-id>/` 并复制 spec 四件套。

- `check_spec.sh`
- 检查 spec 四件套是否存在，以及是否仍残留模板占位内容。

## Notes

- `./ai work` 开始前会把与当前 spec 无关的脏文件保存为带时间戳的 named stash，并输出恢复提示；spec 目录内的未提交修改保留在工作区作为任务上下文。
- `./ai done` 门禁失败时不提交，打印失败命令的输出尾部；阻塞原因应写进 `04-acceptance.md`，由人工评审决定。
- `./ai pr` 会在提交和推送前暂停，要求人工确认 diff、测试证据、风险、回滚方案、commit message 和 MR 描述。
- 不自动调用 GitLab/GitHub API 创建 MR；只生成 MR 材料文件和推送分支。
- `check_spec.sh` 是轻量静态检查，不等价于人工评审或业务验收。
- 这些脚本随规范源仓库版本走；业务仓库通过 submodule 锁定版本，通过 `update_business_standards.sh` 升级。
