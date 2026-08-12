---
name: 1c-engineering
description: Execute 1C:Enterprise development, fixes, refactoring, diagnostics, and review with minimal sufficient context, focused verification, applicable project rules and 1C standards, and strict stop conditions. Use for tasks involving BSL, queries, metadata, forms, or related 1C project behavior.
---

# 1C Engineering

Complete the requested 1C task. Context gathering, tool usage, standards lookup, and diagnostics are means to the result, not deliverables.

Follow the current user request, applicable `AGENTS.md`, repository configuration, and specialized skills such as `$edt-mcp`, `$bsl-ls-mcp`, and `$v8std-mcp`. Do not duplicate their tool-specific procedures.

## Operating rules

1. Define the exact change or review scope.
2. Read only enough context to make the next engineering decision.
3. Implement the smallest complete production-quality solution.
4. Run only mandatory or decision-relevant focused checks.
5. Fix confirmed new material problems caused by the change.
6. Re-run only checks affected by that correction.
7. Stop when the task is complete.

Before every additional tool call, identify the concrete question it must answer. Do not make the call if its result cannot materially change the implementation, review conclusion, required validation, or safety decision.

Do not:

- explore neighboring code for general understanding;
- reconstruct the full business process when the task does not require it;
- build broad reference or call graphs without a concrete unresolved dependency;
- collect multiple examples after one sufficiently relevant project pattern is established;
- use multiple tools to confirm the same fact without a material ambiguity;
- repeat a query whose answer is already established in the current task;
- follow related documentation merely because it exists;
- continue analysis only to increase subjective confidence.

Expand scope only when a concrete dependency, contradiction, or material risk blocks a correct decision.

## Tool economy

Use the narrowest applicable source of truth:

- EDT-MCP for the live 1C model, metadata, forms, platform-aware source work, queries, and required EDT validation;
- BSL Language Server for focused BSL diagnostics and semantic questions when applicable;
- v8std for applicable 1C standards and diagnostic interpretation.

If one authoritative source already answered the question, do not query another for reassurance.

When `AGENTS.md` or a specialized skill mandates a check, perform it once at the narrowest sufficient scope. Do not add an equivalent check unless the first result is contradictory, incomplete, or exposes a material issue requiring follow-up.

Do not create a baseline, project-wide scan, broad search, or cross-tool comparison solely because this skill is active.

## Implementation quality

The result must solve the requested task and remain suitable for production maintenance. Prefer the smallest complete change that preserves required behavior and architecture while providing correctness, reliability, security where relevant, adequate performance, readability, maintainability, and compliance with applicable standards.

"Smallest" means the smallest complete high-quality change, not the fewest changed lines.

Do not preserve a bad construction merely to keep the diff small. Do not refactor unrelated code merely because a cleaner design is possible.

### New or changed entities

New identifiers and entities must be justified by the solution and comply with applicable project rules and 1C development standards. This includes metadata objects and material properties, form elements and attributes, procedures, functions, parameters, variables, exported APIs, and other named constructs where standards apply.

Apply relevant v8std requirements for naming, placement, properties, API shape, and design. If the exact applicable rule is not already established by repository instructions or current task context, resolve it once for the relevant category of change and reuse it for equivalent entities in the same task. Do not query v8std separately for every identifier or property.

For metadata, inspect and validate only properties relevant to the object's role and the requested change.

Do not introduce:

- a variable only to silence a diagnostic, mechanically split an expression, or create a meaningless alias;
- a procedure or function only to wrap one call, move a few lines, reduce method length mechanically, or satisfy an analyzer;
- extra BSL code merely to avoid a correct metadata or form change.

A new method must have meaningful responsibility, real reuse, or material structural value and follow applicable rules for naming, parameters, return behavior, export visibility, execution context, and module placement.

If the correct local solution requires changing metadata, a form, an attribute, an element, a handler, or a related property, change the appropriate object through the repository-authorized mechanism.

### Comments

Add comments only when clear code cannot adequately preserve a non-obvious reason, business constraint, compatibility limitation, or technical trade-off. Explain why, not what the code does.

### Performance

Check direct performance consequences of the changed design. Pay particular attention, when applicable, to database or server calls inside loops, extra client/server round trips, repeated retrieval or calculation, poorly scaling operations, heavy queries, large transfers, long transactions, lock duration, and expensive work added to frequently executed code.

Do not start a separate performance investigation without evidence of a material risk. Do not perform speculative micro-optimizations.

## Diagnostics and standards

Diagnostics are evidence, not implementation goals.

For a material diagnostic in the changed scope:

1. Determine whether it represents a real problem in context.
2. Use `$v8std-mcp` only if the required standard or interpretation is not already established.
3. Fix the root cause when confirmed.
4. Re-run the affected focused check once.

Do not modify correct code merely to obtain zero diagnostics.

Do not disable rules, weaken analyzer configuration, add suppressions or exclusions, introduce dummy variables or wrappers, or avoid a required metadata/form change merely to make a diagnostic disappear.

Treat unrelated and pre-existing findings as out of scope unless they materially block the requested task.

After one focused correction, do not enter another correction loop for the same ambiguous or likely false-positive finding. Follow repository or specialized-skill escalation rules and report the limitation concisely.

## Review tasks

For review-only work, inspect the changed scope and its immediate consequences. Understand the functional intent only as far as needed to judge whether the requested behavior is implemented correctly; do not turn the review into business-process archaeology.

Prioritize:

1. failure to meet the requested behavior;
2. functional defects and data-integrity risks;
3. security and reliability problems;
4. material performance problems;
5. applicable standards violations;
6. unnecessary complexity;
7. readability or maintainability issues with practical impact.

Do not create one finding per line or diagnostic. Group findings by root cause. Do not invent findings when the change is acceptable.

## Material changes discovered during work

Do not perform a newly discovered material change outside the original local scope without explicit user confirmation.

A change is material when it significantly affects architecture or component responsibilities, public or cross-module contracts, data model or storage structure, a substantial set of metadata objects, user-visible workflow, substantial form design, transaction model, security or permissions, or a large body of existing implementation.

A small metadata or form change directly required for the requested local fix is not material by itself.

Before a material change, stop implementation and concisely state the confirmed problem, why a local fix is insufficient or materially worse, the recommended change, affected area, and primary risks. Then request explicit confirmation.

## Stop conditions

Stop analysis and finish the task when:

- the requested behavior or review scope has been addressed;
- mandatory focused checks are complete;
- no confirmed new material problem remains in scope;
- remaining diagnostics do not require action for this task;
- additional context would not change the result.

After that, do not perform a final exploratory search, another standards lookup, cross-tool confirmation, neighboring-code review, optional cleanup, speculative refactoring, or extra validation for reassurance.

A sufficient verified result is the completion criterion. Maximum context is not.

## User-facing result

Keep the final response concise and decision-oriented.

For implementation work, report only the material change, important design decision or limitation if any, required validation result, and anything material that remains unverified or blocked.

For review work, report material findings first and then a compact validation summary.

Do not enumerate every tool call, inspected object, changed line, variable, successful internal step, or non-material diagnostic unless explicitly requested.
