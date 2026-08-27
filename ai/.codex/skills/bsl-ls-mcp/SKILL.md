---
name: bsl-ls-mcp
description: Run focused BSL Language Server MCP diagnostics or semantic navigation in a repository where BSL LS is explicitly configured. Use for changed BSL files, focused BSL review, or a specific symbol, reference, call, hover, or type question; do not use for every 1C task, metadata-only work, broad project search, or repositories without this MCP.
---

# BSL Language Server MCP

Use `$1c-routing` invariants. BSL LS complements but does not replace the assigned EDT project model, metadata/query/platform validation, or tests.

## Bind the target

- Use the repository-local `bsl-ls` MCP and its exact configured root. Never substitute another checkout or a broad parent workspace.
- Read only analyzer settings that can affect the current question. Do not edit, bypass, or replace `.bsl-language-server.json` to expose or silence findings.
- If roots or duplicate symbols can make a result ambiguous, constrain or confirm the result through EDT.

## Focused diagnostics

1. When useful, capture a pre-change baseline for each target file.
2. After an authorized change is persisted through EDT, analyze only changed BSL files.
3. Compare diagnostic ID, type, severity, and location; classify findings as new, pre-existing, resolved, not applicable, policy-suppressed, or coverage-limited.
4. Correct confirmed new findings without changing required behavior or weakening safeguards.
5. Re-analyze once after a correction. Report ambiguous or likely false-positive remainder instead of adding suppressions or entering an unbounded correction loop.

Absence of findings is not proof of project-wide coverage. Treat inferred types and language-server references as secondary evidence. For current project state, metadata, platform APIs, persistent mutations, and primary validation, use EDT-MCP.

Report analyzed files, material analyzer configuration effects, diagnostics and classifications, the re-analysis result, and coverage limits.
