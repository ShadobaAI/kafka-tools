---
name: 1c-code-change
description: Implement or review a scoped 1C source or metadata change through the assigned EDT-MCP. Use for changes and change-focused review, not standalone discovery or API questions.
---

# 1C Code Change

Use the assigned EDT-MCP as the only writer and primary validation source. Review requests are read-only; do not turn findings into edits without authorization.

## Context and change gate

1. Identify the target and requested endpoint. Read the smallest live target and directly affected contracts; use $1c-code-index only for a still-unresolved location or impact question.
2. Before choosing an implementation or judging a change, follow [references/requirements.md](references/requirements.md): run policy MCP detection and selection for artifact, operation and actual mechanisms; retrieve exact selected evidence from v8std. Reuse a valid design-stage selection.
3. Before applying, check the proposed content, enclosing structure and caller impact against those requirements. Submit a complete proposal ledger to `validate_compliance` with current detection. Unresolved applicability, incomplete evidence or a violated mandatory requirement blocks the change.
4. Capture focused EDT diagnostics for the affected objects when supported; a failed/incomplete required baseline blocks mutation. Retain the returned source hash/version and use the live tool's expected-version guard when available.
5. Apply one logically atomic, scoped EDT mutation. For BSL, queries, DCS or forms, load the relevant section of [references/edt-editing.md](references/edt-editing.md). Prefer native method/fragment operations; never rebuild a whole module for a local change.
6. After every mutation, run the same focused EDT diagnostics and artifact-specific validation. Compare with the baseline, detect actual mechanisms again, and submit a result ledger against the retained selection. Reselect only when applicability changed; run the smallest relevant existing behavior test required by the project.

A successful write does not require a redundant reread. Reread when the response is ambiguous, concurrent change is suspected, or validation needs source not returned by the write. Never suppress diagnostics; report material findings and verification gaps.

Database updates, imports, deletes, clean_project, credentials, runtime state and branch operations remain separate authorization scopes. Do not run clean_project as post-write cleanup.
