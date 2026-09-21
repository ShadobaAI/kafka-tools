# Requirements for a 1C change

Use the read-only policy MCP as the sole applicability selector. This file specifies the workflow, not a second table of rules.

1. Bind artifact (`bsl`, `query`, or `metadata`), operation, and affected construct before design or review. Obtain the smallest authorized EDT/code-index/BSL LS evidence needed for mechanisms and enclosing structure.
2. Call `detect_1c_mechanisms` with an evidence reference, structured assessments and `format: compact`. Protocol 2.0.0 compact-v1 carries every named `[mechanism, status, evidence]` tuple; verbose legacy output remains supported. Text cues prove only presence; every unknown status must be resolved before selection. An absent assessment needs bounded authoritative evidence, never merely no text cue. Do not read protected `src/**` through a generic file tool.
3. Call `select_1c_requirements` with explicit and classified mechanisms plus the complete detection result. Unknown mechanisms or incomplete coverage block the dependent decision. Retain the returned registry version, exact selectors, strengths, and digest.
4. Retrieve each selected exact ID/heading from v8std once. Require `found=true` and no truncation. Use `v8std_get_section` for corporate headings, `v8std_get_page` for general IDs, or a complete compact body when it covers the selected requirement. Normative conditions and exceptions come from that evidence, never from registry metadata.
5. Before mutation, build a proposal ledger for every selected mandatory and recommended selector: `rule_id`, `selection_digest`, `target`, `status`, `evidence`; all text fields must be nonblank and extra fields are forbidden. Mandatory status is only `passed`; recommended is `passed` or `deviated` with nonblank `reason`. `compliant`/`satisfied` are invalid. Call `validate_compliance` with `phase: proposal` and current detection. Unresolved/violated requirements block mutation, not an invitation to guess a passing status.
6. After mutation, assess actual result mechanisms and validate a fresh ledger with `phase: result` and current detection against the retained selection. M/H repeats detection; L may reuse proven unchanged assessments after checking actual result. Added/removed mechanisms, artifact/operation changes, registry version change or contradiction invalidate selection; retain an explicit reason. Retrieve only newly required or invalidated normative evidence, never unchanged full selectors twice. Focused EDT diagnostics and behavior tests remain separate gates.

Do not repeat a successful equivalent compliance call within a phase (digest,
target, ledger semantics and current applicability unchanged). Legacy callers may
omit phase (defaults to proposal); managed skills always send it explicitly.

For a local change, assess the changed part and enclosing invariants rather than unrelated legacy code. Metadata-only changes skip the BSL baseline, but need applicable metadata standards. Missing registry coverage is not an exemption: resolve it through $1c-standards before deciding.
