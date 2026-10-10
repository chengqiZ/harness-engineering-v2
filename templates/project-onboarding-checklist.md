# Project Onboarding Checklist

## Repository Setup

- [ ] `.ai-harness/.ai-standards` submodule added and initialized
- [ ] `.ai-harness/AGENTS.md` created for project-specific exceptions only
- [ ] `.ai-harness/specs/` directory created
- [ ] `.ai-harness/docs/changelog/` directory created

## Process Alignment

- [ ] Team knows rule priority: session > `.ai-harness/AGENTS.md` > `.ai-harness/.ai-standards/AGENTS.md` > `.ai-harness/.ai-standards/standards/*`
- [ ] Team agrees to one PR per `task-id`
- [ ] Team agrees to spec-first workflow

## Template Readiness

- [ ] `01-requirements.md` copied from template
- [ ] `02-design.md` copied when task sizing requires it
- [ ] `03-tasks.md` copied and filled with task schema
- [ ] `04-acceptance.md` copied and ready for final check（v2：含 `Validation Command:` 声明位）
- [ ] PR template configured in repo
- [ ] Changelog template available to contributors

## Validation Readiness

- [ ] Test command baseline documented
- [ ] `Validation Command` 示例可在本机环境真实跑通（`./ai done` 门禁依赖它）
- [ ] Manual verification path documented for non-runnable cases
- [ ] Rollback owner identified for high-risk changes

## First Pilot Scope

- [ ] Pick one low-risk, user-visible requirement
- [ ] Keep first pilot within one `task-id`
- [ ] Avoid auth/billing/data migration on first pilot
