import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { withStdioMcp } from "../mcp/stdio-client.mjs";

const args = process.argv.slice(2);
assert.equal(args.length, 2);
assert.equal(args[0], "--config");
const configPath = path.resolve(args[1]);
const config = fs.readFileSync(configPath, "utf8");
const expected = {
  "kafka-policy": ["detect_1c_mechanisms", "select_1c_requirements", "select_yaxunit_requirements", "validate_compliance"],
  "kafka-openviking": ["find", "search", "read", "list", "tree"],
};
for (const [name, names] of Object.entries(expected)) {
  const escapedName = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const blocks = [...config.matchAll(new RegExp(`^\\[mcp_servers\\.${escapedName}\\]\\r?\\n([\\s\\S]*?)(?=^\\[|$(?![\\s\\S]))`, "gm"))];
  assert.equal(blocks.length, 1, `${name} must be registered once`);
  const block = blocks[0][1];
  const value = (key) => JSON.parse(block.match(new RegExp(`^${key} = (.+)$`, "m"))[1]);
  const command = value("command");
  const argv = value("args");
  assert.ok(path.isAbsolute(argv[0]), "MCP script path must be absolute");
  assert.ok(!block.includes("__"), "unresolved placeholder");
  assert.deepEqual(value("enabled_tools"), names);
  const tools = await withStdioMcp(command, argv, async ({ request }) =>
    (await request("tools/list")).tools, { cwd: os.tmpdir(), timeout: 5000 });
  assert.deepEqual(tools.map((item) => item.name), names);
  assert.ok(tools.every((item) => item.annotations.readOnlyHint && !item.annotations.destructiveHint));
}
const reviewer = fs.readFileSync(path.join(path.dirname(configPath), "agents/kafka-reviewer.toml"), "utf8");
assert.match(reviewer, /^name = "kafka-reviewer"$/m);
assert.match(reviewer, /^sandbox_mode = "read-only"$/m);
assert.match(reviewer, /^developer_instructions = """/m);
console.log("installed-managed-mcp: exact registrations, resolved paths, actual stdio tool schemas from foreign cwd, and read-only reviewer passed");
