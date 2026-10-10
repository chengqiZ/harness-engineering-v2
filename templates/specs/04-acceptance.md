# Acceptance

## Spec ID

- `<spec-id>`

## Validation Commands

<!-- v2：每个 task 至少一条机器可执行判据；`./ai done` 的 run_gate.sh 会逐条执行，全过才放行提交。
     多 task spec 必须按 `### <task-id>` 分节组织（并行模式门禁按分节只跑当前 task 的命令）：

     ### T1

     - Validation Command: `pytest tests/unit -k note_format`

     ### T2

     - Validation Command: `mvn compile` -->

- Validation Command: `<shell command>`

## Functional Acceptance

- [ ] Requirement A verified
- [ ] Requirement B verified

## Non-Functional Acceptance

- [ ] Performance expectation met
- [ ] Security constraints met
- [ ] Logging/observability checks passed

## Code Quality Acceptance

- [ ] Classes/modules, public methods, important fields/state, complex branches, and risk-sensitive logic have meaningful comments where needed
- Comment review result:

## Testing Evidence

- Commands executed:
- Results summary:
- Regression checks:

## Risk And Rollback

- Known risks:
- Rollback plan:

## Final Decision

- Merge decision: `YES/NO`
- Reason:
- Reviewer:
