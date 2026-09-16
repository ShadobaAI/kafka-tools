import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const moduleDir = path.dirname(fileURLToPath(import.meta.url));

function option(argv, name) {
  const index = argv.indexOf(name);
  return index < 0 ? undefined : argv[index + 1];
}

export function dispatch({ workspaceRoot, stateDir, node = process.execPath,
                           syncScript = path.join(moduleDir, "git-sync.mjs"), detached = true }) {
  if (!workspaceRoot || !stateDir || !path.isAbsolute(workspaceRoot) || !path.isAbsolute(stateDir)) {
    throw new Error("absolute workspace and state paths are required");
  }
  const relativeState = path.relative(workspaceRoot, stateDir);
  if (!relativeState || (!relativeState.startsWith("..") && !path.isAbsolute(relativeState))) {
    throw new Error("OpenViking state must be outside the Kafka workspace");
  }
  const child = spawn(node, [syncScript, "--workspace-root", workspaceRoot, "--state-dir", stateDir], {
    cwd: workspaceRoot, detached, windowsHide: true, stdio: "ignore",
  });
  if (detached) child.unref();
  return child;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    dispatch({ workspaceRoot: option(process.argv, "--workspace-root"),
      stateDir: option(process.argv, "--state-dir") });
  } catch (error) {
    process.stderr.write(`openviking-hook: ${error.message}\n`);
    process.exitCode = 1;
  }
}
