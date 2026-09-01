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

Run focused EDT diagnostics after every 1C mutation. Do not disable, suppress, filter out, or hide them. Treat a finding as a confirmed defect only after checking its current source and metadata context. Leave it unfixed only when evidence supports a false-positive classification; otherwise keep it unresolved and include it in the verification result.

## Update audit

- Compare code-index and BSL LS tool surfaces with these allowlists; classify every new tool before exposing it.
- Check EDT `list_toolsets` and use live `get_tool_guide` for changed tools.
- Verify the local v8std general and YAxUnit collections before relying on them; Kafka must not use the corporate collection.
- Re-run a minimal project-aware platform docs, semantic navigation, mutation, and validation smoke test after platform or EDT upgrades.
