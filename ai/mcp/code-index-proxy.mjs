import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";

const DEFAULT_LIMIT = 200;
const MAX_LIMIT = 1000;
const DEFAULT_TREE_NODES = 500;
const MAX_TREE_NODES = 2000;
const DAEMON_HEALTH_TIMEOUT_MS = 2000;

function failStartup(message) {
  process.stderr.write(`code-index-proxy: ${message}\n`);
  process.exit(1);
}

function parseArguments(argv) {
  const result = { "indexer-arg": [] };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith("--") || index === argv.length - 1) {
      failStartup(`invalid argument '${argument}'`);
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      failStartup(`missing value for '${argument}'`);
    }
    const name = argument.slice(2);
    if (name === "indexer-arg") {
      result[name].push(value);
    } else if (Object.hasOwn(result, name)) {
      failStartup(`duplicate argument '${argument}'`);
    } else {
      result[name] = value;
    }
    index += 1;
  }
  return result;
}

function resolveFile(value, description) {
  if (!value) {
    failStartup(`missing required ${description}`);
  }
  const resolved = path.resolve(value);
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    failStartup(`${description} does not exist: '${resolved}'`);
  }
  return resolved;
}

function requestKey(id) {
  return `${typeof id}:${JSON.stringify(id)}`;
}

function writeJson(stream, message) {
  stream.write(`${JSON.stringify(message)}\n`);
}

function writeJsonRpcError(id, message) {
  if (id === undefined) {
    return;
  }
  writeJson(process.stdout, {
    jsonrpc: "2.0",
    id,
    error: { code: -32602, message },
  });
}

function integerArgument(value, fallback, minimum, maximum, name) {
  const resolved = value === undefined ? fallback : value;
  if (!Number.isInteger(resolved) || resolved < minimum || resolved > maximum) {
    throw new Error(`${name} must be an integer from ${minimum} to ${maximum}`);
  }
  return resolved;
}

function sqliteCaseInsensitiveGlob(value) {
  return [...value]
    .map((character) => {
      if (character === "*") return "[*]";
      if (character === "?") return "[?]";
      if (character === "[") return "[[]";
      if (character === "]") return "[]]";
      const lower = character.toLocaleLowerCase("ru-RU");
      const upper = character.toLocaleUpperCase("ru-RU");
      if (lower !== upper && [...lower].length === 1 && [...upper].length === 1) {
        return `[${upper}${lower}]`;
      }
      return character;
    })
    .join("");
}

function commonSchema(limitMaximum) {
  return {
    type: "object",
    properties: {
      repo: {
        type: "string",
        minLength: 1,
        description: "Exact repository alias from the managed code-index federation.",
      },
      procedure: {
        type: "string",
        minLength: 1,
        description:
          "Procedure key '<relative-path>::<name>' for an exact target, or a bare/qualified BSL procedure name for discovery.",
      },
      limit: {
        type: "integer",
        minimum: 1,
        maximum: limitMaximum,
        default: DEFAULT_LIMIT,
        description: `Maximum returned edges; hard cap ${limitMaximum}.`,
      },
    },
    required: ["repo", "procedure"],
    additionalProperties: false,
  };
}

const readOnlyAnnotations = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
};

const customTools = [
  {
    name: "get_callers_bsl",
    title: "Get BSL callers",
    description:
      "Find direct BSL callers through the resolved proc_call_graph. Unlike get_callers, accepts a procedure key and reports unresolved or ambiguous indexed edges. Static index only; dynamic string/reflection calls are outside coverage.",
    inputSchema: commonSchema(MAX_LIMIT),
    annotations: { ...readOnlyAnnotations, title: "Get BSL callers" },
  },
  {
    name: "get_callees_bsl",
    title: "Get BSL callees",
    description:
      "Find direct BSL callees through the resolved proc_call_graph. Unlike get_callees, accepts a procedure key and preserves callee keys and call types. Static index only; dynamic string/reflection calls are outside coverage.",
    inputSchema: commonSchema(MAX_LIMIT),
    annotations: { ...readOnlyAnnotations, title: "Get BSL callees" },
  },
  {
    name: "get_call_tree_bsl",
    title: "Get BSL call tree",
    description:
      "Traverse the resolved BSL proc_call_graph from a procedure key or name in callers or callees direction. Returns flat typed edges with depth and explicit coverage limits; use find_path_bsl for a path between two known procedure keys.",
    inputSchema: {
      type: "object",
      properties: {
        repo: {
          type: "string",
          minLength: 1,
          description: "Exact repository alias from the managed code-index federation.",
        },
        procedure: {
          type: "string",
          minLength: 1,
          description:
            "Procedure key '<relative-path>::<name>' for an exact root, or a bare BSL procedure name for discovery.",
        },
        direction: {
          type: "string",
          enum: ["callees", "callers"],
          default: "callees",
          description: "Traverse downstream callees or upstream callers.",
        },
        max_depth: {
          type: "integer",
          minimum: 1,
          maximum: 10,
          default: 3,
          description: "Maximum number of call edges from the root.",
        },
        max_nodes: {
          type: "integer",
          minimum: 1,
          maximum: MAX_TREE_NODES,
          default: DEFAULT_TREE_NODES,
          description: `Maximum returned edges; hard cap ${MAX_TREE_NODES}.`,
        },
      },
      required: ["repo", "procedure"],
      additionalProperties: false,
    },
    annotations: { ...readOnlyAnnotations, title: "Get BSL call tree" },
  },
];

const callersSql = `
SELECT caller_proc_key, callee_proc_name, callee_proc_key, call_type
FROM proc_call_graph
WHERE (?1 = 1 AND callee_proc_key GLOB ?2)
   OR (?1 = 0 AND (
       callee_proc_name GLOB ?2
       OR callee_proc_name GLOB '*.' || ?2
       OR callee_proc_key GLOB '*::' || ?2))
ORDER BY caller_proc_key, callee_proc_name, call_type`;

const calleesSql = `
SELECT caller_proc_key, callee_proc_name, callee_proc_key, call_type
FROM proc_call_graph
WHERE (?1 = 1 AND caller_proc_key GLOB ?2)
   OR (?1 = 0 AND caller_proc_key GLOB '*::' || ?2)
ORDER BY caller_proc_key, callee_proc_name, call_type`;

const calleesTreeSql = `
WITH RECURSIVE walk(caller_proc_key, callee_proc_name, callee_proc_key, call_type, depth, next_key, visited) AS (
  SELECT caller_proc_key, callee_proc_name, callee_proc_key, call_type, 1,
         COALESCE(callee_proc_key, callee_proc_name),
         char(31) || caller_proc_key || char(31) || COALESCE(callee_proc_key, callee_proc_name) || char(31)
  FROM proc_call_graph
  WHERE (?1 = 1 AND caller_proc_key GLOB ?2)
     OR (?1 = 0 AND caller_proc_key GLOB '*::' || ?2)
  UNION ALL
  SELECT edge.caller_proc_key, edge.callee_proc_name, edge.callee_proc_key, edge.call_type,
         walk.depth + 1, COALESCE(edge.callee_proc_key, edge.callee_proc_name),
         walk.visited || COALESCE(edge.callee_proc_key, edge.callee_proc_name) || char(31)
  FROM walk
  JOIN proc_call_graph edge ON edge.caller_proc_key = walk.next_key
  WHERE walk.depth < ?3
    AND instr(walk.visited, char(31) || COALESCE(edge.callee_proc_key, edge.callee_proc_name) || char(31)) = 0
)
SELECT DISTINCT caller_proc_key, callee_proc_name, callee_proc_key, call_type, depth
FROM walk
ORDER BY depth, caller_proc_key, callee_proc_name`;

const callersTreeSql = `
WITH RECURSIVE walk(caller_proc_key, callee_proc_name, callee_proc_key, call_type, depth, next_key, visited) AS (
  SELECT caller_proc_key, callee_proc_name, callee_proc_key, call_type, 1,
         caller_proc_key,
         char(31) || COALESCE(callee_proc_key, callee_proc_name) || char(31) || caller_proc_key || char(31)
  FROM proc_call_graph
  WHERE (?1 = 1 AND callee_proc_key GLOB ?2)
     OR (?1 = 0 AND (
         callee_proc_name GLOB ?2
         OR callee_proc_name GLOB '*.' || ?2
         OR callee_proc_key GLOB '*::' || ?2))
  UNION ALL
  SELECT edge.caller_proc_key, edge.callee_proc_name, edge.callee_proc_key, edge.call_type,
         walk.depth + 1, edge.caller_proc_key,
         walk.visited || edge.caller_proc_key || char(31)
  FROM walk
  JOIN proc_call_graph edge ON edge.callee_proc_key = walk.next_key
  WHERE walk.depth < ?3
    AND instr(walk.visited, char(31) || edge.caller_proc_key || char(31)) = 0
)
SELECT DISTINCT caller_proc_key, callee_proc_name, callee_proc_key, call_type, depth
FROM walk
ORDER BY depth, caller_proc_key, callee_proc_name`;

function prepareCustomCall(message) {
  const toolName = message?.params?.name;
  if (!customTools.some((tool) => tool.name === toolName)) {
    return undefined;
  }
  if (!Object.hasOwn(message, "id")) {
    return { notification: true };
  }

  const args = message.params?.arguments;
  if (!args || typeof args !== "object" || Array.isArray(args)) {
    throw new Error("tool arguments must be an object");
  }
  const repo = typeof args.repo === "string" ? args.repo.trim() : "";
  const procedure = typeof args.procedure === "string" ? args.procedure.trim() : "";
  if (!repo || !procedure) {
    throw new Error("repo and procedure must be non-empty strings");
  }

  if (toolName === "get_call_tree_bsl") {
    const direction = args.direction ?? "callees";
    if (!['callees', 'callers'].includes(direction)) {
      throw new Error("direction must be 'callees' or 'callers'");
    }
    const maxDepth = integerArgument(args.max_depth, 3, 1, 10, "max_depth");
    const maxNodes = integerArgument(
      args.max_nodes,
      DEFAULT_TREE_NODES,
      1,
      MAX_TREE_NODES,
      "max_nodes",
    );
    return {
      toolName,
      procedure,
      direction,
      maxDepth,
      upstreamArguments: {
        repo,
        sql: direction === "callees" ? calleesTreeSql : callersTreeSql,
        params: [procedure.includes("::") ? 1 : 0, sqliteCaseInsensitiveGlob(procedure), maxDepth],
        limit: maxNodes,
      },
    };
  }

  const limit = integerArgument(args.limit, DEFAULT_LIMIT, 1, MAX_LIMIT, "limit");
  return {
    toolName,
    procedure,
    upstreamArguments: {
      repo,
      sql: toolName === "get_callers_bsl" ? callersSql : calleesSql,
      params: [procedure.includes("::") ? 1 : 0, sqliteCaseInsensitiveGlob(procedure)],
      limit,
    },
  };
}

function parseTextPayload(result) {
  const textBlock = result?.content?.find(
    (item) => item?.type === "text" && typeof item.text === "string",
  );
  if (!textBlock) {
    return undefined;
  }
  try {
    let payload = JSON.parse(textBlock.text);
    if (payload && typeof payload === "object" && Object.hasOwn(payload, "result")) {
      payload = payload.result;
    }
    return payload;
  } catch {
    return undefined;
  }
}

function rowsToRecords(payload) {
  if (!Array.isArray(payload?.columns) || !Array.isArray(payload?.rows)) {
    return undefined;
  }
  return payload.rows.map((row) =>
    Object.fromEntries(payload.columns.map((column, index) => [column, row[index] ?? null])),
  );
}

function updateUpstreamToolDescriptions(tools) {
  const health = tools.find((tool) => tool.name === "health");
  if (health) {
    health.description =
      "Check the MCP server and the actual code-index daemon endpoint. The managed proxy verifies daemon.json against GET /health and reports stale runtime information instead of treating the descriptor file as proof that the daemon is online.";
  }

  const registerWriters = tools.find((tool) => tool.name === "get_register_writers");
  if (registerWriters) {
    registerWriters.description =
      "Return declarative 1C register recorders from metadata RegisterRecords edges. For a register, writers contains documents declared as recorders; for a document, writes_to contains declared registers. This tool does not analyze programmatic RecordSet/RecordManager writes. Therefore writers_count=0 means no declarative recorder edge, not that the register is never written from BSL code. Use find_references and grep_code for programmatic-write investigation.";
  }
}

function invalidRuntimeProbe(state, error) {
  return {
    status: "offline",
    state,
    endpoint_verified: false,
    error,
  };
}

function isProcessAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error?.code === "EPERM";
  }
}

async function probeDaemon() {
  const runtimePath = path.join(path.dirname(config), "daemon.json");
  if (!fs.existsSync(runtimePath)) {
    return invalidRuntimeProbe("runtime_info_missing", "daemon.json is missing");
  }

  let runtime;
  try {
    runtime = JSON.parse(fs.readFileSync(runtimePath, "utf8"));
  } catch (error) {
    return invalidRuntimeProbe("stale_runtime_info", `daemon.json is invalid: ${error.message}`);
  }
  if (
    !Number.isInteger(runtime?.pid) ||
    typeof runtime?.http_host !== "string" ||
    !runtime.http_host ||
    !Number.isInteger(runtime?.http_port)
  ) {
    return invalidRuntimeProbe("stale_runtime_info", "daemon.json has an invalid schema");
  }

  const endpoint = `http://${runtime.http_host}:${runtime.http_port}`;
  const processAlive = isProcessAlive(runtime.pid);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DAEMON_HEALTH_TIMEOUT_MS);
  try {
    const response = await fetch(`${endpoint}/health`, { signal: controller.signal });
    if (!response.ok) {
      throw new Error(`GET /health returned HTTP ${response.status}`);
    }
    const health = await response.json();
    if (health?.status !== "running") {
      throw new Error(`GET /health returned unexpected status '${health?.status}'`);
    }
    if (Number(health?.pid) !== runtime.pid) {
      throw new Error(
        `daemon PID mismatch: daemon.json=${runtime.pid}, /health=${health?.pid}`,
      );
    }
    return {
      status: "online",
      state: "healthy",
      endpoint_verified: true,
      process_alive: true,
      endpoint,
      runtime,
      health,
    };
  } catch (error) {
    const message =
      error?.name === "AbortError"
        ? `GET ${endpoint}/health timed out after ${DAEMON_HEALTH_TIMEOUT_MS} ms`
        : error.message;
    return {
      status: "offline",
      state: processAlive ? "unhealthy" : "stale_runtime_info",
      endpoint_verified: false,
      process_alive: processAlive,
      endpoint,
      runtime,
      error: message,
    };
  } finally {
    clearTimeout(timer);
  }
}

function normalizeWindowsPath(value) {
  let normalized = path.resolve(value);
  if (normalized.startsWith("\\\\?\\")) {
    normalized = normalized.slice(4);
  }
  return normalized.replaceAll("/", "\\").replace(/\\+$/, "").toLowerCase();
}

function readManagedRepositories() {
  const source = fs.readFileSync(config, "utf8");
  const repositories = [];
  for (const block of source.split(/^\s*\[\[paths\]\]\s*$/m).slice(1)) {
    const alias = block.match(/^\s*alias\s*=\s*"([^"]+)"\s*$/m)?.[1];
    const rootPath = block.match(/^\s*path\s*=\s*"([^"]+)"\s*$/m)?.[1];
    if (alias && rootPath) {
      repositories.push({ repo: alias, root_path: rootPath });
    }
  }
  return repositories;
}

async function buildManagedHealthPayload() {
  const daemon = await probeDaemon();
  let repositories;
  try {
    repositories = readManagedRepositories();
  } catch (error) {
    repositories = [];
    daemon.configuration_error = error.message;
  }

  const daemonPaths = Array.isArray(daemon.health?.paths) ? daemon.health.paths : [];
  const statusByPath = new Map(
    daemonPaths.map((item) => [normalizeWindowsPath(item.path), item]),
  );
  const repos = repositories.map((repository) => ({
    ...repository,
    path_status:
      daemon.status === "online"
        ? (statusByPath.get(normalizeWindowsPath(repository.root_path)) ?? {
            status: "unknown",
            error: "path is absent from daemon /health response",
          })
        : { status: "unavailable", error: daemon.error },
  }));

  return {
    mcp: {
      status: "ok",
      version: daemon.runtime?.version ?? daemon.health?.version ?? null,
      repos: repositories.map((repository) => repository.repo),
    },
    daemon,
    repos,
  };
}

