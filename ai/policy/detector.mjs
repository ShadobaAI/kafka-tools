// This detector accepts already-authorized EDT/index/analyzer evidence, never paths.
// Text cues can prove presence, but their absence cannot prove absence.
export const criticalMechanisms = Object.freeze([
  "query_text", "query_in_loop", "exception_handler", "explicit_transaction",
  "export_contract", "module_variable", "privileged_mode", "full_access_module",
  "universal_container", "client_server_boundary", "changed_signature",
  "query_result_processing", "predefined_values",
]);

const cues = {
  query_text: /(?<![\p{L}\p{N}_])(?:Новый\s+Запрос|ВЫБРАТЬ|SELECT)(?![\p{L}\p{N}_])/iu,
  exception_handler: /(?<![\p{L}\p{N}_])Попытка(?![\p{L}\p{N}_])/iu,
  explicit_transaction: /(?<![\p{L}\p{N}_])(?:НачатьТранзакцию|ЗафиксироватьТранзакцию|ОтменитьТранзакцию)(?![\p{L}\p{N}_])/iu,
  export_contract: /(?<![\p{L}\p{N}_])Экспорт(?![\p{L}\p{N}_])/iu,
  module_variable: /(?<![\p{L}\p{N}_])Перем(?![\p{L}\p{N}_])/iu,
  privileged_mode: /(?<![\p{L}\p{N}_])УстановитьПривилегированныйРежим(?![\p{L}\p{N}_])/iu,
  universal_container: /(?<![\p{L}\p{N}_])(?:ПоместитьВоВременноеХранилище|ПолучитьИзВременногоХранилища|ХранилищеЗначения)(?![\p{L}\p{N}_])/iu,
  client_server_boundary: /&(?:НаКлиенте|НаСервере|НаСервереБезКонтекста|НаКлиентеНаСервереБезКонтекста)(?![\p{L}\p{N}_])/iu,
  query_result_processing: /\.(?:Выбрать|Выгрузить|Следующий)\s*\(/iu,
  predefined_values: /(?<![\p{L}\p{N}_])(?:ПредопределенноеЗначение|ПредопределённоеЗначение)\s*\(/iu,
};

export function detectMechanisms(input) {
  if (!input || typeof input !== "object" || Array.isArray(input) ||
      typeof input.sourceRef !== "string" || !input.sourceRef.trim() ||
      (input.sourceText !== undefined && typeof input.sourceText !== "string") ||
      !input.assessments || typeof input.assessments !== "object" || Array.isArray(input.assessments)) {
    throw new Error("detector requires a sourceRef and structured assessments");
  }
  const extra = Object.keys(input.assessments).filter((key) => !criticalMechanisms.includes(key));
  if (extra.length) throw new Error(`unknown assessed mechanism: ${extra.join(", ")}`);
  const detectedMechanisms = [];
  const unknownMechanisms = [];
  const coverage = {};
  for (const mechanism of criticalMechanisms) {
    const assessment = input.assessments[mechanism];
    if (assessment !== undefined && (!assessment || !["present", "absent", "unknown"].includes(assessment.status) ||
        typeof assessment.evidence !== "string" || !assessment.evidence.trim())) {
      throw new Error(`invalid assessment: ${mechanism}`);
    }
    const cuePresent = Boolean(input.sourceText && cues[mechanism]?.test(input.sourceText));
    if (cuePresent && assessment?.status === "absent") throw new Error(`contradictory mechanism evidence: ${mechanism}`);
    const status = cuePresent || assessment?.status === "present" ? "present" : assessment?.status ?? "unknown";
    coverage[mechanism] = { status, evidence: cuePresent ? `text cue in ${input.sourceRef}` : assessment?.evidence ?? "not established" };
    if (status === "present") detectedMechanisms.push(mechanism);
    if (status === "unknown") unknownMechanisms.push(mechanism);
  }
  return { sourceRef: input.sourceRef, coverage, detectedMechanisms, unknownMechanisms };
}
