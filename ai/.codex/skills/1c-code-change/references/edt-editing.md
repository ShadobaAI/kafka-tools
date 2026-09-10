# EDT editing contracts

Use the assigned server's live schema and `get_tool_guide` for payload details. These workflow rules complement the requirements and diagnostic gates in the parent skill.

## BSL

- Read the exact method with `read_method_source`; its `contentHash` guards the whole module. Pass that opaque token as `write_module_source.expectedHash` for edits to existing content. Do not derive it from the method text or reuse it after a write.
- Choose `replaceMethod` for a complete method replacement, `insertBefore`/`insertAfter` for one new method beside an existing `methodName` anchor, or `searchReplace` for a smaller uniquely matching fragment. All three method modes require `methodName` and `expectedHash`.
- A method-mode `source` contains exactly one complete procedure/function. `replaceMethod` includes the old method's leading documentation and annotations in its replaced span: preserve the required comments and directives in the replacement. Keep the name and procedure/function kind. Inserts go outside the anchor's annotation/documentation block.
- Duplicate anchors, unsupported declaration shapes, syntax failures and stale hashes are refusals, not reasons to fall back to a whole-module rewrite, `overwrite=true` or `skipSyntaxCheck=true`. Resolve the reported obstacle within scope; follow the project failure gate for a failed required operation.
- Address the module with either `modulePath` or `objectName` plus its module selectors, never both. Only `replace` creates a missing module file; creating that file does not adopt extension metadata.
- The write's block-balance check is not full EDT validation. Run the same focused diagnostics after the write. A documented hash check is lost-update protection; do not infer strict atomic compare-and-write from the parameter alone.

## Queries and DCS

- Validate the complete changed query with `validate_query` in its owning `projectName`; an extension uses the union of its own and base metadata. Use `dcsMode=true` for a DCS query and inspect `valid`, not merely `success`. Static validation does not prove rows, totals, access rights or performance.
- Use `dcs` for supported schema, variant, dynamic-list and form conditional-appearance edits. Start with `get` at the exact root, then read only relevant returned pointers/nodes; a root summary is not the complete query or settings. Use `options` when the writable vocabulary is unknown.
- Retain the returned `hash` as `expectedHash` for mutations. It is mandatory for `replace`, `remove` and any index-addressed edit. Copy returned pointers instead of inventing indexes, and refresh addresses/hash after a mutation.
- Prefer `update` for an existing node or `upsert` when creation is intended. `replace` resets omitted values and clears omitted collections; use it only when that entire replacement is in scope. `remove` needs explicit deletion authorization. Do not supply `body` for `get`, `options` or `remove`.
- Charts and nested data sets have no typed authoring support. Do not route an unsupported operation through generic metadata or filesystem editing. For an authorized whole-schema transfer, consult the guide's XML round-trip: read all pages using `nextOffset`, require an unchanged hash, then send one complete XML document through `dcs` with the destination hash. Never submit a chunk or mix XML with structured members.
- After a DCS mutation, inspect the affected nodes, validate the final query where applicable, and compare focused EDT diagnostics with the baseline.

## Metadata and forms

Read `get_metadata_details` at the smallest owning node; use `full=true` only when actual collection members are required. Resolve objects by programmatic name before writing: synonym search does not make synonyms valid write identifiers.

For visual acceptance use the appropriate form snapshot/screenshot alongside model diagnostics. An empty image is not proof of an empty form. Interpret `get_server_status.formRenderFlags.atStartup` as startup state, not current effective rendering; `requested` and `forcedAtRuntime` do not prove that a buffer exists. Inspect the renderer's reported outcome before proposing configuration changes.
