# 业务仓库接入与执行 SOP（v2）

## 背景

- 当前仓库是 AI Coding Harness v2 的规范源仓库。
- 本 SOP 面向已决定接入 Harness 的业务仓库，覆盖首次接入、增量需求执行、验收、回滚和复盘。
- v2 与 v1 的关键差异：`./ai` 不再调度 Codex，机械层与 AI 层分离；新增 `./ai done` 质量门禁；所有宿主 agent（Claude Code、Codex、OpenClaw、Gemini CLI 等）走同一套 skills。

## 研究问题

- 业务仓库如何稳定接入 `.ai-harness/.ai-standards`？
- 新需求如何按 spec-first 流程推进到单个 task 和 PR？
- 如何留下可复查的验收证据、风险说明和回滚方案？
- 「什么算验收通过」如何从人工打勾变成机器判据？

## 结论摘要

- 新业务仓库先完成 `.ai-harness` 初始化，再确认 `./ai status` 可用。
- 每个需求必须先建立 `spec-id`，每个 PR 只对应一个 `task-id`。
- spec 阶段（spec-prep skill）必须为每个 task 写 `- Validation Command:` 机器判据。
- 机械步骤用 `./ai`；AI 步骤由宿主 agent 加载 skills 执行；两者用同一流程，无工具差异。
- 合并前必须留下测试证据、风险、回滚方案和 acceptance 结论；`./ai done` 门禁是提交前的硬检查。

## 方案对比

### 方案 A：一键执行（低风险 S 级）

- 命令：`./ai run <spec-id> <source-doc>`
- 优点：链路最短。
- 限制：run 只串到 done（本地提交）；push/MR 走 `./ai pr` 单独执行。失败定位回到 checkpoint 和分步命令。

### 方案 B：分步执行（默认推荐）

- 命令：`./ai status`、`./ai spec`、`./ai next`、`./ai work`、`./ai done`、`./ai pr`
- 配合：宿主 agent 在 spec/开发/PR 三个节点加载 spec-prep / task-dev / pr-prep skills。
- 优点：每步输出明确；M/L 任务、高风险任务有人工确认点。
- 限制：人工操作更多。

### 方案 C：宿主 agent 串行多 task

- 入口：`./ai skill serial-task`
- 适用：一个 spec 有多个 task，agent 按依赖顺序连续推进。
- 硬规则：每个 task 独立闭环（实现→验证→acceptance→提交）；M/L、高风险、验证失败、规则冲突、工作区异常时强制暂停。

### 方案 D：最大并发子代理（parallel-task）

- 入口：`./ai skill parallel-task`
- 适用：宿主 agent 具备子代理/并行会话能力，希望把可并行的 task 同时开工。
- 分工：主代理只派活（`./ai ready`）和管理进度文件（回收时统一勾选）；每个子代理独占一个 git worktree（`./ai worktree`）开发一个 task，门禁在 worktree 内按 task 分节执行；`./ai collect` 回收分支。
- 硬规则：M/L、高风险 task 不进并发池（降级方案 C）；业务文件 merge 冲突停下走人工，不自动解决。

## 风险与限制

- `M/L` 任务、DB migration、auth、权限、billing、风险逻辑不得自动推进，必须先人工确认设计和影响范围。
- `./ai work` 会切分支并 stash 无关脏区；执行前应确认工作区没有不应混入的改动。
- `./ai done` 会执行 04-acceptance 声明的 Validation Command；命令本身要能在本机环境跑通，跑不了就按手册 Q4 处理（写明阻塞，人工评审决定）。
- `./ai pr` 会提交推送，执行前必须过人工确认门（diff、测试证据、风险、回滚、MR 文案）。
- 注释、测试、API 契约和异常处理要求以 `.ai-harness/.ai-standards/standards/*.md` 为准。

## 推荐做法

- 新仓库接入后先执行 `./ai status`。
- 新需求先 `./ai spec` 建骨架，宿主 agent 走 spec-prep，人工确认后再开发。
- 每个 task 在 spec 阶段就写好 Validation Command；「验收口径」在开发开始前对齐。
- 单次 PR 只执行一个 `task-id`。
- 复杂任务用分步执行；流程稳定后用方案 A/C。

