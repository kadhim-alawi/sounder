/**
 * Request parsing for `POST /expand`: the capped body read (REQ-EXPAND-3,
 * D7, E11) and the body shape check (REQ-EXPAND-4).
 *
 * Nothing here logs or keeps what the user typed (REQ-LOG-3). Apart from
 * reading the request body, every function is pure.
 */

/** Longest accepted Token_List (REQ-EXPAND-4). */
const MAX_TOKENS = 12;

/** One Token: 1 to 8 ASCII letters (REQ-EXPAND-4). */
const TOKEN_PATTERN = /^[A-Za-z]{1,8}$/;

/**
 * Reads the body of [request] with a byte cap of [limit] (REQ-EXPAND-3, D7).
 *
 * If a `Content-Length` header is present and its value is above [limit],
 * returns `"too_large"` without reading the body. Otherwise reads
 * `request.body` chunk by chunk, counting bytes; on the first byte past
 * [limit] it cancels the reader and returns `"too_large"`, so the cap applies
 * to the bytes actually sent, not only to the header (E11). A body of exactly
 * [limit] bytes is accepted. A null body returns an empty `Uint8Array`.
 *
 * Errors raised while reading the stream are not caught here; they propagate
 * to the caller, and `handleExpand` maps them to 400 `bad_request`.
 */
export async function readBodyLimited(
  request: Request,
  limit: number,
): Promise<Uint8Array | "too_large"> {
  const header = request.headers.get("Content-Length");
  if (header !== null) {
    const declared = Number(header);
    if (Number.isFinite(declared) && declared > limit) return "too_large";
  }

  const body = request.body;
  if (body === null) return new Uint8Array(0);

  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (; ;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (value === undefined) continue;
    total += value.byteLength;
    if (total > limit) {
      await reader.cancel().catch(() => undefined);
      return "too_large";
    }
    chunks.push(value);
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

/**
 * Parses a request body into a Token_List (REQ-EXPAND-4).
 *
 * Returns the Tokens only when: [bytes] are valid UTF-8; `JSON.parse`
 * succeeds; the value is a non-null, non-array object; its keys are exactly
 * `["tokens"]`; `tokens` is an array of 1 to 12 items; and every item is a
 * string of 1 to 8 ASCII letters. Anything else returns null, which the
 * endpoint answers with 400 `bad_request`.
 */
export function parseTokenRequest(bytes: Uint8Array): string[] | null {
  let text: string;
  try {
    // `ignoreBOM: false` is the standard default; the Workers types require it.
    text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
  } catch {
    return null;
  }

  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }

  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  const keys = Object.keys(value);
  if (keys.length !== 1 || keys[0] !== "tokens") return null;

  const tokens: unknown = (value as Record<string, unknown>)["tokens"];
  if (!Array.isArray(tokens)) return null;
  if (tokens.length < 1 || tokens.length > MAX_TOKENS) return null;

  const out: string[] = [];
  for (const item of tokens) {
    if (typeof item !== "string" || !TOKEN_PATTERN.test(item)) return null;
    out.push(item);
  }
  return out;
}
