# Repository Agent Instructions

## Workspace Instructions

Read the required [workspace instructions](../AGENTS.md) before working in this repository. The fixed `KAFKA_PROJECTS_ROOT` layout is required. If the shared file is missing, report a workspace-layout error and stop. The repository-specific rules below supplement and override the shared rules when they conflict.

## Repository Scope

This repository contains CI/release scripts, Docker environments, database utilities, and the XDTO generator. Start with [readme.md](readme.md), then read the README or configuration of the affected component.

## Repository-Specific Rules

- Limit navigation and validation to the affected component directory.
- Use the smallest validation already supported by that component: syntax checks, focused tests, schema validation, or `docker compose config`.
- Do not start long-running infrastructure unless the task requires it.
- Starting a required service and reading logs is allowed only when it does not trigger a prohibited download or destructive state change.
- `docker compose down -v`, `prune`, volume or database deletion, restore, and equivalent destructive operations require explicit user confirmation.
- Do not read or print `.env`, tokens, passwords, or credentials.
- Tracked test credentials are not production secrets, but do not disclose them outside this repository.
- Do not modify generated output, backups, local volumes, or runtime data unless explicitly in scope.

