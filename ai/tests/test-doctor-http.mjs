import assert from "node:assert/strict";
import { createServer } from "node:http";
import { withHttpMcp } from "../mcp/http-client.mjs";

export async function runHttpTests() {
  let mode = "json", deleted = 0, calls = [], captured = [];
  const secret = "fixture-private-value";
  const server = createServer(async (req, res) => {
    captured.push(req.headers);
    if (req.method === "DELETE") { deleted++; res.writeHead(204).end(); return; }
    let body = "";
    for await (const chunk of req) body += chunk;
    const message = JSON.parse(body);
    calls.push(message.method);
    if (mode === "timeout") return;
    if (mode === "redirect") { res.writeHead(302, { Location: `/private-${secret}` }).end(); return; }
    if (mode === "status") { res.writeHead(401).end(secret); return; }
    if (message.method === "notifications/initialized") { res.writeHead(202).end(); return; }
    const result = message.method === "initialize"
      ? { protocolVersion: mode === "older-version" ? "2024-11-05" : mode === "unknown-version" ? "2099-01-01" : "2025-03-26", capabilities: {}, serverInfo: { name: "fixture", version: "1" } }
      : { tools: [{ name: "health" }] };
    const response = { jsonrpc: "2.0", id: message.id, result };
    if (mode === "wrong-id") response.id++;
    if (mode === "rpc-error") { delete response.result; response.error = { code: -1, message: secret }; }
    const text = mode === "invalid" ? secret : JSON.stringify(response);
    const headers = { "Content-Type": mode === "sse" ? "text/event-stream" : "application/json" };
    if (message.method === "initialize") headers["Mcp-Session-Id"] = "fixture-session";
    res.writeHead(200, headers);
    if (mode === "sse") {
      res.write(': keepalive\r\ndata: {"jsonrpc":"2.0","method":"notifications/progress","params":{}}\r\n\r\n');
      res.write(`event: message\r\ndata: ${text}\r`);
      setImmediate(() => res.write("\n\r\n")); // A response may leave the SSE stream open.
    } else res.end(text);
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const config = { url: `http://127.0.0.1:${server.address().port}/mcp`,
    http_headers: { "X-Static": "fixture" }, env_http_headers: { "X-Secret": "FIXTURE" }, bearer_token_env_var: "FIXTURE" };
  const options = { env: { FIXTURE: secret }, timeout: 1000 };
  const probe = (extra = {}) => withHttpMcp(config, ({ request }) => request("tools/list"), { ...options, ...extra });
  try {
    for (mode of ["json", "sse"]) {
      calls = []; captured = [];
      assert.deepEqual(await probe(), { tools: [{ name: "health" }] });
      assert.deepEqual(calls, ["initialize", "notifications/initialized", "tools/list"]);
      assert.equal(captured[0].authorization, `Bearer ${secret}`);
      assert.equal(captured[0]["x-secret"], secret);
      assert.equal(captured[0]["x-static"], "fixture");
      assert.equal(captured[0]["mcp-session-id"], undefined);
      assert.equal(captured[1]["mcp-session-id"], "fixture-session");
      assert.equal(captured[2]["mcp-protocol-version"], "2025-03-26");
      assert.equal(captured[3]["mcp-session-id"], "fixture-session");
    }
    assert.equal(deleted, 2);
    mode = "older-version";
    captured = [];
    assert.deepEqual(await probe(), { tools: [{ name: "health" }] });
    assert.equal(captured[2]["mcp-protocol-version"], "2024-11-05");
    mode = "json";
    captured = [];
    assert.deepEqual(await withHttpMcp({ url: config.url, http_headers: null, env_http_headers: null,
      bearer_token_env_var: null }, ({ request }) => request("tools/list"), { timeout: 1000 }), { tools: [{ name: "health" }] });
    assert.equal(captured[0].authorization, undefined);
    for (const [nextMode, expected] of [["wrong-id", /response id/], ["rpc-error", /request failed/],
      ["unknown-version", /incomplete MCP HTTP initialize/],
      ["invalid", /invalid MCP HTTP JSON/], ["status", /status 401/], ["redirect", /transport failed/],
      ["timeout", /timed out/]]) {
      mode = nextMode;
      await assert.rejects(probe({ timeout: mode === "timeout" ? 100 : 1000 }), (error) => {
        assert.match(error.message, expected);
        assert.equal(error.message.includes(secret), false);
        assert.equal(error.message.includes(config.url), false);
        return true;
      });
    }
    mode = "json";
    await assert.rejects(probe({ maxBytes: 10 }), /budget exceeded/);
    // Each response fits on its own; the budget covers their aggregate.
    await assert.rejects(probe({ maxBytes: 180 }), /budget exceeded/);
    await assert.rejects(probe({ env: {} }), /missing credential environment variable/);
    await assert.rejects(withHttpMcp({ url: "not-a-url" }, () => {}), /invalid MCP HTTP configuration/);
    await assert.rejects(withHttpMcp(config, () => new Promise(() => {}), { ...options, timeout: 100 }), /timed out/);
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
}
