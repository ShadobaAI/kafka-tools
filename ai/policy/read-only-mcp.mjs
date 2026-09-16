import path from "node:path";
import readline from "node:readline";
import { fileURLToPath } from "node:url";
import { loadRegistry, select, validateCompliance } from "./selector.mjs";
import { detectMechanisms } from "./detector.mjs";

const modulePath = fileURLToPath(import.meta.url);
const readOnly = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const mechanismInput = {
  mechanisms: { type: "array", items: { type: "string" } },
  classifiedMechanisms: { type: "array", items: { type: "string" } },
  detectedMechanisms: { type: "array", items: { type: "string" } },
  unknownMechanisms: { type: "array", items: { type: "string" } },
  detection: { type: "object" },
};
const tools = [
  { name: "detect_1c_mechanisms", description: "Classify critical mechanisms from authorized evidence. Unproven absence stays unknown.",
    annotations: readOnly, inputSchema: { type: "object", properties: {
      sourceRef: { type: "string" }, sourceText: { type: "string" }, assessments: { type: "object" },
    }, required: ["sourceRef", "assessments"], additionalProperties: false } },
  { name: "select_1c_requirements", description: "Select exact mandatory v8std IDs and corporate headings for a 1C artifact. Unknown mechanisms fail closed.",
    annotations: readOnly, inputSchema: { type: "object", properties: {
      artifact: { enum: ["bsl", "query", "metadata"] }, operation: { enum: ["design", "create", "change", "review"] },
      ...mechanismInput,
    }, required: ["artifact", "operation", "mechanisms", "detection"], additionalProperties: false } },
  { name: "select_yaxunit_requirements", description: "Select exact YAxUnit pattern IDs for a test operation and mechanisms.",
    annotations: readOnly, inputSchema: { type: "object", properties: {
      operation: { enum: ["design", "create", "change", "review", "debug", "migrate", "run", "report"] },
      ...mechanismInput,
    }, required: ["operation", "mechanisms"], additionalProperties: false } },
  { name: "validate_compliance", description: "Verify complete mandatory ledger coverage against the unchanged selection digest and current mechanisms.",
    annotations: readOnly, inputSchema: { type: "object", properties: {
      selection: { type: "object" }, ledger: { type: "array", items: { type: "object" } },
      current: { type: "object" },
    }, required: ["selection", "ledger"], additionalProperties: false } },
];

export function visibleTools() { return tools; }

export function callTool(name, args, registry = loadRegistry()) {
  const tool = tools.find((item) => item.name === name);
  if (!tool) throw new Error("unknown policy tool");
  if (!args || typeof args !== "object" || Array.isArray(args) ||
      Object.keys(args).some((key) => !Object.hasOwn(tool.inputSchema.properties, key)) ||
      tool.inputSchema.required.some((key) => args[key] === undefined)) {
    throw new Error("invalid policy tool arguments");
  }
  if (name === "detect_1c_mechanisms") return detectMechanisms(args);
  if (name === "select_1c_requirements") return select("oneC", args, registry);
  if (name === "select_yaxunit_requirements") return select("yaxunit", args, registry);
  return validateCompliance(args.selection, args.ledger, args.current, registry);
}

function send(message) { process.stdout.write(`${JSON.stringify(message)}\n`); }

function dispatch(message, registry) {
  if (!message || message.jsonrpc !== "2.0" || !message.method || message.id === undefined) return;
  let result;
  if (message.method === "initialize") {
    result = { protocolVersion: message.params?.protocolVersion ?? "2024-11-05", capabilities: { tools: {} },
      serverInfo: { name: "kafka-policy-readonly", version: registry.registryVersion } };
  } else if (message.method === "ping") result = {};
  else if (message.method === "tools/list") result = { tools };
  else if (message.method === "tools/call") {
    try {
      const value = callTool(message.params?.name, message.params?.arguments ?? {}, registry);
      result = { content: [{ type: "text", text: JSON.stringify(value) }], isError: false };
    } catch (error) {
      result = { content: [{ type: "text", text: error.message }], isError: true };
    }
  } else {
    send({ jsonrpc: "2.0", id: message.id, error: { code: -32601, message: "method not found" } });
    return;
  }
  send({ jsonrpc: "2.0", id: message.id, result });
}

if (process.argv[1] && path.resolve(process.argv[1]) === modulePath) {
  try {
    const registry = loadRegistry();
    const lines = readline.createInterface({ input: process.stdin });
    lines.on("line", (line) => {
      try { dispatch(JSON.parse(line), registry); }
      catch (error) { process.stderr.write(`policy-mcp: ${error.message}\n`); }
    });
  } catch (error) {
    process.stderr.write(`policy-mcp: ${error.message}\n`);
    process.exitCode = 1;
  }
}
