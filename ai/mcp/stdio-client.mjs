import { spawn } from "node:child_process";

// One bounded session. Never start services or retry through another transport.
export async function withStdioMcp(command, args, use, {
  env = process.env, cwd = process.cwd(), timeout = 10000, maxBytes = 1024 * 1024,
} = {}) {
  const child = spawn(command, args, { env, cwd, windowsHide: true, stdio: ["pipe", "pipe", "pipe"] });
  const pending = new Map();
  let id = 0, buffer = "", bytes = 0, failure;
  const fail = (error) => {
    failure ??= error;
    for (const entry of pending.values()) entry.reject(failure);
    pending.clear();
  };
  const closed = new Promise((resolve) => child.once("close", resolve));
  child.on("error", () => fail(new Error("MCP process could not start")));
  child.stdin.on("error", () => fail(new Error("MCP input closed")));
  child.on("close", () => fail(new Error("MCP transport closed")));
  // Drain without exposing provider configuration or credentials in diagnostics.
  child.stderr.on("data", (chunk) => {
    bytes += chunk.length;
    if (bytes > maxBytes) fail(new Error("MCP output budget exceeded"));
  });
  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk) => {
    bytes += Buffer.byteLength(chunk);
    if (bytes > maxBytes) { fail(new Error("MCP output budget exceeded")); return; }
    buffer += chunk.toString("utf8");
    let end;
    while ((end = buffer.indexOf("\n")) !== -1) {
      const line = buffer.slice(0, end).trim();
      buffer = buffer.slice(end + 1);
      if (!line) continue;
      let message;
      try { message = JSON.parse(line); }
      catch { fail(new Error("invalid MCP JSON")); return; }
      if (!message || typeof message !== "object" || Array.isArray(message) || message.jsonrpc !== "2.0") {
        fail(new Error("invalid MCP envelope")); return;
      }
      if (!Object.hasOwn(message, "id")) continue;
      const entry = pending.get(message.id);
      if (!entry) { fail(new Error("unexpected MCP response")); return; }
      pending.delete(message.id);
      if (Object.hasOwn(message, "error") || !Object.hasOwn(message, "result")) entry.reject(new Error("MCP request failed"));
      else entry.resolve(message.result);
    }
  });
  const send = (message) => {
    if (failure) throw failure;
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", ...message })}\n`);
  };
  const request = (method, params = {}) => new Promise((resolve, reject) => {
    const next = ++id;
    pending.set(next, { resolve, reject });
    try { send({ id: next, method, params }); }
    catch (error) { pending.delete(next); reject(error); }
  });
  let timer;
  const deadline = new Promise((_, reject) => {
    timer = setTimeout(() => {
      const error = new Error("MCP session timed out");
      fail(error);
      reject(error);
    }, timeout);
  });
  try {
    return await Promise.race([(async () => {
      const initialized = await request("initialize", { protocolVersion: "2024-11-05",
        capabilities: {}, clientInfo: { name: "kafka-doctor", version: "1" } });
      if (initialized?.protocolVersion !== "2024-11-05" ||
          typeof initialized.serverInfo?.name !== "string" || !initialized.serverInfo.name ||
          typeof initialized.serverInfo?.version !== "string" || !initialized.serverInfo.version) {
        throw new Error("incomplete MCP initialize");
      }
      send({ method: "notifications/initialized" });
      const result = await use({ request });
      if (failure) throw failure;
      return result;
    })(), deadline]);
  } finally {
    clearTimeout(timer);
    child.stdin.end();
    // The launcher must get EOF so its own proxy can stop its child cleanly.
    let finish;
    const grace = new Promise((resolve) => { finish = resolve; });
    const force = setTimeout(() => {
      child.kill();
      child.stdout.destroy();
      child.stderr.destroy();
      finish();
    }, 1000);
    await Promise.race([closed, grace]);
    clearTimeout(force);
  }
}

export function jsonToolResult(result) {
  if (result?.isError) throw new Error("MCP tool returned error");
  if (result?.structuredContent) return result.structuredContent;
  const blocks = result?.content?.filter((item) => item.type === "text");
  if (blocks?.length !== 1) throw new Error("MCP tool result is not one JSON object");
  try { return JSON.parse(blocks[0].text); }
  catch { throw new Error("MCP tool result contains invalid JSON"); }
}
