import path from "node:path";
import { pathToFileURL } from "node:url";
import { withStdioMcp, jsonToolResult } from "./stdio-client.mjs";
import { withHttpMcp } from "./http-client.mjs";

export async function listTools(request, config) {
  const tools = [], cursors = new Set();
  let cursor;
  do {
    const page = await request("tools/list", cursor ? { cursor } : {});
    if (!Array.isArray(page?.tools)) throw new Error("Некорректный список инструментов MCP.");
    for (const tool of page.tools) {
      if (typeof tool.name !== "string" || tools.some((item) => item.name === tool.name)) throw new Error("Некорректные или повторяющиеся имена инструментов MCP.");
      tools.push(tool);
    }
    cursor = page.nextCursor;
    if (cursor !== undefined && (typeof cursor !== "string" || !cursor || cursors.has(cursor) || cursors.size >= 20)) throw new Error("Некорректная пагинация MCP.");
    if (cursor) cursors.add(cursor);
  } while (cursor);
  return tools.filter((tool) => (!config.enabled_tools || config.enabled_tools.includes(tool.name)) && !config.disabled_tools?.includes(tool.name));
}

export async function withConfiguredMcp(config, use, env = process.env, { codeIndex = false } = {}) {
  if (!config || config.error) throw new Error(config?.error ?? "MCP не зарегистрирован.");
  if (config.enabled === false) throw new Error("MCP отключён в конфигурации.");
  if (config.experimental_environment === "remote") throw new Error("Удалённый stdio executor не поддерживается doctor.");
  // Doctor bounds the entire probe, including tool calls, not just startup.
  const timeout = Math.min(120000, Math.max(10000,
    (config.startup_timeout_sec ?? 10) * 1000, (config.tool_timeout_sec ?? 60) * 1000));
  if (!Number.isFinite(timeout)) throw new Error("Некорректные таймауты MCP.");
  if (config.url) return withHttpMcp(config, use, { env, timeout });
  if (typeof config.command !== "string" || !Array.isArray(config.args ?? [])) throw new Error("Некорректная команда stdio MCP.");
  const args = [...(config.args ?? [])];
  if (codeIndex) {
    const fileIndex = args.findIndex((arg) => arg.toLowerCase() === "-file");
    if (fileIndex < 0 || path.basename(args[fileIndex + 1] ?? "").toLowerCase() !== "code-index-mcp.ps1" ||
        !args.some((arg) => arg.toLowerCase() === "-codeindexhome")) {
      throw new Error("Неизвестный launcher code-index: нельзя гарантировать запуск без bootstrap.");
    }
    if (!args.some((arg) => arg.toLowerCase() === "-skipdaemonbootstrap")) args.push("-SkipDaemonBootstrap");
  }
  return withStdioMcp(config.command, args, use, { env: { ...env, ...config.env },
    cwd: config.cwd ?? config.configCwd, timeout });
}

export function requireTools(tools, names) {
  if (names.some((name) => !tools.some((tool) => tool.name === name))) throw new Error("Обязательные инструменты MCP отсутствуют или отключены в конфигурации.");
}

export function explainProbeError(error) {
  const message = error.message;
  if (/timed out/.test(message)) return "Истекло время ожидания MCP. Проверьте запуск сервера и его логи.";
  if (/HTTP status (401|403)/.test(message)) return "MCP отклонил авторизацию. Проверьте настроенные headers и переменные для токенов; сохранённый OAuth Codex doctor не использует.";
  if (/HTTP transport failed/.test(message)) return "Не удалось подключиться к HTTP MCP. Проверьте запуск назначенного сервера, URL в конфигурации и доступность порта.";
  if (/credential environment/.test(message)) return "Некорректная HTTP-конфигурация или отсутствует переменная авторизации из MCP-настроек.";
  if (/process could not start/.test(message)) return "Не удалось запустить stdio MCP. Проверьте command, args, cwd и доступность runtime.";
  if (/transport closed|input closed/.test(message)) return "Процесс MCP завершился до ответа. Проверьте его command, args и логи запуска.";
  if (/output budget/.test(message)) return "Ответ MCP превысил допустимый объём (1 MiB); проверка остановлена.";
  if (/MCP tool returned error|MCP.*request failed/.test(message)) return "MCP вернул ошибку на контрольный запрос. Проверьте состояние компонента и его логи.";
  if (/invalid|incomplete|unexpected|unsupported/.test(message)) return "Ответ или протокол MCP не поддерживается либо неполон. Проверьте совместимость сервера с doctor.";
  return message;
}

