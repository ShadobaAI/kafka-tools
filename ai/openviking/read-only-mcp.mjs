import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { fileURLToPath } from "node:url";
import { documentUri, loadManifest, localClient, reconcile } from "./git-sync.mjs";

const modulePath = fileURLToPath(import.meta.url);
const namespace = loadManifest().manifest.namespace;
const readonly = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const tools = [
  {
    name: "find", description: "Find bounded historical or documented Kafka context at L0/L1. Source: committed Git documents only.",
    annotations: readonly,
    inputSchema: { type: "object", properties: {
      query: { type: "string", minLength: 1 }, limit: { type: "integer", minimum: 1, maximum: 10 },
    }, required: ["query"], additionalProperties: false },
  },
  {
    name: "search", description: "Assemble a bounded context from committed Git document abstracts; max_tokens is required.",
    annotations: readonly,
    inputSchema: { type: "object", properties: {
      query: { type: "string", minLength: 1 }, max_tokens: { type: "integer", minimum: 100, maximum: 3000 },
      limit: { type: "integer", minimum: 1, maximum: 10 },
    }, required: ["query", "max_tokens"], additionalProperties: false },
  },
  {
    name: "read", description: "Read one exact Git-backed OpenViking URI at L2, with a required context budget.",
    annotations: readonly,
    inputSchema: { type: "object", properties: {
      uri: { type: "string" }, max_tokens: { type: "integer", minimum: 100, maximum: 8000 },
    }, required: ["uri", "max_tokens"], additionalProperties: false },
  },
  {
    name: "list", description: "List one directory under the Kafka Git context namespace.",
    annotations: readonly,
    inputSchema: { type: "object", properties: {
      uri: { type: "string" }, limit: { type: "integer", minimum: 1, maximum: 100 },
      offset: { type: "integer", minimum: 0, maximum: 10000 },
    }, required: ["uri"], additionalProperties: false },
  },
  {
    name: "tree", description: "Show a bounded subtree of Kafka Git context.",
    annotations: readonly,
    inputSchema: { type: "object", properties: {
      uri: { type: "string" }, level_limit: { type: "integer", minimum: 1, maximum: 3 },
      node_limit: { type: "integer", minimum: 1, maximum: 200 },
    }, required: ["uri"], additionalProperties: false },
  },
];

function parseArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    if (!["--workspace-root", "--state-dir"].includes(name) || !value || options[name]) {
      throw new Error("expected --workspace-root PATH --state-dir PATH");
    }
    options[name] = value;
  }
  if (!options["--workspace-root"] || !options["--state-dir"]) {
    throw new Error("missing workspace root or state directory");
  }
  return { workspaceRoot: path.resolve(options["--workspace-root"]), stateDir: path.resolve(options["--state-dir"]) };
}

function integer(value, fallback, min, max, label) {
  const result = value === undefined ? fallback : value;
  if (!Number.isInteger(result) || result < min || result > max) throw new Error(`invalid ${label}`);
  return result;
}

