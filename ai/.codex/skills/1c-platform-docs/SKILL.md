---
name: 1c-platform-docs
description: Verify 1C platform APIs, built-in types, methods, properties, signatures, content assist, and version-specific availability against the assigned live EDT project. Use when an implementation decision depends on the current project's platform model; do not use v8std, code-index, or BSL LS as the primary API reference.
---

# 1C Platform Docs

Use the assigned EDT-MCP and `$1c-routing` invariants.

## Workflow

1. Reuse the established EDT project, platform context, and API facts from this session. Re-establish them only after a relevant state change, conflicting evidence, or when the needed fact is live-state dependent.
2. Call EDT `get_platform_documentation` with `projectName` and the narrowest relevant symbol or topic.
3. Stop when that authoritative result answers the question. Use EDT content assist or semantic symbol information only when signatures, context availability, overloads, client/server placement, or a missing member remain unresolved.
4. If the answer drives an implementation, verify the resulting change through the normal EDT mutation and focused validation workflow; documentation alone does not prove project correctness.

Do not corroborate a sufficient platform-documentation result with code-index, BSL LS, web search, or content assist merely for confidence. Those routes may add project symbol context but are not authoritative for platform compatibility. v8std explains recommended practice, not whether an API exists. Do not infer version independence or invent unavailable signatures.

Report the relevant API fact and remaining compatibility uncertainty; omit already established project/platform context unless it affects the conclusion.
