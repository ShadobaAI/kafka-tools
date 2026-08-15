---
name: 1c-engineering
description: Execute scoped 1C:Enterprise implementation, bug fixing, refactoring, diagnostics, or code review with minimal context and focused verification. Use when a task requires an engineering change or assessment of BSL, queries, metadata, forms, or related project behavior. Do not use for simple source reading/navigation or a standalone standards lookup.
---

# 1C Engineering

Complete the requested engineering task; research and diagnostics are inputs, not deliverables.

## Workflow

1. Define the affected behavior, objects, repositories, and required contracts.
2. Obtain only the current context needed for the next decision.
3. Check diagnostics or standards only when required by the task, repository policy, or a material uncertainty.
4. Make the smallest complete production-quality change.
5. Run focused validation for the changed scope.
6. Correct confirmed new material problems and re-run only the affected checks.
7. Stop when the requested result is complete and no in-scope material problem remains.

Before an additional tool call, identify the question it must answer. Skip calls that cannot change the implementation, review conclusion, required validation, or safety decision. Do not collect neighboring code, multiple examples, broad graphs, repeated queries, or cross-tool confirmation for reassurance.

## Route evidence independently

| Need | Source |
|---|---|
| Current EDT model, 1C source/metadata, platform-aware mutation or validation | `$edt-mcp` |
| Applicable 1C standard or diagnostic interpretation | `$v8std-mcp` |
| Focused BSL analysis in a repository where it is configured and required | `$bsl-ls-mcp` |

Activate only the needed specialized skill. One authoritative answer is sufficient unless it is contradictory, incomplete, or exposes a material risk.

## Engineering decisions

- Preserve required behavior, architecture, compatibility, security, permissions, transactions, data integrity, and established project style.
- Add identifiers, methods, metadata, form elements, comments, or abstractions only when they carry real responsibility or information.
- Check direct performance consequences when the change can add repeated calls, heavy queries, large transfers, long transactions, locks, or expensive hot-path work; avoid speculative optimization.
- Keep unrelated cleanup and pre-existing findings out of scope.

## Diagnostics and retry policy

Treat diagnostics as evidence, not as a zero-count target. Confirm applicability in the actual code and project context before changing behavior. Never weaken analyzer configuration, add suppressions, or introduce meaningless code merely to silence a finding.

After one reasoned correction, re-run the focused check once. If the same finding remains ambiguous or likely false-positive, classify and report it according to repository policy; do not enter a speculative correction loop.

For review-only work, report material defects and risks by root cause, prioritizing requested behavior, correctness and data integrity, security and reliability, performance, applicable standards, and maintainability.

Finish without exploratory searches, optional cleanup, or extra validation once the requested scope and mandatory focused checks are complete. Report material changes or findings, performed verification, and anything important left unverified.
