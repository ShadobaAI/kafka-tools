# Runtime launch and breakpoints

Consult live guides for `launch`, `set_breakpoint` or `set_error_breakpoint` when used. These operations need the actual application/debugging scope; a source edit alone does not authorize them.

## Launch

Use `launch` with explicit `mode="run"` or `mode="debug"`; Attach configurations support debug only. Select one exact launch configuration or the project/application pair obtained from EDT.

Set launch side effects from the authorized scope. `updateBeforeLaunch` defaults to true and can update the database; `externalInfobaseChanges` defaults to `override`, which can overwrite external changes. Without that authorization use `updateBeforeLaunch=false` and `externalInfobaseChanges="cancel"`; a resulting modal or refusal is not permission to update/import. Keep `standaloneServerPortConflict="cancel"` unless changing server ports is authorized. `restartIfRunning=true` terminates a live client and needs restart scope.

`alreadyRunning:true` means no new launch occurred. A returned launch request or ID is not proof of client startup, attachment or successful database update; inspect the returned state and the appropriate follow-up status. Do not repeat a launch just to discover its status.

## Breakpoints

- Read relevant `list_breakpoints` state before changing existing entries, and retain IDs and original settings for cleanup.
- `set_breakpoint` updates an existing line breakpoint; omitted `condition`/`hitCount` clear those settings. Check `degraded`, `conditionApplied` and `hitCountApplied`; a marker is not proof the runtime will stop. A condition is runtime BSL evaluation, so keep it within the authorized debugging scope.
- `set_error_breakpoint` affects the entire EDT workspace, not one project. Use only when that scope is authorized. Omitting `exceptionMessage` preserves its filter; an empty string clears it. `enabled=false` preserves the saved filter.
- Restore the actual prior state after a temporary change; do not blindly re-enable after a test. `notFound` means no saved breakpoint existed. Pre-existing disabled or mixed entries must not become enabled. Retain every returned `breakpointIds` entry; the singular ID may cover only one duplicate. Do not delete user breakpoints as cleanup; report any state that cannot be faithfully restored through the available API.
