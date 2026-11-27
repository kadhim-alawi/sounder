/**
 * TS_Validator: the Initials_Validator of REQ-VALIDATOR-1, written in
 * TypeScript for the Worker. The Dart_Validator in `app/lib/compose/` runs the
 * same algorithm, and both read `fixtures/expansion_validator.json`
 * (REQ-VALIDATOR-2).
 *
 * Every function here works on UTF-16 code units (`charCodeAt`), uses no
 * regex with Unicode classes and no `toLowerCase`, so the two runtimes cannot
 * differ (E1, E5). Every function is pure: no I/O, no clock, no logging
 * (REQ-VALIDATOR-4).
 */

/** Maximum Candidate length in UTF-16 code units after E2 trimming (REQ-VALIDATOR-1 (a), E5). */
export const MAX_CANDIDATE_LENGTH = 200;

/** Maximum number of Tokens in a Token_List (REQ-VALIDATOR-1, REQ-EXPAND-4). */
const MAX_TOKENS = 12;

/** Maximum number of letters in one Token (REQ-VALIDATOR-1, REQ-EXPAND-4). */
const MAX_TOKEN_LENGTH = 8;

/** Code unit of the first character of [ch], or -1 when [ch] is not exactly one code unit. */
function unitOf(ch: string): number {
  return ch.length === 1 ? ch.charCodeAt(0) : -1;
}

function isE2SpaceUnit(u: number): boolean {
  return (u >= 0x09 && u <= 0x0d) || u === 0x20;
}

function isStripUnit(u: number): boolean {
  switch (u) {
    case 0x2e: // .
    case 0x2c: // ,
    case 0x21: // !
    case 0x3f: // ?
    case 0x3b: // ;
    case 0x3a: // :
    case 0x22: // "
    case 0x28: // (
    case 0x29: // )
      return true;
    default:
      return false;
  }
}

function isAsciiLetterUnit(u: number): boolean {
  return (u >= 0x41 && u <= 0x5a) || (u >= 0x61 && u <= 0x7a);
}

function isJoinerUnit(u: number): boolean {
  return u === 0x27 /* ' */ || u === 0x2019 /* ’ */ || u === 0x2d /* - */;
}

/**
 * True when [ch] is one E2 whitespace character: U+0009 to U+000D or U+0020.
 * Other Unicode spaces are not separators (REQ-VALIDATOR-1 (b), E2).
 */
export function isE2Space(ch: string): boolean {
  return isE2SpaceUnit(unitOf(ch));
}

/**
 * True when [ch] is one of the strip characters `. , ! ? ; : " ( )`
 * (REQ-VALIDATOR-1 (c), E4). Curly quotes are not strip characters.
 */
export function isStripChar(ch: string): boolean {
  return isStripUnit(unitOf(ch));
}

/** True when [ch] is one ASCII letter, `A`-`Z` or `a`-`z` (REQ-VALIDATOR-1, E1). */
export function isAsciiLetter(ch: string): boolean {
  return isAsciiLetterUnit(unitOf(ch));
}

/**
 * ASCII lowercasing: maps only U+0041..U+005A to U+0061..U+007A and keeps
 * every other code unit (REQ-VALIDATOR-1 (d), E1).
 */
export function asciiLower(s: string): string {
  let out = "";
  for (let i = 0; i < s.length; i++) {
    const u = s.charCodeAt(i);
    out += u >= 0x41 && u <= 0x5a ? String.fromCharCode(u + 0x20) : s[i];
  }
  return out;
}

/**
 * [s] with E2 whitespace removed from both ends (REQ-VALIDATOR-1 (a),
 * REQ-REPLY-2, E2, E5).
 */
export function trimE2(s: string): string {
  let start = 0;
  let end = s.length;
  while (start < end && isE2SpaceUnit(s.charCodeAt(start))) start++;
  while (end > start && isE2SpaceUnit(s.charCodeAt(end - 1))) end--;
  return s.slice(start, end);
}

/**
 * Splits [s] on runs of E2 whitespace. Leading, trailing and repeated
 * whitespace create no empty Words (REQ-VALIDATOR-1 (b), E2).
 */
export function splitWords(s: string): string[] {
  const words: string[] = [];
  let start = -1;
  for (let i = 0; i < s.length; i++) {
    if (isE2SpaceUnit(s.charCodeAt(i))) {
      if (start >= 0) {
        words.push(s.slice(start, i));
        start = -1;
      }
    } else if (start < 0) {
      start = i;
    }
  }
  if (start >= 0) words.push(s.slice(start));
  return words;
}

/**
 * The Stripped_Word: [w] with strip characters removed repeatedly from both
 * ends until neither end is a strip character (REQ-VALIDATOR-1 (c), E4).
 */
export function stripWord(w: string): string {
  let start = 0;
  let end = w.length;
  while (start < end && isStripUnit(w.charCodeAt(start))) start++;
  while (end > start && isStripUnit(w.charCodeAt(end - 1))) end--;
  return w.slice(start, end);
}

/**
 * True when [core] is non-empty, made only of ASCII letters, apostrophes
 * (U+0027, U+2019) and hyphens (U+002D), and every apostrophe and hyphen has
 * an ASCII letter directly before and after it (REQ-VALIDATOR-1 (c), E3).
 */
export function isWellFormedWord(core: string): boolean {
  const n = core.length;
  if (n === 0) return false;
  for (let j = 0; j < n; j++) {
    const u = core.charCodeAt(j);
    if (isAsciiLetterUnit(u)) continue;
    if (!isJoinerUnit(u)) return false;
    if (j === 0 || j === n - 1) return false;
    if (!isAsciiLetterUnit(core.charCodeAt(j - 1))) return false;
    if (!isAsciiLetterUnit(core.charCodeAt(j + 1))) return false;
  }
  return true;
}

/** True when [tokens] is a Token_List: 1 to 12 strings of 1 to 8 ASCII letters (REQ-VALIDATOR-1). */
function isTokenList(tokens: readonly unknown[]): tokens is readonly string[] {
  if (!Array.isArray(tokens)) return false;
  if (tokens.length < 1 || tokens.length > MAX_TOKENS) return false;
  for (const t of tokens) {
    if (typeof t !== "string") return false;
    if (t.length < 1 || t.length > MAX_TOKEN_LENGTH) return false;
    for (let i = 0; i < t.length; i++) {
      if (!isAsciiLetterUnit(t.charCodeAt(i))) return false;
    }
  }
  return true;
}

/**
 * The Initials_Validator rule (REQ-VALIDATOR-1). Accepts [candidate] for
 * [tokens] only when (a) the E2-trimmed Candidate is at most 200 UTF-16 code
 * units, (b) it has exactly one Word per Token, (c) every Stripped_Word is
 * non-empty and well formed (E3), and (d) every Stripped_Word, ASCII-lowercased,
 * starts with its Token, ASCII-lowercased. Returns false when [tokens] is not
 * a Token_List. Pure, with no I/O, clock or logging (REQ-VALIDATOR-4).
 */
export function isValidCandidate(tokens: readonly string[], candidate: string): boolean {
  if (!isTokenList(tokens)) return false;
  if (typeof candidate !== "string") return false;
  const t = trimE2(candidate);
  if (t.length > MAX_CANDIDATE_LENGTH) return false;
  const words = splitWords(t);
  if (words.length !== tokens.length) return false;
  for (let i = 0; i < words.length; i++) {
    const core = stripWord(words[i]);
    if (!isWellFormedWord(core)) return false;
    if (!asciiLower(core).startsWith(asciiLower(tokens[i]))) return false;
  }
  return true;
}
