# Kafka YAxUnit Testability

Load only after a concrete obstacle blocks a deterministic test.

Use this order and stop at the first sufficient seam:

```text
public product API
-> existing semantic fixture or public YAxUnit data API
-> YAxUnit mock supported by the installed version
-> test-only seam in the unit extension
-> separately authorized product seam
-> unsupported
```

Search the `yaxunit` collection only for the unresolved mock/seam API; do not repeat already loaded guidance.

Keep test-only aliases, overrides, or wrappers inside the `unit` extension, minimal, explicitly test-named, and free of business logic. Verify unresolved extension support or signatures through `unit-edt`. Keep the YAxUnit core read-only and do not change product code solely for test convenience before exhausting earlier options.
