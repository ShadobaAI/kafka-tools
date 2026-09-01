---
name: 1c-code-index
description: Search and analyze indexed 1C source and metadata through read-only code-index when slight staleness is acceptable. Use for discovery, structure, references, graphs, and impact; never for writes, platform APIs, live truth, or primary diagnostics.
---

# 1C code-index

Bind the exact alias from the workspace mapping; never infer one from filesystem proximity. Call `health` only when status/freshness is unknown or a state change/failure invalidated it. Report stale, incomplete, or errored coverage.

Use the first sufficient route:

```text
structured metadata/symbol query
-> exact function/symbol
-> bounded BSL callers/callees/references at depth 1
-> bounded grep/read_file
-> bounded bsl_sql only when no named tool fits
```

Prefer BSL-specific call tools. Empty call graphs cover indexed static calls only; check string dispatch only when plausible. `get_register_writers` covers declarative edges only. For large modules, inspect the symbol inventory and selected bodies, never the full module first.

## Authority boundary

Stop when the indexed answer is sufficient; do not repeat it in EDT. Use EDT only for a different need: the exact pre-mutation target, live state, platform truth, primary diagnostics, or doubtful/absent index facts. EDT wins on conflict.

Report only the result and material truncation, coverage, health, or staleness limits.