async function writeManagedHealthResponse(id) {
  const payload = await buildManagedHealthPayload();
  writeJson(process.stdout, {
    jsonrpc: "2.0",
    id,
    result: {
      content: [{ type: "text", text: JSON.stringify(payload) }],
      isError: false,
    },
  });
}

function targetResolution(context, records) {
  if (context.procedure.includes("::")) {
    return "exact_key";
  }
  const rootRecords =
    context.toolName === "get_call_tree_bsl"
      ? records.filter((record) => Number(record.depth) === 1)
      : records;
  const keys = new Set();
  if (
    context.toolName === "get_callees_bsl" ||
    (context.toolName === "get_call_tree_bsl" && context.direction === "callees")
  ) {
    for (const record of rootRecords) {
      if (record.caller_proc_key) {
        keys.add(record.caller_proc_key);
      }
    }
  } else {
    for (const record of rootRecords) {
      if (record.callee_proc_key) {
        keys.add(record.callee_proc_key);
      }
    }
  }
  if (keys.size > 1) {
    return "ambiguous";
  }
  if (keys.size === 1) {
    return "unique_indexed_target";
  }
  return rootRecords.length === 0 ? "not_found_in_static_graph" : "unresolved_target";
}

function buildCustomResult(context, upstreamResult) {
  const payload = parseTextPayload(upstreamResult);
  const records = rowsToRecords(payload);
  if (!payload || !records) {
    return {
      ...upstreamResult,
      isError: true,
      content: [
        {
          type: "text",
          text: JSON.stringify({
            error: "bsl_sql returned an unexpected response",
            source: "proc_call_graph",
          }),
        },
      ],
    };
  }
  if (payload.error) {
    return {
      ...upstreamResult,
      isError: true,
      content: [{ type: "text", text: JSON.stringify(payload) }],
    };
  }

  const resolvedEdges = records.filter((record) => record.callee_proc_key).length;
  const unresolvedEdges = records.length - resolvedEdges;
  const truncated = payload.truncated === true;
  const resolution = targetResolution(context, records);
  const limitations = [
    "dynamic string and reflection-based calls are not represented",
    "the index is eventually consistent; EDT remains authoritative",
  ];
  if (resolution === "ambiguous") {
    limitations.push("the supplied procedure name resolves to multiple indexed targets");
  }
  if (truncated) {
    limitations.push("the result reached its edge limit and is incomplete");
  }

  const coverage = {
    source: "proc_call_graph",
    static_graph_exhaustive: !truncated,
    requested_bounds_complete: !truncated,
    project_call_coverage: "static_only",
    target_resolution: resolution,
    returned_edges: records.length,
    resolved_edges: resolvedEdges,
    unresolved_edges: unresolvedEdges,
    truncated,
    limitations,
  };
  if (context.toolName === "get_call_tree_bsl") {
    const depthBoundaryReached = records.some(
      (record) => Number(record.depth) === context.maxDepth,
    );
    coverage.max_depth = context.maxDepth;
    coverage.depth_boundary_reached = depthBoundaryReached;
    coverage.static_graph_exhaustive = !truncated && !depthBoundaryReached;
    if (depthBoundaryReached) {
      coverage.limitations.push("the traversal reached max_depth; deeper static edges may exist");
    }
  }

  const resultKey =
    context.toolName === "get_callers_bsl"
      ? "callers"
      : context.toolName === "get_callees_bsl"
        ? "callees"
        : "edges";
  const customPayload = {
    procedure: context.procedure,
    ...(context.direction ? { direction: context.direction } : {}),
    [resultKey]: records,
    coverage,
  };
  return {
    ...upstreamResult,
    isError: false,
    content: [{ type: "text", text: JSON.stringify(customPayload) }],
  };
}

const options = parseArguments(process.argv.slice(2));
const indexer = resolveFile(options.indexer, "--indexer file");
const config = resolveFile(options.config, "--config file");
const pending = new Map();

const child = spawn(
  indexer,
  [...options["indexer-arg"], "serve", "--config", config],
  {
    cwd: path.dirname(config),
    shell: false,
    stdio: ["pipe", "pipe", "pipe"],
    windowsHide: true,
  },
);

child.stderr.pipe(process.stderr);

