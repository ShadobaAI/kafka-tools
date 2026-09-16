import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { visibleTools as policyTools } from "../policy/read-only-mcp.mjs";
import { visibleTools as openVikingTools } from "../openviking/read-only-mcp.mjs";

const aiRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const bytes = (relative) => fs.statSync(path.join(aiRoot, relative)).size;
const skillStats = (relative) => {
  const root = path.join(aiRoot, relative);
  const paths = fs.readdirSync(root).map((name) => path.join(root, name, "SKILL.md"))
    .filter((item) => fs.existsSync(item));
  const bodies = paths.map((item) => fs.readFileSync(item, "utf8"));
  return { count: paths.length, bodyBytes: paths.reduce((sum, item) => sum + fs.statSync(item).size, 0),
    metadataBytes: bodies.reduce((sum, body) => sum + Buffer.byteLength(body.match(/^---\r?\n[\s\S]*?\r?\n---\r?\n/)?.[0] ?? ""), 0) };
};

const report = {
  kind: "static-byte-inventory; not billed tokens",
  workspaceAgentsBytes: bytes("AGENTS.md"),
  managedSkills: skillStats(".codex/skills"),
  oldRequirementsTableBytes: bytes("tests/legacy-requirements.md"),
  managedRequirementsWorkflowBytes: bytes(".codex/skills/1c-code-change/references/requirements.md"),
  managedMcpConfigBytes: bytes(".codex/config.toml"),
  newToolSchemaBytes: Buffer.byteLength(JSON.stringify([...policyTools(), ...openVikingTools()])),
  actualRenderedCodexSchemaBytes: null,
  actualSessionInputTokens: null,
};
process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
