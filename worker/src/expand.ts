/**
 * The Expand_Endpoint: the handler for `/expand` (REQ-EXPAND-1 to
 * REQ-EXPAND-11, REQ-LOG-1, REQ-LOG-2, design D2, D4 to D7).
 *
 * Checks run in the E9 order: method (405), rate limit (429), Content-Type
 * (415), body size (413), body shape (400), then the model (503 or 200). Each
 * response is logged once through the injected `log` with four numbers only.
 * Nothing here stores request data or logs what the user typed (REQ-LOG-1,
 * REQ-LOG-3); every caught error is discarded and mapped to a status code.
 */

import type { ExpandLogEntry } from "./log";
import { callModelWithTimeout, type ModelCaller } from "./model";
import { processReply } from "./reply";
import { parseTokenRequest, readBodyLimited } from "./request";

/** Largest accepted request body in bytes (REQ-EXPAND-3, E11). */
export const MAX_BODY_BYTES = 1024;

/** Time limit for one Model call in milliseconds (REQ-EXPAND-9, D6). */
export const MODEL_TIMEOUT_MS = 5000;

/** Rate-limit key used when `CF-Connecting-IP` is missing (REQ-EXPAND-6, E13). */
export const UNKNOWN_CLIENT_KEY = "unknown";

/**
 * The slice of the Cloudflare rate-limiting binding the endpoint uses
 * (REQ-EXPAND-6, REQ-EXPAND-7, C3). `success: false` means over the limit.
 */
export interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

/**
 * Dependencies injected into `handleExpand` (D2, REQ-WORKERTEST-2), so tests
 * pass mocks and never reach the real bindings.
 */
export interface ExpandDeps {
  /** Rate_Limiter, called once per POST before the body is read (REQ-EXPAND-6). */
  rateLimiter: RateLimiter;
  /** Model_Caller for the one Model call (REQ-EXPAND-8). */
  modelCaller: ModelCaller;
  /** Current time in milliseconds; used for the logged latency only (REQ-LOG-2). */
  now: () => number;
  /** Receives one Worker_Log entry per request (REQ-LOG-2). */
  log: (entry: ExpandLogEntry) => void;
}

/** Fixed error codes of the non-200 responses (REQ-EXPAND-11, E12). */
export type ExpandErrorCode =
  | "method_not_allowed"
  | "unsupported_media_type"
  | "payload_too_large"
  | "bad_request"
  | "rate_limited"
  | "model_unavailable";

/**
 * Builds an `/expand` response (REQ-EXPAND-11): [body] as JSON, with
 * `Content-Type: application/json` and `Cache-Control: no-store` always set
 * and no `Access-Control-Allow-Origin`, even if [extraHeaders] holds one.
 */
export function jsonResponse(
  status: number,
  body: unknown,
  extraHeaders?: Record<string, string>,
): Response {
  const headers = new Headers(extraHeaders);
  headers.set("Content-Type", "application/json");
  headers.set("Cache-Control", "no-store");
  headers.delete("Access-Control-Allow-Origin");
  return new Response(JSON.stringify(body), { status, headers });
}

/** True when the media type of [header] is `application/json` (REQ-EXPAND-2, E10). */
function isJsonMediaType(header: string | null): boolean {
  return (header ?? "").split(";")[0].trim().toLowerCase() === "application/json";
}

/**
 * Handles one request to `/expand` (REQ-EXPAND-1 to REQ-EXPAND-11), running
 * the checks in the E9 order and returning the status of the first that
 * fails (REQ-EXPAND-5).
 *
 * - Not POST: 405 with `Allow: POST`; the Rate_Limiter is not called.
 * - One `limit({ key })` call with `CF-Connecting-IP`, or `unknown`, before
 *   the body is read; over the limit is 429; a throw counts as allowed (D5).
 * - Media type not `application/json`: 415. Body over 1,024 bytes: 413.
 *   Body stream error or not a Token_List: 400.
 * - Model error or no result within 5 s: 503. Otherwise 200 with the
 *   Reply_Processor output.
 *
 * Logs one entry per request: Token count is set once the body parsed, and
 * Candidate count only for 200 (REQ-LOG-2, design error table).
 */
export async function handleExpand(request: Request, deps: ExpandDeps): Promise<Response> {
  const start = deps.now();

  const finish = (
    status: number,
    body: unknown,
    tokenCount: number,
    candidateCount: number,
    extraHeaders?: Record<string, string>,
  ): Response => {
    deps.log({ status, latencyMs: deps.now() - start, tokenCount, candidateCount });
    return jsonResponse(status, body, extraHeaders);
  };
  const fail = (
    status: number,
    error: ExpandErrorCode,
    tokenCount = 0,
    extraHeaders?: Record<string, string>,
  ): Response => finish(status, { error }, tokenCount, 0, extraHeaders);

  // 1. Method (REQ-EXPAND-1). No Rate_Limiter call (E9).
  if (request.method !== "POST") {
    return fail(405, "method_not_allowed", 0, { Allow: "POST" });
  }

  // 2. Rate limit, exactly once, before the body is read (REQ-EXPAND-6, REQ-EXPAND-7).
  const key = request.headers.get("CF-Connecting-IP") ?? UNKNOWN_CLIENT_KEY;
  let allowed = true;
  try {
    allowed = (await deps.rateLimiter.limit({ key })).success;
  } catch {
    allowed = true; // D5: a limiter fault fails open.
  }
  if (!allowed) return fail(429, "rate_limited");

  // 3. Content-Type (REQ-EXPAND-2, E10).
  if (!isJsonMediaType(request.headers.get("Content-Type"))) {
    return fail(415, "unsupported_media_type");
  }

  // 4. Body size (REQ-EXPAND-3, D7, E11). A stream error is a 400.
  let bytes: Uint8Array | "too_large";
  try {
    bytes = await readBodyLimited(request, MAX_BODY_BYTES);
  } catch {
    return fail(400, "bad_request");
  }
  if (bytes === "too_large") return fail(413, "payload_too_large");

  // 5. Body shape (REQ-EXPAND-4).
  const tokens = parseTokenRequest(bytes);
  if (tokens === null) return fail(400, "bad_request");

  // 6. Model (REQ-EXPAND-8 to REQ-EXPAND-10).
  const outcome = await callModelWithTimeout(deps.modelCaller, tokens, MODEL_TIMEOUT_MS);
  if (outcome.kind !== "ok") return fail(503, "model_unavailable", tokens.length);

  const candidates = processReply(outcome.reply, tokens);
  return finish(200, { candidates }, tokens.length, candidates.length);
}