function handleClientMessage(line) {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    child.stdin.write(`${line}\n`);
    return;
  }

  if (message?.method === "tools/list" && Object.hasOwn(message, "id")) {
    pending.set(requestKey(message.id), { toolName: "tools/list" });
  }

  if (message?.method === "tools/call") {
    if (message.params?.name === "health") {
      if (Object.hasOwn(message, "id")) {
        writeManagedHealthResponse(message.id).catch((error) => {
          writeJsonRpcError(message.id, `managed health failed: ${error.message}`);
        });
      }
      return;
    }
    let customCall;
    try {
      customCall = prepareCustomCall(message);
    } catch (error) {
      writeJsonRpcError(message.id, error.message);
      return;
    }
    if (customCall) {
      if (customCall.notification) {
        return;
      }
      pending.set(requestKey(message.id), customCall);
      message.params = {
        name: "bsl_sql",
        arguments: customCall.upstreamArguments,
      };
    }
  }

  writeJson(child.stdin, message);
}

async function handleServerMessage(line) {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return;
  }

  if (message && Object.hasOwn(message, "id")) {
    const key = requestKey(message.id);
    const context = pending.get(key);
    if (context) {
      if (context.toolName === "tools/list" && Array.isArray(message.result?.tools)) {
        const existingNames = new Set(message.result.tools.map((tool) => tool.name));
        message.result.tools.push(
          ...customTools.filter((tool) => !existingNames.has(tool.name)),
        );
        updateUpstreamToolDescriptions(message.result.tools);
      } else if (context.toolName !== "tools/list" && message.result) {
        message.result = buildCustomResult(context, message.result);
      }
      pending.delete(key);
    }
  }

  writeJson(process.stdout, message);
}

function consumeLines(stream, handler) {
  let buffer = "";
  stream.setEncoding("utf8");
  stream.on("data", (chunk) => {
    buffer += chunk;
    let newlineIndex;
    while ((newlineIndex = buffer.indexOf("\n")) !== -1) {
      let line = buffer.slice(0, newlineIndex);
      buffer = buffer.slice(newlineIndex + 1);
      if (line.endsWith("\r")) {
        line = line.slice(0, -1);
      }
      if (line) {
        handler(line);
      }
    }
  });
  stream.on("end", () => {
    const line = buffer.endsWith("\r") ? buffer.slice(0, -1) : buffer;
    if (line) {
      handler(line);
    }
  });
}

consumeLines(process.stdin, handleClientMessage);
consumeLines(child.stdout, (line) => {
  handleServerMessage(line).catch((error) => {
    process.stderr.write(`code-index-proxy: response handling failed: ${error.message}\n`);
  });
});

let stoppingSignal;
let forceStopTimer;

function stopChild(signal) {
  if (stoppingSignal) {
    return;
  }
  stoppingSignal = signal;
  child.kill(signal);
  forceStopTimer = setTimeout(() => child.kill("SIGKILL"), 5_000);
  forceStopTimer.unref();
}

process.on("SIGINT", () => stopChild("SIGINT"));
process.on("SIGTERM", () => stopChild("SIGTERM"));
process.stdin.on("end", () => {
  if (!child.stdin.destroyed) {
    child.stdin.end();
  }
});
process.stdout.on("error", (error) => {
  if (error.code === "EPIPE") {
    stopChild("SIGTERM");
  }
});

let childStartFailed = false;
child.on("error", (error) => {
  childStartFailed = true;
  process.stderr.write(`code-index-proxy: failed to start bsl-indexer: ${error.message}\n`);
});

child.stdin.on("error", (error) => {
  if (error.code !== "EPIPE" && error.code !== "ERR_STREAM_DESTROYED") {
    process.stderr.write(`code-index-proxy: bsl-indexer input failed: ${error.message}\n`);
  }
});

child.on("close", (code) => {
  if (forceStopTimer) {
    clearTimeout(forceStopTimer);
  }
  process.stdin.pause();
  process.stdin.destroy();
  if (stoppingSignal === "SIGINT") {
    process.exitCode = 130;
  } else if (stoppingSignal === "SIGTERM") {
    process.exitCode = 143;
  } else {
    process.exitCode = childStartFailed ? 1 : (code ?? 1);
  }
  process.stdout.end();
});
