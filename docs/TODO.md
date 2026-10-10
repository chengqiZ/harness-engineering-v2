# TODO

- [x] v2 机械层重写：`./ai` 从 Codex 编排器（约 1300 行 bash + codex exec 调度）改为纯机械薄编排器（`templates/ai.sh`），删除 prepare_* 提示词渲染脚本与 codex_runner。
- [x] v2 引入 skills 分层：spec-prep / task-dev / pr-prep / serial-task 四个 SKILL.md 取代 6 个 prompt 模板；宿主 agent 通过 `./ai skill <name>` 按需加载。
- [x] v2 质量门禁落地：`scripts/run_gate.sh` + `04-acceptance.md` 的 `Validation Command:` 声明 + `./ai done` 子命令。
- [x] v2 断点恢复保留：Run Checkpoint + `./ai resume <spec-id>`。
- [x] 吸收 v1 未提交改进：编译/构建冒烟先行并入 task-dev skill；`.gitattributes` 的 CRLF 笔误不带入 v2。
- [ ] 评估并执行 `AGENTS.md` 瘦身：仅保留主入口级强约束，把说明性和流程性内容下沉到方案、操作手册和 SOP；前提是至少完成 1 个业务仓库真实试点并完成复盘。
- [ ] v2 真机试点：在 harness-base-test（或新业务仓）用 submodule 升级方式跑 1 个真实需求的 spec → task → gate → acceptance 闭环，验证门禁真实拦截/放行。
- [ ] 双宿主验证：同一 spec 分别在 Claude Code 与 Codex 下走 task-dev skill，确认 skills 措辞对两家 agent 都无歧义。
- [ ] 设计长期多需求管理能力：评估是否新增 `.ai-harness/specs/README.md` 索引、spec 状态字段、增量需求操作入口。
- [ ] 评估 GitLab/GitHub MR API 自动化；前提是确认可用 token、权限边界、失败回滚和审计记录。
- [ ] 补齐 changelog 自动化：评估是否新增 `scripts/create_changelog_entry.sh` 或等价入口，降低每个 PR 合并后的手工记录成本。
- [ ] 完成规范源库版本化发布准备：确认所有规范、模板、脚本、示例和文档均纳入 Git，并打 tag（建议 v2.0.0）供业务仓库 submodule 锁定。
