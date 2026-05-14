# Workspace Index

Fast route for Codex in this workspace.

Primary context:

- `adapter\adapter` - the product: source, metadata, public API, and documentation.
- `tools` - automation and this AI context layer.

Adapter documentation is first-class context. Before opening docs directly, use `tools\ai\generated\adapter-docs-index.md` to choose the smallest relevant page under `adapter\adapter\docs`.

Use support repositories only when needed for the current change:

- `adapter\base` - base 1C configuration assumptions.
- `adapter\tester` - API examples and manual repro context.
- `adapter\yaxunit` - automated tests.
- `conversion\KFK` - Data Conversion 3.1 integration.

Normal loading order:

1. `tools\ai\repositories.md`
2. `tools\ai\generated\adapter-docs-index.md` for adapter docs work
3. Targeted docs/source files

Do not scan the whole workspace. Ignore `builds`, `.settings`, `.metadata`, and generated files by default.
