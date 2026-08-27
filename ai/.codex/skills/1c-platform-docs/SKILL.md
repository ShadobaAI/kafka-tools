---
name: 1c-platform-docs
description: Verify 1C platform APIs, built-in types, methods, properties, signatures, content assist, and version-specific availability against the assigned live EDT project. Use when an implementation decision depends on the current project's platform model; do not use v8std, code-index, or BSL LS as the primary API reference.
---

# 1C Platform Docs

Use the assigned EDT-MCP and `$1c-routing` invariants.

## Workflow

1. Establish the exact EDT project and obtain its configuration/platform properties when not already known.
2. Call EDT `get_platform_documentation` with `projectName` and the narrowest relevant symbol or topic.
3. Use EDT content assist or semantic symbol information when signatures, context availability, overloads, or client/server placement remain uncertain.
4. If the answer drives an implementation, verify it through the normal EDT mutation and focused validation workflow; documentation alone does not prove project correctness.

code-index and BSL LS may provide supplementary symbol context but are not authoritative for current live state or platform compatibility. v8std explains recommended practice, not whether an API exists. Do not infer version independence or invent unavailable signatures.

Report the verified project/platform context, relevant API fact, and any remaining compatibility uncertainty.
