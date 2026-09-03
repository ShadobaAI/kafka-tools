# Kafka YAxUnit Workflow

Use for designing, creating, changing, reviewing, running or debugging tests. Read-only tasks do not authorize mutation or require runtime checks merely to give a conclusion.

## Create or change

1. Define observable behavior, context, inputs, outcome, and isolation.
2. Inspect the product through its bound alias; inspect tests through `kfk-unit`. Use `unit-edt` only for live facts or mutation.
3. Reuse one semantic fixture when suitable; otherwise use the narrowest public `ЮТест.Данные()` API. Do not scan for alternatives after a sufficient option is found.
4. Use `kfk-yaxunit` only to locate an unresolved installed definition or real usage. Ask `unit-edt` for the exact signature only when it remains unknown or conflicts with v8std.
5. Mutate only the `unit` extension through `unit-edt`, then run focused diagnostics.

## Authoring gate

Before accepting a design/review or applying a change, check the applicable items below. Recheck affected items on the result before runtime; do not defer mandatory authoring rules until after writing.

- Enclosing structure, method placement, role and naming satisfy applicable general, work and test contracts together; a minimal pattern is not a full module template.
- Registration is declarative; registered test methods satisfy their export/context contract.
- Setup is deterministic and isolated.
- The test exercises one observable behavior.
- Assertions match the loaded pattern.
- Every multiline fluent chain passes the logical-ownership gate in `SKILL.md`.

For authorized changes, fix findings and revalidate affected checks. For read-only review, report findings without edits. Passing runtime tests does not establish structural or normative compliance.

## Run or debug

Run the narrowest scope. Treat unexpected `0` tests as failure. Classify a failure as test, product, data/environment, or runner before changing code; inspect only the source needed by that classification.
