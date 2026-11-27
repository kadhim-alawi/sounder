// Throwaway spike: compare two Workers AI models for expanding initials into sentences.
// GET /run calls each model on each test, one call at a time, and returns a plain-text report.

const MODELS = [
  "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
  "@cf/meta/llama-4-scout-17b-16e-instruct",
] as const;

type ModelId = (typeof MODELS)[number];

// Per https://developers.cloudflare.com/workers-ai/features/json-mode/ only llama-3.3-70b-instruct-fp8-fast
// of these two is listed as supporting JSON Mode, so only it gets response_format.
const JSON_MODE: Record<ModelId, boolean> = {
  "@cf/meta/llama-3.3-70b-instruct-fp8-fast": true,
  "@cf/meta/llama-4-scout-17b-16e-instruct": false,
};

const TESTS: { initials: string[]; hoped: string }[] = [
  { initials: ["I", "W", "S", "W", "P"], hoped: "I want some water please" },
  { initials: ["C", "Y", "H", "M"], hoped: "Can you help me" },
  { initials: ["I", "A", "T"], hoped: "I am tired" },
  { initials: ["P", "C", "M", "D"], hoped: "Please call my daughter" },
  { initials: ["I", "N", "T", "G", "T", "T", "B"], hoped: "I need to go to the bathroom" },
  { initials: ["W", "T", "I", "I"], hoped: "What time is it" },
];

const SYSTEM_PROMPT =
  'You expand initials into short spoken sentences for a person who cannot speak. Each input letter is the first letter of one word, in order. Return exactly 4 different candidate sentences as JSON, and nothing else: {"candidates":["...","...","...","..."]} Every candidate must have exactly one word per letter, and each word must start with that letter. Use everyday, first-person language a person would say to a carer or friend.';

const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    candidates: { type: "array", items: { type: "string" }, minItems: 4, maxItems: 4 },
  },
  required: ["candidates"],
};

interface CallResult {
  model: ModelId;
  initials: string[];
  hoped: string;
  latencyMs: number;
  parsed: boolean;
  candidates: string[];
  validFlags: boolean[];
  hit: boolean;
  raw: string;
  error?: string;
}

function isValid(candidate: string, initials: string[]): boolean {
  const words = candidate.trim().split(/\s+/).filter((w) => w.length > 0);
  if (words.length !== initials.length) return false;
  return words.every((w, i) => w[0].toLowerCase() === initials[i].toLowerCase());
}

function normalise(s: string): string {
  return s
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, "")
    .replace(/\s+/g, " ")
    .trim();
}

// Extracts candidates from a parsed reply. Returns null when the shape is wrong.
function extractCandidates(value: unknown): string[] | null {
  if (typeof value !== "object" || value === null) return null;
  const c = (value as { candidates?: unknown }).candidates;
  if (!Array.isArray(c) || !c.every((x) => typeof x === "string")) return null;
  return c as string[];
}

async function callOnce(env: Env, model: ModelId, initials: string[], hoped: string): Promise<CallResult> {
  const inputs: Record<string, unknown> = {
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: initials.join(" ") },
    ],
    temperature: 0.2,
    max_tokens: 200,
  };
  if (JSON_MODE[model]) {
    inputs.response_format = { type: "json_schema", json_schema: RESPONSE_SCHEMA };
  }

  const result: CallResult = {
    model,
    initials,
    hoped,
    latencyMs: 0,
    parsed: false,
    candidates: [],
    validFlags: [],
    hit: false,
    raw: "",
  };

  const start = Date.now();
  let reply: unknown;
  try {
    // The model union and loose inputs object do not match one overload, so cast at this boundary.
    reply = await (env.AI.run as (m: string, i: unknown) => Promise<unknown>)(model, inputs);
  } catch (e) {
    result.latencyMs = Date.now() - start;
    result.error = e instanceof Error ? e.message : String(e);
    return result;
  }
  result.latencyMs = Date.now() - start;

  // Per the output schema, `response` is the generated text. In JSON Mode it may already be an object.
  const response = (reply as { response?: unknown } | null)?.response;
  let candidates: string[] | null = null;
  if (typeof response === "string") {
    result.raw = response;
    try {
      candidates = extractCandidates(JSON.parse(response));
    } catch {
      candidates = null;
    }
  } else {
    result.raw = JSON.stringify(response ?? reply);
    candidates = extractCandidates(response);
  }

  if (candidates) {
    result.parsed = true;
    result.candidates = candidates;
    result.validFlags = candidates.map((c) => isValid(c, initials));
    const target = normalise(hoped);
    result.hit = candidates.some((c) => normalise(c) === target);
  }
  return result;
}

function median(xs: number[]): number {
  if (xs.length === 0) return 0;
  const s = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : Math.round((s[mid - 1] + s[mid]) / 2);
}

function pad(s: string, n: number): string {
  return s.length >= n ? s : s + " ".repeat(n - s.length);
}

function report(results: CallResult[]): string {
  const lines: string[] = [];
  const nTests = TESTS.length;
  const maxCandidates = nTests * 4;

  lines.push("SUMMARY");
  lines.push(
    pad("model", 44) + pad("hits", 8) + pad("valid", 10) + pad("median ms", 12) + pad("parse fail", 12) + "errors",
  );
  for (const model of MODELS) {
    const rs = results.filter((r) => r.model === model);
    const hits = rs.filter((r) => r.hit).length;
    const valid = rs.reduce((n, r) => n + r.validFlags.filter(Boolean).length, 0);
    const parseFail = rs.filter((r) => !r.parsed).length;
    const errors = rs.filter((r) => r.error).length;
    const med = median(rs.map((r) => r.latencyMs));
    lines.push(
      pad(model, 44) +
        pad(`${hits}/${nTests}`, 8) +
        pad(`${valid}/${maxCandidates}`, 10) +
        pad(String(med), 12) +
        pad(String(parseFail), 12) +
        String(errors),
    );
  }
  lines.push("");
  lines.push("Parse fail counts calls with an error too. JSON Mode: " +
    MODELS.map((m) => `${m}=${JSON_MODE[m] ? "on" : "off"}`).join(", "));
  lines.push("");
  lines.push("DETAILS");

  for (const r of results) {
    lines.push("");
    lines.push(`${r.model} | ${r.initials.join(" ")} | hoped: "${r.hoped}"`);
    lines.push(
      `  latency ${r.latencyMs} ms | parsed ${r.parsed ? "yes" : "no"} | valid ${r.validFlags.filter(Boolean).length}/${r.candidates.length} | hit ${r.hit ? "yes" : "no"}`,
    );
    if (r.error) lines.push(`  error: ${r.error}`);
    r.candidates.forEach((c, i) => lines.push(`  ${r.validFlags[i] ? "[ok] " : "[bad]"} ${c}`));
    if (!r.parsed && r.raw) lines.push(`  raw: ${r.raw}`);
  }
  return lines.join("\n") + "\n";
}

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method !== "GET" || url.pathname !== "/run") {
      return new Response("GET /run to start the comparison.\n", { status: 404 });
    }
    const results: CallResult[] = [];
    for (const model of MODELS) {
      for (const t of TESTS) {
        results.push(await callOnce(env, model, t.initials, t.hoped));
      }
    }
    return new Response(report(results), { headers: { "content-type": "text/plain; charset=utf-8" } });
  },
} satisfies ExportedHandler<Env>;
