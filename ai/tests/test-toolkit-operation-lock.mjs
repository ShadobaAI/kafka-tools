// No installation, readiness probes or index operations are executed here.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { withToolkitOperation } from "../mcp/toolkit-operation-lock.mjs";

if (process.platform === "win32") {
  const helper = fileURLToPath(new URL("../mcp/toolkit-operation-lock.ps1", import.meta.url));
  const shell = path.join(process.env.SystemRoot, "System32/WindowsPowerShell/v1.0/powershell.exe");
  await withToolkitOperation(async () => {
    await assert.rejects(withToolkitOperation(() => assert.fail("Concurrent Node operation entered")), /busy|lock/);
    const competitor = spawnSync(shell, ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", helper, "-Hold"],
      { input: "\n", windowsHide: true, timeout: 15000 });
    assert.equal(competitor.status, 73, "PowerShell must share the same operation lock");
  });
  assert.equal(await withToolkitOperation(async () => "released"), "released");
  await assert.rejects(withToolkitOperation(async () => { throw new Error("fixture failure"); }), /fixture failure/);
  assert.equal(await withToolkitOperation(async () => "recovered"), "recovered");
  const standalone = spawnSync(shell, ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", helper, "-Hold"],
    { input: "\n", windowsHide: true, timeout: 15000 });
  assert.equal(standalone.status, 0);
  assert.equal(standalone.stdout.toString().trim(), "LOCKED");
  const abandoned = spawn(shell, ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", helper, "-Hold"],
    { windowsHide: true, stdio: ["pipe", "pipe", "ignore"] });
  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("Fixture guardian timeout")), 10000);
      abandoned.once("error", (error) => { clearTimeout(timer); reject(error); });
      abandoned.stdout.once("data", (chunk) => {
        clearTimeout(timer);
        if (chunk.toString().trim() === "LOCKED") resolve(); else reject(new Error("Unexpected fixture response"));
      });
    });
    const ended = new Promise((resolve) => abandoned.once("exit", resolve));
    abandoned.kill();
    await ended;
  } finally {
    abandoned.stdin.destroy();
    if (abandoned.exitCode === null) abandoned.kill();
  }
  assert.equal(await withToolkitOperation(async () => "after crash"), "after crash");
}
console.log("Toolkit operation lock: OK");
