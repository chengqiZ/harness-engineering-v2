# AI Coding Harness 完整方案 v2（Submodule 统一规范 + SKILL 分层版）

## 1. 目标

- 建立跨项目统一的 AI 编程规范，不再到处复制文件。
- 通过 Git Submodule 锁定规范版本，保证可追溯、可升级、可灰度。
- 在需求理解、任务拆解、开发、测试、评审、发布全流程统一执行。
- 当前仓库定位为「规范源仓库」，负责维护规则、模板、示例和 SOP，不直接承载业务实现。
- 业务仓库初始化后，宿主 agent 基于需求文档或方案文档补齐 spec，经确认后再进入开发。

## 2. v2 相对 v1 的设计变更

### 2.1 分层模型

v2 把 Harness 明确拆成两层，职责不再混淆：

1. **机械层（`./ai` + `scripts/`）**：纯确定性操作——spec 骨架、占位检查、task 解析、分支/stash/提交/推送、验证门禁执行。不调用任何 AI，不渲染任何提示词。
2. **AI 层（`skills/`）**：需要模型参与的工作——写 spec、写代码、写 MR 材料。宿主 agent（Claude Code、Codex、OpenClaw、Gemini CLI、内部 AI 程序）通过 `./ai skill <name>` 获取 SKILL.md 路径并按需加载。

v1 的问题：机械层里塞了「渲染提示词 + 调度 codex exec」的第三种职责，导致约 1300 行 bash、绑定单一工具、其他 agent 只能走逃生口（v1 手册的 portable-managed 章节）。v2 删除该职责，机械层缩到约 400 行，全工具平等。

### 2.2 质量门禁（v2 新增）

- `04-acceptance.md` 新增 `Validation Commands` 段：每个 task 至少一条 `- Validation Command:` 行，内容是 shell 可执行命令。
- `./ai done` 调 `scripts/run_gate.sh` 逐条执行；全过才放行提交。无命令时退化为「Final Decision 必须已写 YES」。
- 设计意图：v1 的验收是人工打勾模板，「什么算过」没有机器判据；v2 把验收口径前移到 spec 阶段声明，开发者和评审者对齐同一个可执行判据。

### 2.3 断点恢复保留

- `./ai run` 在 03-tasks.md 底部维护 `Run Checkpoint`（当前 task、当前步骤、恢复命令）；失败后 `./ai resume <spec-id>` 输出恢复入口。

## 3. 核心设计

### 3.1 仓库角色

1. 规范源仓库：`harness-engineering-v2`
   - 核心规则：`AGENTS.md`、`standards/*`
   - 阶段技能：`skills/*/SKILL.md`
   - Spec 模板：`templates/specs/*`
   - 执行模板：`templates/*.md`
   - SOP：`docs/*.md`
2. 业务仓库：`project-*`
   - 在 `/.ai-harness/` 下统一管理规范相关内容
   - 通过子模块引入规范源仓库到 `/.ai-harness/.ai-standards`
   - `/.ai-harness/AGENTS.md` 仅存放项目特例
   - spec 与执行产物放在 `/.ai-harness/specs/<spec-id>/`、`/.ai-harness/docs/changelog/`、`/.ai-harness/pr/`

### 3.2 版本锁定机制（自 v1 保留）

- `.gitmodules` 记录子模块路径和 URL。
- 父仓库提交中记录子模块指向的 commit SHA（gitlink）。
- 业务仓库升级规范，本质是把 `/.ai-harness/.ai-standards` 指针从旧 SHA 更新到新 SHA/tag。

### 3.3 规则优先级（自 v1 保留）

- `session constraints > .ai-harness/AGENTS.md > .ai-harness/.ai-standards/AGENTS.md > .ai-harness/.ai-standards/standards/*.md`

## 4. 目标目录结构

```text
harness-engineering-v2/                # 规范源仓库
  AGENTS.md
  README.md
  standards/
  skills/
  templates/
  scripts/
  docs/

project-a/                             # 业务仓库
  .github/
    pull_request_template.md
  .ai-harness/
    .ai-standards/                     # submodule -> harness-engineering-v2@<sha>
    AGENTS.md                          # 仅项目特例
    specs/
      <spec-id>/
        source.md                      # 原始需求文档（./ai spec 时自动拷入）
        01-requirements.md
        02-design.md
        03-tasks.md
        04-acceptance.md               # 含 Validation Command 门禁声明
    docs/
      changelog/
    pr/
```

## 5. Git Submodule 落地流程

### 5.1 首次接入

推荐从业务仓库根目录执行一键初始化：

```bash
bash /path/to/harness-engineering-v2/scripts/init_business_repo.sh <repo-url-of-harness-engineering-v2>
```

该命令会添加规范源 submodule、执行 bootstrap，并运行 `./ai status` 验证入口。

