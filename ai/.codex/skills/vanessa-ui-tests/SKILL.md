---
name: vanessa-ui-tests
description: Research, create, update, run, and debug Vanessa Automation UI scenarios through its MCP. Use for Gherkin features, UI recording, assertions, TestClient, and scenario results; not for product source changes or unit tests.
---

# Vanessa UI tests

Use the selected project's Vanessa profile and its test repository instructions. Resolve the MCP server from that profile; do not infer the base from the server name or reuse another project's TestClient. Product source work follows that project's separate authority route.

## Knowledge and runtime

Use v8std for Vanessa facts, syntax, alternatives and version limits. This skill owns the agent workflow; project profiles own bases, paths and local conventions. Do not copy upstream agent prompts or project examples into general instructions.

Read known recipes through `v8std_get_page`. Require the requested ID, `found=true`, and complete text; use `v8std_get_section` for a known section. Discover an unfamiliar topic with `v8std_search(collections=["vanessa"])`, optionally `types=["pattern"]`. `vanessa:patterns:catalog` maps tasks to related recipes; choose only the topics needed for the current decision. The installed corpus supplies the reference without upstream repositories or websites.

Read returned `v8std:…` references through the same MCP. For truncated text, increase `body_limit` or read the exact section. Do not browse web sources to obtain knowledge supplied by v8std; URLs inside executable examples are literal data.

- Setup or connection: `vanessa:patterns:environment-readiness`.
- UI research or recording: `vanessa:patterns:exploration-recording`.
- New project structure: `vanessa:patterns:project-layout`; feature authoring: `vanessa:patterns:feature-sections` and `vanessa:patterns:steps-assertions`. For reuse, parameterization or data, follow `subscenarios-and-libraries`, `scenario-outlines` or `test-data-strategies` under the same prefix.
- Running or debugging: `vanessa:patterns:execution-debugging`; on an error also `vanessa:patterns:failure-classification` and, for a dialog, `vanessa:patterns:modal-dialogs`.

Tool cards have IDs `vanessa:mcp:<tool>`. They explain semantics and prerequisites; the connected server's complete `tools/list` is authoritative for available tools and argument schemas. Never guess a parameter from a different version. Reuse valid knowledge during the task. An unavailable or incompatible required reference or runtime blocks its dependent operation.

Recipes distinguish verified text from image/video-only details and example-specific conventions. Do not turn an illustrative folder tree, database reset or restriction on Context into a universal requirement. Missing execution details require the actual runtime schema or library, not an invented step.

## Working cycle

1. Read the target feature and its expected behavior. Check the profile, actual manager environment, selected TestClient base, VanessaExt, VAExtension, and current execution/recording state before UI actions. Preserve work belonging to another session.
2. Research only the relevant UI and fixtures. Use form analysis and internal element names. When recording helps, establish ownership, start it before the intended actions and retain the recorded steps and observed checks. Do not create unspecified fixtures or change arbitrary existing records.
3. Update the feature in UTF-8, preserving project conventions unless restructuring is requested. Use the applicable recipe when choosing a new structure. Find standard steps through Vanessa. Preserve the intended assertions; navigation alone does not establish a business result.
4. Reload the edited file in Vanessa and run `check_syntax`. Select and run the affected scenario, using its exact file and name. Do not default to running every loaded feature.
5. Inspect `get_test_results` and correlate it with the edited file, scenario and run. On failure, inspect the current form and a screenshot of the verified TestClient window before choosing a correction. If MCP window discovery fails to identify its PID, stop repeating that call; available computer-use may inspect the independently identified client window. An ambiguous window still blocks visual diagnosis. `paused_modal_dialog` suspends an action chain: handle the observed dialog and continue only its remaining actions.
6. Correct an outdated test from observed evidence. Continue from a step only for diagnosis; acceptance requires a successful run of the affected scenario from its beginning. Do not weaken expected behavior to accommodate a product defect.

The agent performs justified corrections and reruns within the requested task. Stop repeating an unchanged failure. After a mutation timeout, inspect the authoritative state before deciding whether another action is safe. Report infrastructure failure, missing fixtures, and product defects separately from an outdated UI test.

## Local commands and completion

Prefer the selected native MCP. If its tools are unavailable in the chat, use the toolkit against the same profile endpoint. For CLI execution or the Single/MCP editor-state limitation, read [CLI workflow and editor transition](references/cli-workflow.md). It contains the control protocol; facts about the version belong to `vanessa:patterns:execution-debugging`.

Save a JSON run receipt under the profile's results directory: `schemaVersion: 1`, `featurePath`, `featureSha256` (of the executed file), `scenario`, `startedAt`, `finishedAt`, `runtime` (platform/Vanessa/MCP versions actually observed), `syntaxStatus`, `fromBeginning`, `status`, and `resultsFile` pointing to that run's tool result. Correlate the returned scenario and state with this receipt; do not reuse a previous run's result or include credentials.

Report changed features, the actual syntax/run results, unresolved blockers, and the receipt path. A syntax-only check, a run from the middle, a skipped scenario, stale results, or an unfinished run does not count as a passing UI test. Leave the manager and client available unless their closure is part of the task.
