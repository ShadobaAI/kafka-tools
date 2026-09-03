---
name: bsl-ls-mcp
description: Run repository-local BSL LS diagnostics or semantic navigation for a specific file or symbol when this analyzer's result is needed. Do not load for every BSL change; never replace EDT primary validation or platform authority.
---

# BSL Language Server MCP

Bind the exact repository-local root. Read only analyzer settings that affect the question; never edit them to expose or silence findings.

Analyze only the target symbol or changed BSL files. When a baseline exists, classify findings as new, pre-existing, resolved, not applicable, or coverage-limited. Re-analyze once after a correction; never suppress or loop indefinitely.

Stop when BSL LS answers the semantic/diagnostic question. Do not duplicate it in code-index. Use EDT only for a different authority: live state, metadata, platform truth, mutation, or primary validation.

Report only material diagnostics, classification, configuration effects, and coverage limits.