手工等价步骤用于排错或受限环境：

```bash
git submodule add <repo-url-of-harness-engineering-v2> .ai-harness/.ai-standards
git submodule update --init --recursive
bash .ai-harness/.ai-standards/scripts/bootstrap_repo.sh
git add .gitmodules .ai-harness .github
git commit -m "chore(harness): bootstrap ai harness"
```

### 5.2 规范升级（按版本）

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

v1 → v2 升级说明：bootstrap 检测到旧版 Codex 编排器 `./ai` 时会自动替换为 v2 薄编排器；存量 spec 四件套格式不变，仅建议逐步为 `04-acceptance.md` 补 `Validation Command:` 行。

### 5.3 升级门禁（自 v1 保留）

- 升级 PR 必须说明：变更摘要、是否影响当前项目流程、回退方式（回到旧 tag/SHA）。

## 6. 开发流程（Spec 驱动，宿主 agent 通用）

推荐日常路径：

1. `./ai spec <spec-id> <source-doc>` — 机械层建骨架并拷入需求文档
2. 宿主 agent 加载 `./ai skill spec-prep` 指向的 SKILL.md，补齐四件套，人工确认
3. `./ai next <spec-id>` — 取下一个 ready task
4. `./ai work <spec-id> <task-id>` — 切任务分支
5. 宿主 agent 加载 `./ai skill task-dev`，实现 + 验证 + 更新 04-acceptance
6. `./ai done <spec-id> <task-id>` — 跑验证门禁 + 本地提交
7. 宿主 agent 加载 `./ai skill pr-prep` 生成 MR 描述；`./ai pr <spec-id> <task-id> main` 推送并落 MR 材料文件
8. 平台侧人工创建 MR；合并后写 changelog

一键路径（低风险 S 级）：

```bash
./ai run <spec-id> <source-doc>    # 串行 spec → next → work → done
./ai resume <spec-id>             # 失败后从 Run Checkpoint 恢复
```

多个 task 连续执行：宿主 agent 加载 `./ai skill serial-task`，按依赖顺序循环；每 task 闭环后暂停等人工确认（serial-task SKILL.md 的暂停条件为硬规则）。

规范源仓库自身不使用顶层 `specs/` 作为维护过程记录；业务仓库 spec 骨架只保留在 `templates/specs/`。源库维护事项通过 `docs/TODO.md`、决策记录、changelog 或 PR/report 证据留痕。

## 7. 规范执行边界（自 v1 保留）

### 7.1 统一规则放哪里

- 通用规则只改规范源仓库。
- 业务仓库不直接改 `/.ai-harness/.ai-standards` 内容。
- 项目差异写在 `/.ai-harness/AGENTS.md`。

### 7.2 项目特例要求

- 每条特例必须包含：`Reason`、`Scope`、`Expiry`。
- 未声明例外时，规则全部强制。

## 8. 风险与回滚（自 v1 保留）

### 8.1 常见风险

- 业务仓库规范版本不一致
- 规范升级导致旧项目流程不兼容
- 宿主 agent 忽略子模块规则，仅按项目局部规则执行

### 8.2 回滚策略

- 规范升级失败时，回退子模块到上一个稳定 tag/SHA
- 升级 PR 独立提交，禁止与业务功能改动混合

## 9. 验收标准（v2）

- 至少 1 个业务仓库完成 submodule 接入（可用 harness-base-test 升级演练）
- 至少 1 个真实需求走通 spec → task → code → gate → acceptance 闭环（`./ai done` 门禁真实拦截过一次或放行过一次）
- 至少 1 次规范升级演练（含回滚）
- 团队成员在至少两种宿主 agent（如 Claude Code 与 Codex）下用同一套 skills 完成任务推进

## 10. 附加资料

- 业务仓库接入与执行 SOP：`docs/业务仓库接入与执行SOP.md`
- 团队快速上手：`docs/团队快速上手指册.md`
- 项目接入检查清单：`templates/project-onboarding-checklist.md`
- 业务仓库 AGENTS 模板：`templates/business-repo-AGENTS.md`
- PR 模板：`templates/pull_request_template.md`
- Changelog 模板：`templates/changelog-entry.md`
- 规范升级评估模板：`templates/standards-upgrade-review.md`
- 例外规则模板：`templates/exception-rule.md`
- Spec 模板：`templates/specs/`
- Skills：`skills/spec-prep/`、`skills/task-dev/`、`skills/pr-prep/`、`skills/serial-task/`
- 自动化脚本：`scripts/init_business_repo.sh`、`scripts/bootstrap_repo.sh`、`scripts/init_spec.sh`、`scripts/check_spec.sh`、`scripts/run_gate.sh`、`scripts/update_business_standards.sh`
- 脚本说明：`scripts/README.md`
