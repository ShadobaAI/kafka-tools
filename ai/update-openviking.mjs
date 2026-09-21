import path from "node:path";
import { withToolkitOperation } from "./mcp/toolkit-operation-lock.mjs";
import os from "node:os";
import { fileURLToPath } from "node:url";
import { codexMcp } from "./mcp/installed-config.mjs";
import { reconcile, localClient } from "./openviking/git-sync.mjs";

const workspaceRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

export function updateMode(args) {
  if (args.length === 0) return { forceRebuild: false, allowRebuild: false };
  if (args.length === 1 && args[0] === "--rebuild") return { forceRebuild: true, allowRebuild: true };
  throw new Error("Использование: update-openviking.cmd [--rebuild]. Без параметров обновляются только изменения.");
}

export function resolveUpdateOptions(env = process.env, read = codexMcp) {
  let stateDir = env.KAFKA_OPENVIKING_STATE_DIR;
  const source = stateDir ? "KAFKA_OPENVIKING_STATE_DIR" : "MCP kafka-openviking";
  if (!stateDir) {
    const config = read(["get", "kafka-openviking", "--json"], os.tmpdir(), env);
    if (!config || config.name !== "kafka-openviking" || config.enabled === false || config.transport?.type !== "stdio") {
      throw new Error("Не найдена активная stdio-конфигурация MCP kafka-openviking. Проверьте установку toolkit или задайте KAFKA_OPENVIKING_STATE_DIR явно.");
    }
    const args = config.transport.args;
    if (!Array.isArray(args) || args.some((arg) => typeof arg !== "string")) throw new Error("Некорректные args MCP kafka-openviking.");
    const option = (name) => {
      const matches = args.flatMap((arg, index) => arg === name ? [index] : []);
      if (matches.length !== 1 || !args[matches[0] + 1] || args[matches[0] + 1].startsWith("--")) {
        throw new Error(`В MCP kafka-openviking требуется единственный аргумент ${name}.`);
      }
      return args[matches[0] + 1];
    };
    const configuredRoot = option("--workspace-root");
    const canonical = (root) => process.platform === "win32" ? path.resolve(root).toLowerCase() : path.resolve(root);
    if (!path.isAbsolute(configuredRoot) || canonical(configuredRoot) !== canonical(workspaceRoot)) {
      throw new Error("MCP kafka-openviking настроен на другой workspace. Перестройка отменена; проверьте --workspace-root в его args.");
    }
    stateDir = option("--state-dir");
  }
  if (!path.isAbsolute(stateDir)) throw new Error("Каталог OpenViking state-dir должен быть абсолютным путём.");
  return { workspaceRoot, stateDir: path.resolve(stateDir), source };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  withToolkitOperation(async () => {
    let options, mode;
    try {
      mode = updateMode(process.argv.slice(2));
      options = resolveUpdateOptions();
    } catch (error) {
      process.stderr.write(`openviking-update: ${error.message}\n`);
      process.exitCode = 2;
    }
    if (options) {
      process.stderr.write(`Каталог данных определён через ${options.source}. ${mode.forceRebuild ? "Полная перестройка" : "Инкрементальное обновление"} Git-контекста...\n`);
      await reconcile({ workspaceRoot: options.workspaceRoot, stateDir: options.stateDir,
        client: localClient(options.stateDir), ...mode,
        progress: (message) => process.stderr.write(`openviking-sync: ${message}\n`),
      }).then((result) => process.stdout.write(`${JSON.stringify(result)}\n`))
        .catch((error) => { process.stderr.write(`openviking-sync: ${error.message}\n`); process.exitCode = 1; });
    }
  }).catch((error) => { process.stderr.write(`openviking-update: ${error.message}\n`); process.exitCode = 1; });
}
