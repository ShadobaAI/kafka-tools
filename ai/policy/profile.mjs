import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";
import { visibleTools } from "./read-only-mcp.mjs";

// Bounded shipped contract, not a persistent cache or personal config inventory.
export const profileFiles = Object.freeze([
  "1c-routing/SKILL.md", "1c-code-change/SKILL.md",
  "1c-code-change/references/requirements.md", "1c-code-index/SKILL.md",
  "1c-standards/SKILL.md", "yaxunit-tests/SKILL.md",
]);
const sourceSkills = fileURLToPath(new URL("../.codex/skills/", import.meta.url));

export function checkPolicySurface(actual) {
  for (const expected of visibleTools()) {
    const matches = actual.filter((item) => item.name === expected.name);
    if (matches.length !== 1 || JSON.stringify(matches[0].inputSchema) !== JSON.stringify(expected.inputSchema) ||
        matches[0].description !== expected.description) {
      throw new Error("Policy protocol/schema mismatch; install matching MCP and skills together.");
    }
  }
}

export function checkPolicyProfile(env = process.env, read = fs.readFileSync) {
  const installed = path.join(env.CODEX_HOME || path.join(os.homedir(), ".codex"), "skills");
  try {
    const different = profileFiles.filter((file) =>
      read(path.join(installed, file), "utf8").replace(/\r\n/g, "\n") !==
      read(path.join(sourceSkills, file), "utf8").replace(/\r\n/g, "\n"));
    if (different.length) return { status: "error", detail: `Несогласованные managed skills: ${different.join(", ")}. Требуется согласованная установка профиля.` };
    return { status: "ready", detail: "Managed skills и requirements соответствуют текущему policy contract." };
  } catch {
    return { status: "error", detail: "Managed skills отсутствуют или недоступны; согласованность policy profile не подтверждена." };
  }
}
