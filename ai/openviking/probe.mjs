import { localClient, loadManifest } from "./git-sync.mjs";
import path from "node:path";

function option(name) {
  const index = process.argv.indexOf(name);
  return index < 0 ? undefined : process.argv[index + 1];
}

try {
  const stateDir = option("--state-dir");
  if (!stateDir) throw new Error("--state-dir is required");
  const { runtime } = loadManifest(undefined, path.join(path.resolve(stateDir), "runtime.json"));
  await localClient(stateDir).ready(runtime.version);
  process.stdout.write(`${JSON.stringify({ status: "ready", version: runtime.version })}\n`);
} catch (error) {
  process.stderr.write(`openviking-probe: ${error.message}\n`);
  process.exitCode = 1;
}
