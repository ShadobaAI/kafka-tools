# MCP tool policy

## code-index read-only allowlist

Only these tools are permitted. New code-index tools default to deny:

```text
get_function
get_callers_bsl
get_callees_bsl
get_call_tree_bsl
find_symbol
read_file
grep_code
health
get_object_structure
get_form_handlers
get_event_subscriptions
find_path_bsl
search_terms
get_data_links
find_data_path
get_register_writers
get_object_profile
find_references
bsl_sql
```

## BSL LS read-only allowlist

```text
analyze_file
document_symbols
find_references
call_hierarchy
hover
definition
type_info
global_member_info
global_member_search
type_at_position
```

## EDT policy

Disable `git` and `ask_workmate`.

Require explicit context and approval for:

```text
delete_metadata
delete_project
delete_infobase
update_database
import_configuration_from_xml
clean_project
set_infobase_credentials
set_variable
evaluate_expression
create_git_branch
switch_git_branch
set_branch_infobase
```

Normal `write_module_source`, `create_metadata`, and `modify_metadata` operations are controlled by task scope, current-state inspection, lost-update protection when available, and mandatory focused EDT validation.

### Mixed and runtime tools

The repository-local EDT configs expose the server's tools except `git` and `ask_workmate`; toolset visibility is managed in EDT. Keep the following overrides aligned across all three owners. Codex approval overrides address a whole tool, not its action/mode.

| Tool | Codex approval | Operational boundary |
|---|---|---|
| `compare_configurations` | `approve` | Comparison only; exact project/revisions/scope, retain the job and comparison IDs. Release only this task's finished comparison. |
| `get_comparison_node` | `approve` | Bounded read of a retained comparison. |
| `dcs` | `prompt` | `get`/`options` are reads; writes use the code-change gate, and removal/reset needs the corresponding explicit scope. The tool also exposes destructive actions. |
| `merge_rules` | `prompt` | Read or write a rules file; never executes a merge. Overwriting and validation must follow the comparison workflow. |
| `set_error_breakpoint` | `prompt` | Changes workspace-wide debugger state, including other projects. Preserve the prior state. |
| `launch` | `prompt` | Can update the database or terminate an existing client; select parameters from the authorized runtime scope. |

Use [comparison.md](comparison.md), [runtime.md](runtime.md), and the code-change skill's editing reference for the actual workflow. Tool approval does not establish source/project readiness or successful validation.

Run focused EDT diagnostics after every 1C mutation. Do not disable, suppress, filter out, or hide them. Treat a finding as a confirmed defect only after checking its current source and metadata context. Leave it unfixed only when evidence supports a false-positive classification; otherwise keep it unresolved and include it in the verification result.

## Update audit

- Compare code-index and BSL LS tool surfaces with these allowlists; classify every new tool before exposing it.
- Check EDT `list_toolsets` and use live `get_tool_guide` for changed tools.
- Verify only the required v8std collections: general standards, corporate:work:* policy, or YAxUnit. Kafka uses corporate work policy; do not broaden it to unrelated corporate namespaces.
- For a toolkit/configuration upgrade, verify `initialize`, `get_server_status`, `tools/list`, `list_toolsets` and the changed live guides without touching project data. Inspect structured results and embedded guide resources, not only text acknowledgments. Preserve the MCP session ID for subsequent HTTP requests; after a server restart initialize a new session.
- Project-aware platform docs, navigation, mutation and diagnostic smoke checks belong to an explicitly scoped ready test project. Do not mutate business source or launch tests merely to audit tool availability; report that runtime coverage separately.
