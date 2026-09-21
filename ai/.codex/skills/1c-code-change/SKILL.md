---
name: 1c-code-change
description: Implement or review a scoped 1C source or metadata change through the assigned EDT-MCP. Use for changes and change-focused review, not standalone discovery or API questions.
---

# 1C Code Change

Use the assigned EDT-MCP as the only writer and primary validation source. Review requests are read-only; do not turn findings into edits without authorization.

## Context and change gate

1. Identify the target and requested endpoint. Read the smallest live target and directly affected contracts. Before choosing new standalone behavior (helper, query, transformation, validation, parsing, serialization or collection logic), perform the mandatory $1c-code-index reuse-gate. Reuse a compatible existing method. Simple conditions, assignments, elementary loops, local Structure/Array construction, call parameters, short intermediate calculations and call-site-specific glue without independent semantic responsibility are exempt. Judge behavior, not syntax. Indexed location/impact evidence also stays reusable.
2. Before choosing an implementation or judging a change, follow [references/requirements.md](references/requirements.md): run policy MCP detection and selection for artifact, operation and actual mechanisms; retrieve exact selected evidence from v8std. Reuse a valid design-stage selection.
3. Before applying, check the proposed content, enclosing structure and caller impact against those requirements. Submit a complete ledger to `validate_compliance` with `phase: proposal` and current detection. Unresolved applicability, incomplete evidence or a violated mandatory requirement blocks the change.
4. Capture focused EDT diagnostics for the affected objects when supported; a failed/incomplete required baseline blocks mutation. Retain the returned source hash/version and use the live tool's expected-version guard when available.
5. Apply one logically atomic, scoped EDT mutation. For BSL, queries, DCS or forms, load the relevant section of [references/edt-editing.md](references/edt-editing.md). Prefer native method/fragment operations; never rebuild a whole module for a local change.
6. After every mutation, run the same focused EDT diagnostics and artifact-specific validation. Compare with the baseline and assess actual result mechanisms. Submit `phase: result` with current evidence against the retained selection; do not retrieve unchanged normative text again. Reselect only with an explicit applicability invalidation; run the smallest relevant existing behavior test required by the project.

## Process tier

Select conservatively from actual mechanisms, never diff size. The tier changes
repetition, not requirements, authority, diagnostics or concurrency guards.

- **L**: proven test-only delegate/wrapper, registration, internal test helper,
  testability seam or local test infrastructure without a production contract.
  Exclude production public API/method-contract changes, metadata schema, query
  behavior, explicit transactions, privileged/full-access behavior, client/server
  boundary, module persistent state, access/security changes, external protocol,
  cross-repository behavior and destructive operations. Inspect → applicable reuse
  → detect/select → load norms once → proposal compliance → focused EDT baseline
  → atomic mutation → focused EDT result diagnostics → result assessment/compliance
  using unchanged selection/evidence → focused behavior test. Retain complete
  current detection; a proven unchanged assessment can be reused after checking
  actual result and enclosing invariants, without a duplicate detector call.
- **M**: normal behavior changes (including queries); full pre/post detection and
  compliance. Reuse selection and normative evidence when applicability is unchanged.
- **H**: public API, schema, security, destructive or cross-repository behavior;
  full workflow plus required approved SDD, impact/architecture review, fresh
  reviewer, extended validation and repository controls.

Any L exclusion promotes to M or H; unresolved risk promotes to the stricter tier,
and unresolved mandatory mechanism evidence still blocks mutation. A test file is
not proof of low risk. Apply the workspace error taxonomy; safe authorized recovery
continues after validation, infrastructure/contradiction/unsafe/unknown stops.

A successful write does not require a redundant reread. Reread when the response is ambiguous, concurrent change is suspected, or validation needs source not returned by the write. Never suppress diagnostics; report material findings and verification gaps.

Database updates, imports, deletes, clean_project, credentials, runtime state and branch operations remain separate authorization scopes. Do not run clean_project as post-write cleanup.
