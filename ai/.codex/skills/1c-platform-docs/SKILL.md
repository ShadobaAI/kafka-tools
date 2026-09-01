---
name: 1c-platform-docs
description: Verify 1C platform APIs and version-specific availability through the assigned EDT project. Use for built-in types, members, signatures, contexts, and compatibility; never use v8std, code-index, or BSL LS as platform authority.
---

# 1C Platform Docs

Call EDT `get_platform_documentation` with `projectName` and the narrowest known symbol/topic. Use EDT content assist or semantic information only for a still-unresolved overload, context, client/server placement, or missing member.

Stop when EDT answers the question. Do not repeat the lookup in v8std, code-index, BSL LS, or web search. Reuse established API facts until the project/platform context changes or evidence conflicts.

Documentation proves API availability, not project correctness. If it drives a change, hand off to `$1c-code-change` for mutation and validation. Report only the API fact and material compatibility uncertainty.
