# Kafka YAxUnit Workflow

Use only for creating, changing, running, or debugging tests.

## Create or change

1. Define observable behavior, context, inputs, outcome, and isolation.
2. Inspect the product through its bound alias; inspect tests through `kfk-unit`. Use `unit-edt` only for live facts or mutation.
3. Reuse one semantic fixture when suitable; otherwise use the narrowest public `ЮТест.Данные()` API. Do not scan for alternatives after a sufficient option is found.
4. Use `kfk-yaxunit` only to locate an unresolved installed definition or real usage. Ask `unit-edt` for the exact signature only when it remains unknown or conflicts with v8std.
5. Mutate only the `unit` extension through `unit-edt`, then run focused diagnostics.

## Authoring gate

Before runtime, verify once that registration is declarative, module role and naming satisfy the loaded contract, setup is deterministic and isolated, one behavior is exercised, and assertions satisfy the loaded pattern. Fix findings and revalidate.

Format every fluent YAxUnit chain according to the hierarchy of its API receivers/builders, regardless of method names. Align sibling calls made on the same receiver; indent a call one tab further when it operates on a child receiver returned or selected by the preceding API level, and restore the parent's indentation when the chain returns to that receiver. Determine the level from the loaded YAxUnit contract or exact signature, not from the spelling of a method, and do not align every leading dot mechanically:

```bsl
ЮТТесты
	.ДобавитьТестовыйНабор()
		.Перед()
		.ДобавитьСерверныйТест()
```

## Run or debug

Run the narrowest scope. Treat unexpected `0` tests as failure. Classify a failure as test, product, data/environment, or runner before changing code; inspect only the source needed by that classification.