function exactUri(value) {
  if (typeof value !== "string" ||
      (value !== namespace && !value.startsWith(`${namespace}/`)) ||
      value.includes("..") || /[%?#\\]/.test(value)) throw new Error("URI outside Git-backed Kafka context");
  return value;
}

function textBudget(value, maxTokens) {
  // Conservative character cap. Never pass an unbounded provider response into model context.
  const cap = maxTokens * 3;
  if (value.length > cap) throw new Error(`document exceeds ${maxTokens} token budget; select a narrower source`);
  return value;
}

export function visibleTools() { return tools; }

function allowedUris(stateDir) {
  const state = JSON.parse(fs.readFileSync(path.join(stateDir, "state.json"), "utf8"));
  if (state.schemaVersion !== 1 || !state.repositories || typeof state.repositories !== "object") {
    throw new Error("OpenViking source state is incomplete");
  }
  const allowed = new Set();
  for (const [repo, item] of Object.entries(state.repositories)) {
    for (const file of Object.keys(item.files ?? {})) allowed.add(documentUri(namespace, repo, file));
  }
  return allowed;
}

function allowedEntry(item, allowed) {
  if (typeof item.uri !== "string") return false;
  if (!item.isDir) return allowed.has(item.uri);
  return item.uri === namespace || [...allowed].some((uri) => uri.startsWith(`${item.uri.replace(/\/$/, "")}/`));
}

export async function callTool(name, args, { client, workspaceRoot, stateDir }) {
  const definition = tools.find((tool) => tool.name === name);
  if (!definition) throw new Error("unknown read-only tool");
  if (!args || typeof args !== "object" || Array.isArray(args) ||
      Object.keys(args).some((key) => !Object.hasOwn(definition.inputSchema.properties, key)) ||
      definition.inputSchema.required.some((key) => args[key] === undefined)) {
    throw new Error("invalid tool arguments");
  }
  const result = await reconcile({ workspaceRoot, stateDir, client, allowRebuild: false });
  if (result.status !== "ready") throw new Error("OpenViking source is stale");
  const allowed = allowedUris(stateDir);
  if (name === "find" || name === "search") {
    if (typeof args.query !== "string" || !args.query.trim() || args.query.length > 1000) throw new Error("invalid query");
    const limit = integer(args.limit, 5, 1, 10, "limit");
    const response = await client.request("POST", "/api/v1/search/find", {
      query: args.query, target_uri: namespace, context_type: ["resource"], limit,
    });
    if (response.status !== "ok" || !Array.isArray(response.result?.resources)) {
      throw new Error("OpenViking returned incomplete search results");
    }
    const entries = response.result.resources.filter((item) =>
      allowed.has(item.uri)).slice(0, limit).map((item) => ({
        uri: item.uri, level: item.level, score: item.score,
        abstract: typeof item.abstract === "string" ? item.abstract.slice(0, 800) : "",
      }));
    if (name === "find") return { entries, source: namespace, status: "ready" };
    const maxTokens = integer(args.max_tokens, undefined, 100, 3000, "max_tokens");
    const assembled = [];
    let remaining = maxTokens * 3;
    for (const item of entries) {
      const fragment = `${item.uri}\n${item.abstract}\n`;
      if (fragment.length > remaining) break;
      assembled.push(fragment);
      remaining -= fragment.length;
    }
    return { text: assembled.join("\n"), used_budget_chars: maxTokens * 3 - remaining,
      max_tokens: maxTokens, source: namespace, status: "ready" };
  }
  const uri = exactUri(args.uri);
  if (name === "read") {
    if (!allowed.has(uri)) throw new Error("read requires an exact committed Markdown document");
    const maxTokens = integer(args.max_tokens, undefined, 100, 8000, "max_tokens");
    const response = await client.request("GET", `/api/v1/content/read?${new URLSearchParams({ uri })}`);
    if (response.status !== "ok" || typeof response.result !== "string") throw new Error("incomplete document read");
    return { uri, content: textBudget(response.result, maxTokens), status: "ready" };
  }
  if (name === "list") {
    const limit = integer(args.limit, 50, 1, 100, "limit");
    const offset = integer(args.offset, 0, 0, 10000, "offset");
    const response = await client.request("GET", `/api/v1/fs/ls?${new URLSearchParams({ uri, limit, offset })}`);
    if (response.status !== "ok" || !Array.isArray(response.result)) throw new Error("incomplete directory listing");
    return { entries: response.result.filter((item) => allowedEntry(item, allowed)).slice(0, limit), status: "ready" };
  }
  const levelLimit = integer(args.level_limit, 3, 1, 3, "level_limit");
  const nodeLimit = integer(args.node_limit, 100, 1, 200, "node_limit");
  const response = await client.request("GET", `/api/v1/fs/tree?${new URLSearchParams({ uri,
    level_limit: levelLimit, node_limit: nodeLimit })}`);
  if (response.status !== "ok" || !Array.isArray(response.result)) throw new Error("incomplete directory tree");
  return { entries: response.result.filter((item) => allowedEntry(item, allowed)).slice(0, nodeLimit), status: "ready" };
}

function send(message) { process.stdout.write(`${JSON.stringify(message)}\n`); }

async function dispatch(message, context) {
  if (!message || message.jsonrpc !== "2.0" || !message.method) return;
  const id = message.id;
  if (id === undefined) return;
  try {
    let result;
    if (message.method === "initialize") {
      result = { protocolVersion: message.params?.protocolVersion ?? "2024-11-05",
        capabilities: { tools: {} }, serverInfo: { name: "kafka-openviking-readonly", version: "1.0.0" } };
    } else if (message.method === "ping") result = {};
    else if (message.method === "tools/list") result = { tools };
    else if (message.method === "tools/call") {
      try {
        const value = await callTool(message.params?.name, message.params?.arguments ?? {}, context);
        result = { content: [{ type: "text", text: JSON.stringify(value) }], isError: false };
      } catch (error) {
        result = { content: [{ type: "text", text: error.message }], isError: true };
      }
    } else throw new Error("method not found");
    send({ jsonrpc: "2.0", id, result });
  } catch (error) {
    send({ jsonrpc: "2.0", id, error: { code: -32601, message: error.message } });
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === modulePath) {
  try {
    const options = parseArguments(process.argv.slice(2));
    const context = { ...options, client: localClient(options.stateDir) };
    let pending = Promise.resolve();
    const lines = readline.createInterface({ input: process.stdin });
    lines.on("line", (line) => {
      pending = pending.then(async () => {
        try { await dispatch(JSON.parse(line), context); }
        catch { /* Malformed notification cannot grant a tool. */ }
      });
    });
  } catch (error) {
    process.stderr.write(`openviking-readonly: ${error.message}\n`);
    process.exitCode = 1;
  }
}
