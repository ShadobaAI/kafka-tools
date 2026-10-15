# CLI workflow

Use this only for toolkit execution or recovery of the documented editor-state limitation. Resolve the toolkit location from the task environment; no upstream Vanessa checkout is needed. The selected profile remains the source of base, endpoint and paths.

Read the toolkit's `ui/README.md` for setup/start/doctor and timeout details. `ui/vanessa.mjs` provides `list`, `call` and a bounded single-scenario command:

```text
run --profile PROFILE_JSON --feature FEATURE_PATH --scenario EXACT_NAME
```

`run` holds the client lock across initial full readiness, opening, reloading, syntax validation, independent selection/content checks, execution from the beginning and result retrieval. A `completed` operation still requires inspection of the test result before declaring a pass. The CLI does not grant additional permission to change data.

## Editor transition under the same lock

Read the version facts in `vanessa:patterns:execution-debugging`. Do not infer missing execution/recording flags from an abbreviated state or infer editor availability from cached content.

When the manager is in tree mode, invoke `run` with `--editor-transition` and keep stdin open (a PTY can be used). The wait is bounded by 60 seconds and the profile's remaining MCP deadline; allow enough time for observation, preferably `limits.timeoutMs=120000`.

1. Wait for `awaiting_editor_enable`. Verify its reported manager belongs to the selected profile and task.
2. With available computer-use, observe that manager and its actual control “Перейти в Vanessa Editor”. Perform only this mode change and refresh the window.
3. Send exactly one stdin line `{"action":"continue"}`. The CLI retains the lock and MCP session; successful `open_feature_file` then proves editor availability.
4. Inspect the returned syntax, selection, executed text and test results. After the run, restore tree mode through its observed control and obtain full state before another chain.

Do not signal continuation after other UI actions, an ambiguous manager, an expired wait or an unknown outcome. If the needed UI capability is unavailable, leave the workflow blocked rather than inventing missing readiness. A manager restart is not a substitute for this mode transition.
