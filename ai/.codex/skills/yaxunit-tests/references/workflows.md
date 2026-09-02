# Kafka YAxUnit Workflow

Use only for creating, changing, running, or debugging tests.

## Create or change

1. Define observable behavior, context, inputs, outcome, and isolation.
2. Inspect the product through its bound alias; inspect tests through `kfk-unit`. Use `unit-edt` only for live facts or mutation.
3. Reuse one semantic fixture when suitable; otherwise use the narrowest public `ЮТест.Данные()` API. Do not scan for alternatives after a sufficient option is found.
4. Use `kfk-yaxunit` only to locate an unresolved installed definition or real usage. Ask `unit-edt` for the exact signature only when it remains unknown or conflicts with v8std.
5. Mutate only the `unit` extension through `unit-edt`, then run focused diagnostics.

## Authoring gate

Before runtime, reject the change until all checks pass:

- Registration is declarative; module role and naming match the loaded contract.
- Setup is deterministic and isolated.
- The test exercises one observable behavior.
- Assertions match the loaded pattern.
- Every multiline fluent chain passes the receiver-depth gate in `SKILL.md`.

Fix findings, then revalidate the gate.

## Run or debug

Run the narrowest scope. Treat unexpected `0` tests as failure. Classify a failure as test, product, data/environment, or runner before changing code; inspect only the source needed by that classification.
