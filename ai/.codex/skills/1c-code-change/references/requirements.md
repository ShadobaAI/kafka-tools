# Requirements for a 1C change

Use the read-only policy MCP as the sole applicability selector. This file specifies the workflow, not a second table of rules.

1. Bind artifact (`bsl`, `query`, or `metadata`), operation, and affected construct before design or review. Obtain the smallest authorized EDT/code-index/BSL LS evidence needed for mechanisms and enclosing structure.
2. Call `detect_1c_mechanisms` with an evidence reference and structured assessments. Text cues prove only presence. Resolve every `unknownMechanisms` entry using the assigned authority before selection; an absent assessment needs evidence for the bounded target. Do not read protected `src/**` through a generic file tool.
3. Call `select_1c_requirements` with explicit and classified mechanisms plus the complete detection result. Unknown mechanisms or incomplete coverage block the dependent decision. Retain the returned registry version, exact selectors, strengths, and digest.
4. Retrieve each selected exact ID/heading from v8std once. Require `found=true` and no truncation. Use `v8std_get_section` for corporate headings, `v8std_get_page` for general IDs, or a complete compact body when it covers the selected requirement. Normative conditions and exceptions come from that evidence, never from registry metadata.
5. Before mutation, build a proposal ledger for every selected mandatory and recommended selector: `rule_id`, `selection_digest`, `target`, `status`, `evidence`; a recommended `deviated` entry also needs `reason`. Call `validate_compliance` with current detection. Mandatory `violated` or `unresolved` blocks mutation. A successful tool call alone is not a compliance check.
6. After mutation, repeat detection on actual result from authorized evidence and validate a fresh result ledger against the retained selection. Added mechanisms require reselection and exact retrieval of new requirements. Do not silently drop an earlier mechanism; changed applicability needs an explicit reason and new digest. Focused EDT diagnostics and behavior tests are separate gates.

For a local change, assess the changed part and enclosing invariants rather than unrelated legacy code. Metadata-only changes skip the BSL baseline, but need applicable metadata standards. Missing registry coverage is not an exemption: resolve it through $1c-standards before deciding.
