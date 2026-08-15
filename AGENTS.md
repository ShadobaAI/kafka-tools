# Repository Agent Instructions

Apply the required [workspace instructions](../AGENTS.md). The rules below are this repository's delta and override shared rules on conflict.

This repository contains CI/release scripts, Docker environments, database utilities, and the XDTO generator. Limit navigation and validation to the affected component and use its documented README or configuration.

- Use the smallest supported component check: syntax, focused tests, schema validation, or `docker compose config`.
- Do not start long-running infrastructure unless required. Starting a required service and reading logs is allowed only when it triggers neither a prohibited download nor destructive state change.
- `docker compose down -v`, `prune`, volume or database deletion, restore, and equivalent destructive operations require explicit user confirmation.
- Do not read or print `.env`, tokens, passwords, or credentials. Do not disclose tracked test credentials outside this repository.
- Do not modify generated output, backups, local volumes, or runtime data unless explicitly in scope.