export function checkEdtProjects(status, result, expectedRoots, port) {
  if (status?.running !== true || status.success === false || status.port !== port || result?.success === false || !Array.isArray(result?.projects)) {
    return { status: "error", detail: "EDT не подтвердил состояние running, назначенный порт или список проектов." };
  }
  const normalize = (root) => path.resolve(root).replace(/\\/g, "/").toLowerCase();
  for (const root of expectedRoots) {
    const matches = result.projects.filter((item) => typeof item.path === "string" && normalize(item.path) === normalize(root));
    if (matches.length !== 1 || matches[0].state !== "ready" || matches[0].open !== true || matches[0].edtProject !== true) {
      return { status: "error", detail: `EDT отвечает, но проект ${path.basename(root)} отсутствует, закрыт или не готов. Откройте назначенный workspace EDT и дождитесь сборки.` };
    }
  }
  return { status: "ready", detail: `EDT отвечает; обязательные проекты открыты и готовы (${expectedRoots.length}).` };
}

export function checkBslResponse(result) {
  return !result?.error && result?.success !== false && Number.isInteger(result?.count) && result.count > 0 && Array.isArray(result.functions) &&
    result.functions.some((item) => ["Сообщить", "Message"].includes(item.name));
}

export async function probeConfiguredMcp(name, config, env, { checkCodeIndexHealth, aliases = [], inspect, edt, workspaceRoot } = {}) {
  try {
    return await withConfiguredMcp(config, async ({ request }) => {
      const tools = await listTools(request, config);
      if (!tools.length) throw new Error("MCP не предоставляет доступных инструментов.");
      if (inspect) return inspect({ request, tools });
      if (edt) {
        requireTools(tools, ["get_server_status", "list_projects"]);
        const status = jsonToolResult(await request("tools/call", { name: "get_server_status", arguments: {} }));
        if (status.running !== true || status.port !== edt.port) return { status: "error", detail: "EDT не подтвердил running на назначенном порту." };
        const projects = jsonToolResult(await request("tools/call", { name: "list_projects", arguments: { format: "json" } }));
        return checkEdtProjects(status, projects, edt.roots.map((root) => path.join(workspaceRoot, root)), edt.port);
      }
      if (name.startsWith("bsl-ls:")) {
        requireTools(tools, ["global_member_search"]);
        const rootIndex = config.args?.indexOf("--root");
        const root = rootIndex >= 0 ? config.args[rootIndex + 1] : undefined;
        const expected = path.join(workspaceRoot, config.owner);
        if (!root || path.resolve(root).toLowerCase() !== path.resolve(expected).toLowerCase()) throw new Error("BSL LS --root не соответствует назначенному проекту.");
        const result = jsonToolResult(await request("tools/call", { name: "global_member_search", arguments: {
          fileType: "BSL", root: pathToFileURL(expected).href, query: "Сообщить", categories: ["FUNCTION"],
        } }));
        if (!checkBslResponse(result)) throw new Error("BSL LS не подтвердил ответ analyzer для root.");
        return { status: "ready", detail: "MCP и analyzer отвечают на запрос в назначенном root; диагностика исходников не запускалась." };
      }
      if (name === "code-index") {
        requireTools(tools, ["health"]);
        return checkCodeIndexHealth(jsonToolResult(await request("tools/call", { name: "health", arguments: {} })), aliases);
      }
      if (name === "kafka-policy") {
        requireTools(tools, ["detect_1c_mechanisms", "select_1c_requirements", "select_yaxunit_requirements", "validate_compliance"]);
        const result = jsonToolResult(await request("tools/call", { name: "select_yaxunit_requirements",
          arguments: { operation: "run", mechanisms: [] } }));
        if (result.error || !result.digest || !Array.isArray(result.mandatory) || !result.registryVersion) throw new Error("Некорректный ответ selector MCP.");
        return { status: "ready", detail: "MCP и selector отвечают; выбор требований выполнен." };
      }
      if (name === "kafka-openviking") {
        requireTools(tools, ["find", "search", "read", "list", "tree"]);
        return { status: "ready", detail: "MCP доступен; runtime и свежесть данных проверяются отдельно." };
      }
      if (name === "v8std") {
        requireTools(tools, ["v8std_get_summary"]);
        const result = jsonToolResult(await request("tools/call", { name: "v8std_get_summary",
          arguments: { id_or_alias_or_url: "corporate:work:bsl-change-policy:overview", body_limit: 600 } }));
        if (result?.found !== true || result.error || result.page?.id !== "corporate:work:bsl-change-policy:overview" ||
            typeof result.page.body_markdown !== "string" || !result.page.body_markdown.trim()) throw new Error("Корпус v8std не подтвердил доступность контрольного документа.");
        return { status: "ready", detail: "MCP отвечает, контрольный документ корпуса прочитан." };
      }
      return { status: "ready", detail: `MCP отвечает; доступно инструментов: ${tools.length}.`, level: "connection" };
    }, env, { codeIndex: name === "code-index" });
  } catch (error) {
    // Only our own transport/validation errors reach the report, never server content.
    return { status: "error", detail: explainProbeError(error) };
  }
}
