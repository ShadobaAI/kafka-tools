# AI Workspace Router

This workspace is centered on the 1C Kafka adapter.

Default routes:

- `adapter\adapter` - main adapter source, docs, metadata, public API, and behavior.
- `tools` - shared automation, local services, schema tooling, and AI context.

AI navigation metadata lives in `tools\ai`.

Startup workflow:

1. Read `tools\ai\workspace-index.md`.
2. Read `tools\ai\repositories.md`.
3. Use `tools\ai\generated\adapter-docs-index.md` before opening adapter docs.
4. Inspect only targeted docs/source files.

Secondary repositories (`adapter\base`, `adapter\examples`, `adapter\yaxunit`, `conversion\KFK`) are validation or support context. Open them only when the task explicitly needs them.

Ignore `builds`, `.settings`, `.metadata`, and generated output unless the task explicitly targets them. Prefer existing scripts, CI, build, and test commands.
