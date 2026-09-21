import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

// No configuration or credentials are sent to the Windows mutex guardian.
export async function withToolkitOperation(operation) {
  if (process.platform !== "win32") return operation();
  const script = fileURLToPath(new URL("./toolkit-operation-lock.ps1", import.meta.url));
  const shell = path.join(process.env.SystemRoot || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  const child = spawn(shell, ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, "-Hold"],
    { windowsHide: true, stdio: ["pipe", "pipe", "ignore"] });
  const exited = new Promise((resolve) => {
    child.once("error", () => resolve(null));
    child.once("exit", resolve);
  });
  child.stdin.on("error", () => {});
  try {
    await new Promise((resolve, reject) => {
      let text = "";
      const timer = setTimeout(() => reject(new Error("Windows toolkit lock timed out.")), 10000);
      const finish = (error) => {
        clearTimeout(timer);
        if (error) reject(error); else resolve();
      };
      child.once("error", () => finish(new Error("Windows PowerShell is required for the toolkit operation lock.")));
      child.once("exit", (code) => finish(new Error(`Kafka toolkit is busy or its operation lock is unavailable (code ${code}).`)));
      child.stdout.on("data", (chunk) => {
        text += chunk.toString("ascii");
        if (text.trim() === "LOCKED") finish();
        else if (text.length > 4096) finish(new Error("Unexpected toolkit lock response."));
      });
    });
    return await operation();
  } finally {
    child.stdin.end();
    // This can terminate only the guardian, never a service.
    const timer = setTimeout(() => child.kill(), 5000);
    await exited;
    clearTimeout(timer);
  }
}
