# Repository Map

Default to the smallest context: `adapter\adapter` for product work, `tools` for automation/context work.

## Primary Routes

### `adapter\adapter`

Main Kafka adapter project. Use for adapter behavior, metadata, public API, exchange settings, and docs.

For documentation, open `tools\ai\generated\adapter-docs-index.md` first, then the selected page under `adapter\adapter\docs`.

### `tools`

Shared automation and local infrastructure. Use for Docker/Kafka helpers, XDTO/schema tooling, build helpers, and `tools\ai`.

Keep generated AI indexes in `tools\ai\generated`.

## Secondary Routes

Open only when the task needs them:

- `adapter\base` - base 1C configuration, XDTO packages, web services.
- `adapter\examples` - examples extension, fixtures, public API examples.
- `adapter\yaxunit` - YAxUnit tests and behavior validation.
- `conversion\KFK` - Data Conversion 3.1 adapter integration.

Ignore by default:

- base conversion reference under `conversion` - read-only support context.
- `builds`, `.settings`, `.metadata` - generated/local workspace output.

Generated orientation files are in `tools\ai\generated` and are not authoritative.
