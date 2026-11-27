/**
 * Reply_Processor: turns a Workers AI reply into the final Candidate list
 * (REQ-REPLY-1 to REQ-REPLY-4).
 *
 * Every function here is pure: no I/O, no clock and no logging (REQ-LOG-2,
 * REQ-LOG-3). Letter case is changed with ASCII rules only (E1, E6), using the
 * shared helpers of the TS_Validator.
 */

import {
  asciiLower,
  isAsciiLetter,
  isE2Space,
  isStripChar,
  isValidCandidate,
  splitWords,
  stripWord,
  trimE2,
} from "./validator";

/** Maximum number of Candidates returned by the Reply_Processor (REQ-REPLY-4). */
export const MAX_REPLY_CANDIDATES = 4;

/** True when [value] is a non-null object that is not an array. */
function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The `candidates` array of [value] when it is a non-null, non-array object holding one. */
function candidatesOf(value: unknown): unknown[] | null {
  if (!isPlainObject(value)) return null;
  const candidates = value["candidates"];
  return Array.isArray(candidates) ? candidates : null;
}

/**
 * E8 JSON extraction (REQ-REPLY-1). Takes `reply.response`: a non-null,
 * non-array object is used as it is; a string is parsed from its first `{`
 * to its last `}` inclusive. Returns the `candidates` array of the result, or
 * null when the reply is unparseable or has no `candidates` array.
 */
export function extractCandidatesArray(reply: unknown): unknown[] | null {
  if (!isPlainObject(reply)) return null;
  const response = reply["response"];
  if (isPlainObject(response)) return candidatesOf(response);
  if (typeof response !== "string") return null;
  const first = response.indexOf("{");
  const last = response.lastIndexOf("}");
  if (first < 0 || last < first) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(response.slice(first, last + 1));
  } catch {
    return null;
  }
  return candidatesOf(parsed);
}

/** True when [ch] is an uppercase ASCII letter, `A`-`Z`. */
function isAsciiUpper(ch: string): boolean {
  const u = ch.length === 1 ? ch.charCodeAt(0) : -1;
  return u >= 0x41 && u <= 0x5a;
}

/**
 * The REQ-REPLY-3 condition: [candidate] has 2 or more Words, and every
 * Stripped_Word is non-empty and starts with an uppercase ASCII letter (E6).
 */
export function shouldSentenceCase(candidate: string): boolean {
  const words = splitWords(candidate);
  if (words.length < 2) return false;
  for (const word of words) {
    const core = stripWord(word);
    if (core.length === 0 || !isAsciiUpper(core[0])) return false;
  }
  return true;
}

/**
 * The core of one Word, after Sentence_Case (E6): `I`, or a core starting
 * with `I'` or `I’`, keeps its capital `I` and lowercases the rest; every
 * other core is ASCII-lowercased.
 */
function caseCore(core: string): string {
  if (core === "I") return core;
  if (core.length >= 2 && core[0] === "I" && (core[1] === "'" || core[1] === "\u2019")) {
    return "I" + asciiLower(core.slice(1));
  }
  return asciiLower(core);
}

/**
 * Sentence_Case conversion (REQ-REPLY-3, E6). Changes only ASCII letter
 * case: every whitespace run, strip character, apostrophe, hyphen and other
 * character stays in place, so the length is unchanged. Each Word's core is
 * lowercased except a pronoun `I` (also in `I'…` and `I’…`), then the first
 * ASCII letter of the whole string is uppercased.
 */
export function sentenceCase(candidate: string): string {
  let out = "";
  let i = 0;
  const n = candidate.length;
  while (i < n) {
    if (isE2Space(candidate[i])) {
      out += candidate[i];
      i++;
      continue;
    }
    let end = i;
    while (end < n && !isE2Space(candidate[end])) end++;
    const word = candidate.slice(i, end);
    let coreStart = 0;
    let coreEnd = word.length;
    while (coreStart < coreEnd && isStripChar(word[coreStart])) coreStart++;
    while (coreEnd > coreStart && isStripChar(word[coreEnd - 1])) coreEnd--;
    out +=
      word.slice(0, coreStart) +
      caseCore(word.slice(coreStart, coreEnd)) +
      word.slice(coreEnd);
    i = end;
  }
  for (let j = 0; j < out.length; j++) {
    if (isAsciiLetter(out[j])) {
      const u = out.charCodeAt(j);
      if (u >= 0x61 && u <= 0x7a) {
        out = out.slice(0, j) + String.fromCharCode(u - 0x20) + out.slice(j + 1);
      }
      break;
    }
  }
  return out;
}

/**
 * E7 duplicate key (REQ-REPLY-4): [candidate] ASCII-lowercased, with the
 * trailing run of `.`, `!` and `?` removed.
 */
export function duplicateKey(candidate: string): string {
  const lower = asciiLower(candidate);
  let end = lower.length;
  while (end > 0) {
    const ch = lower[end - 1];
    if (ch !== "." && ch !== "!" && ch !== "?") break;
    end--;
  }
  return lower.slice(0, end);
}

/**
 * The Reply_Processor (REQ-REPLY-1 to REQ-REPLY-4), in this order: extract
 * the `candidates` array (E8); keep string items in model order and trim E2
 * whitespace; apply Sentence_Case when REQ-REPLY-3 holds; drop Candidates the
 * TS_Validator rejects for [tokens]; drop E7 duplicates of earlier kept
 * Candidates; keep the first 4. Returns `[]` for an unparseable reply and,
 * defensively, for any unexpected exception (design error table).
 */
export function processReply(reply: unknown, tokens: string[]): string[] {
  try {
    const items = extractCandidatesArray(reply);
    if (items === null) return [];
    const kept: string[] = [];
    const seen = new Set<string>();
    for (const item of items) {
      if (kept.length >= MAX_REPLY_CANDIDATES) break;
      if (typeof item !== "string") continue;
      const trimmed = trimE2(item);
      const cased = shouldSentenceCase(trimmed) ? sentenceCase(trimmed) : trimmed;
      if (!isValidCandidate(tokens, cased)) continue;
      const key = duplicateKey(cased);
      if (seen.has(key)) continue;
      seen.add(key);
      kept.push(cased);
    }
    return kept;
  } catch {
    return [];
  }
}