## 落地步骤

### 1. 接入业务仓库

在业务仓库根目录执行：

```bash
bash /path/to/harness-engineering-v2/scripts/init_business_repo.sh <repo-url-of-harness-engineering-v2>
```

验证：

```bash
./ai status
```

接入后人工检查：

- `.ai-harness/AGENTS.md` 只保留项目特例。
- `.github/pull_request_template.md` 已存在。
- `.ai-harness/docs/changelog/README.md` 已存在。
- `./ai status` 能输出仓库、分支、规范源和 specs 信息。

### 2. 准备增量需求

需求文档就是普通业务文档（PRD、方案说明、缺陷描述、验收口径或用户故事），放在例如 `docs/requirements/<spec-id>.md`。至少包含：要解决的问题、用户触发路径、期望结果、明确不做的范围、验收方式。

### 3. 生成并确认 spec

```bash
./ai spec <spec-id> <source-doc>
```

（需求文档会自动拷入 `.ai-harness/specs/<spec-id>/source.md`）

然后对宿主 agent 说：

```text
请读取 ./ai skill spec-prep 指向的 SKILL.md，
基于 .ai-harness/specs/<spec-id>/source.md 补齐四件套。
要求每个 task 在 04-acceptance.md 写至少一条 Validation Command。
完成后输出：每个文件的完成摘要、Open Questions、推荐的第一个 ready task。
```

开发前必须确认：

- `01-requirements.md` 已补齐关键需求。
- `03-tasks.md` 至少有一个可执行 `task-id`。
- `04-acceptance.md` 每个 task 有 Validation Command。
- `M/L` 任务已补齐设计或拆小。
- Open Questions 不阻塞当前 task。

### 4. 执行单个 task

```bash
./ai work <spec-id> <task-id>
```

对宿主 agent 说：

```text
请读取 ./ai skill task-dev 指向的 SKILL.md，执行 <task-id>。
完成后运行该 task 的 Validation Command 并更新 04-acceptance.md，
然后停止等我评审；不要自行调用 ./ai done。
```

### 5. 门禁 + 提交

```bash
./ai done <spec-id> <task-id>
```

- run_gate.sh 逐条执行 Validation Command，全过才本地提交。
- 人工评审 agent 的产出（diff、测试证据、注释、风险、回滚）后再放行提交。

### 6. 准备 PR 和验收

对宿主 agent 说：

```text
请读取 ./ai skill pr-prep 指向的 SKILL.md，为 <task-id> 生成 MR 描述。
```

然后：

```bash
./ai pr <spec-id> <task-id> main
```

推送后在平台创建 MR。PR/report 必须包含：spec link、task id、changed files、test evidence、risks、rollback plan、pending items。合并后按 `templates/changelog-entry.md` 更新 `.ai-harness/docs/changelog/`。

### 7. 失败恢复

`./ai run` 中断后：

```bash
./ai resume <spec-id>
```

按输出的 Resume Command 继续。规范源版本回退：按业务仓库 PR 中记录的 submodule tag/SHA 回退，并单独提交。

### 8. 多 task 串行（宿主 agent 驱动）

```text
请读取 ./ai skill serial-task 指向的 SKILL.md。
按 .ai-harness/specs/<spec-id>/03-tasks.md 依赖顺序串行执行 task：
每个 task 走 ./ai work → task-dev skill → ./ai done 闭环。
每完成一个 task-id 后暂停，输出验证证据、风险、回滚方案、PR 材料和 next ready task，等待我确认是否继续。
```

## 验收标准

- `./ai status` 可以正常输出仓库和规范源信息。
- 至少 1 个 `spec-id` 建立完成。
- 当前 PR 只对应 1 个 `task-id`。
- 行为变化有测试证据；类/模块、方法、属性/状态、条件分支、边界处理和风险逻辑有明确的 comment review result。
- `04-acceptance.md` 每个 task 有 Validation Command；`./ai done` 门禁真实执行过。
- `04-acceptance.md` 有明确 YES/NO 结论。
- PR/report 包含风险、回滚方案和 pending items。
- `.ai-harness/docs/changelog/` 留下变更记录。
