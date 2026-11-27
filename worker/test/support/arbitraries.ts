/**
 * fast-check generators for the Worker property tests (REQ-WORKERTEST-3).
 *
 * Every generator meets its preconditions by construction: no `fc.pre` and
 * no `.filter`. Generated strings are synthetic test data, not user text.
 */
import fc from "fast-check";

/** The 52 ASCII letters `A`-`Z` and `a`-`z` (REQ-VALIDATOR-1, E1). */
export const ASCII_LETTERS: readonly string[] = Array.from({ length: 26 }, (_, i) =>
  String.fromCharCode(0x41 + i),
).concat(Array.from({ length: 26 }, (_, i) => String.fromCharCode(0x61 + i)));

/** The strip characters `. , ! ? ; : " ( )` (REQ-VALIDATOR-1 (c), E4). */
export const STRIP_CHARS: readonly string[] = [".", ",", "!", "?", ";", ":", '"', "(", ")"];

/** The E2 whitespace characters U+0009..U+000D and U+0020 (REQ-VALIDATOR-1 (b), E2). */
export const E2_SPACES: readonly string[] = ["\t", "\n", "\u000b", "\f", "\r", " "];

/** Most Tokens in a Token_List (REQ-VALIDATOR-1, REQ-EXPAND-4). */
const MAX_TOKENS = 12;

/** Most letters in a Token (REQ-VALIDATOR-1, REQ-EXPAND-4). */
const MAX_TOKEN_LETTERS = 8;

/**
 * Fixed caps for generated-valid candidates (design, Property test
 * configuration). With at most 12 Words of 8 token letters + 2 extra letters
 * + 2 leading and 2 trailing strip characters, and 11 separators of at most 2
 * characters, the E2-trimmed Candidate is at most 12 × 14 + 11 × 2 = 190
 * characters, within the 200 of REQ-VALIDATOR-1 (a) and REQ-VALIDATOR-5.
 */
const MAX_EXTRA_LETTERS = 2;
const MAX_STRIP_PER_END = 2;
const MAX_SEPARATOR_LENGTH = 2;
const MAX_OUTER_SPACE_LENGTH = 2;

const asciiLetterArb: fc.Arbitrary<string> = fc.constantFrom(...ASCII_LETTERS);
const stripCharArb: fc.Arbitrary<string> = fc.constantFrom(...STRIP_CHARS);
const e2SpaceArb: fc.Arbitrary<string> = fc.constantFrom(...E2_SPACES);

/** A Token: 1 to 8 ASCII letters in any case (REQ-VALIDATOR-1, REQ-VALIDATOR-5). */
export const tokenArb: fc.Arbitrary<string> = fc.string({
  unit: asciiLetterArb,
  minLength: 1,
  maxLength: MAX_TOKEN_LETTERS,
});

/** A Token_List: 1 to 12 Tokens (REQ-VALIDATOR-1, REQ-VALIDATOR-5). */
export const tokenListArb: fc.Arbitrary<string[]> = fc.array(tokenArb, {
  minLength: 1,
  maxLength: MAX_TOKENS,
});

/** ASCII case flip of one letter; the generators only pass ASCII letters here (E1). */
function withCase(letter: string, upper: boolean): string {
  const u = letter.charCodeAt(0);
  const lower = u >= 0x41 && u <= 0x5a ? u + 0x20 : u;
  return String.fromCharCode(upper ? lower - 0x20 : lower);
}

/**
 * One Word for [token]: the Token in any mix of letter case, then 0 to 2
 * extra ASCII letters, with 0 to 2 strip characters at each end
 * (REQ-VALIDATOR-5).
 */
function validWordArb(token: string): fc.Arbitrary<string> {
  return fc
    .tuple(
      fc.array(fc.boolean(), { minLength: token.length, maxLength: token.length }),
      fc.string({ unit: asciiLetterArb, maxLength: MAX_EXTRA_LETTERS }),
      fc.string({ unit: stripCharArb, maxLength: MAX_STRIP_PER_END }),
      fc.string({ unit: stripCharArb, maxLength: MAX_STRIP_PER_END }),
    )
    .map(([upper, extra, lead, trail]) => {
      let core = "";
      for (let i = 0; i < token.length; i++) core += withCase(token[i], upper[i]);
      return lead + core + extra + trail;
    });
}

/**
 * A Candidate that the Initials_Validator must accept for [tokens]: Word i
 * is Token i in any letter case plus 0 to 2 extra letters, with 0 to 2 strip
 * characters at each end; Words are joined by 1 to 2 E2 whitespace
 * characters, with 0 to 2 E2 whitespace characters before and after. The
 * fixed caps keep the trimmed Candidate at or under 190 characters
 * (REQ-VALIDATOR-5, REQ-VALIDATOR-1, REQ-WORKERTEST-3).
 */
export function validCandidateArb(tokens: readonly string[]): fc.Arbitrary<string> {
  const separatorArb = fc.string({ unit: e2SpaceArb, minLength: 1, maxLength: MAX_SEPARATOR_LENGTH });
  const outerArb = fc.string({ unit: e2SpaceArb, maxLength: MAX_OUTER_SPACE_LENGTH });
  const count = tokens.length;
  return fc
    .tuple(
      fc.tuple(...tokens.map((t) => validWordArb(t))),
      fc.array(separatorArb, { minLength: count - 1, maxLength: count - 1 }),
      outerArb,
      outerArb,
    )
    .map(([words, separators, leading, trailing]) => {
      let body = words[0];
      for (let i = 1; i < count; i++) body += separators[i - 1] + words[i];
      return leading + body + trailing;
    });
}

/** A Token_List with a Candidate for it (REQ-VALIDATOR-5, REQ-VALIDATOR-6, REQ-WORKERTEST-3). */
export interface TokensAndCandidate {
  tokens: string[];
  candidate: string;
}

/** True for one E2 whitespace code unit, U+0009..U+000D or U+0020 (E2). */
function isE2Unit(u: number): boolean {
  return (u >= 0x09 && u <= 0x0d) || u === 0x20;
}

/** True for one strip character code unit `. , ! ? ; : " ( )` (E4). */
function isStripCharUnit(u: number): boolean {
  return STRIP_CHARS.includes(String.fromCharCode(u));
}

/**
 * Index in [candidate] of the first character of Stripped_Word [wordIndex]:
 * skips E2 whitespace to the start of that Word, then its leading strip
 * characters. Only called on candidates from `validCandidateArb`, where that
 * character is an ASCII letter (REQ-VALIDATOR-6, E2, E4).
 */
function strippedWordStart(candidate: string, wordIndex: number): number {
  let i = 0;
  let word = -1;
  while (i < candidate.length) {
    while (i < candidate.length && isE2Unit(candidate.charCodeAt(i))) i++;
    word++;
    if (word === wordIndex) break;
    while (i < candidate.length && !isE2Unit(candidate.charCodeAt(i))) i++;
  }
  while (isStripCharUnit(candidate.charCodeAt(i))) i++;
  return i;
}

/**
 * A Property 1 pair whose Candidate has the first letter of Stripped_Word i
 * replaced by a different ASCII letter. Position i is a natural number modulo
 * the Word count; the new letter is `(first + 1 + k) mod 26` with k in 0..24,
 * so it differs from the old one ignoring case by construction, and it keeps
 * the old letter's case. Token i starts with the old letter ignoring case, so
 * the new Stripped_Word i no longer starts with Token i
 * (REQ-VALIDATOR-6, REQ-VALIDATOR-1, REQ-WORKERTEST-3).
 */
export const firstLetterMutationArb: fc.Arbitrary<TokensAndCandidate> = tokenListArb.chain((tokens) =>
  fc
    .tuple(validCandidateArb(tokens), fc.nat(), fc.integer({ min: 0, max: 24 }))
    .map(([valid, n, k]) => {
      const at = strippedWordStart(valid, n % tokens.length);
      const u = valid.charCodeAt(at);
      const upper = u >= 0x41 && u <= 0x5a;
      const first = upper ? u - 0x41 : u - 0x61;
      const replaced = (first + 1 + k) % 26;
      const letter = String.fromCharCode((upper ? 0x41 : 0x61) + replaced);
      return { tokens, candidate: valid.slice(0, at) + letter + valid.slice(at + 1) };
    }),
);

/** Most Words that `addWordsMutationArb` inserts (REQ-VALIDATOR-7). */
const MAX_ADDED_WORDS = 3;

/**
 * The Words of [candidate]: its maximal runs of non-E2 characters, in order
 * (REQ-VALIDATOR-1 (b), E2).
 */
function splitE2Words(candidate: string): string[] {
  const words: string[] = [];
  let i = 0;
  while (i < candidate.length) {
    while (i < candidate.length && isE2Unit(candidate.charCodeAt(i))) i++;
    const start = i;
    while (i < candidate.length && !isE2Unit(candidate.charCodeAt(i))) i++;
    if (i > start) words.push(candidate.slice(start, i));
  }
  return words;
}

/**
 * [words] joined by the given E2 separators, with [leading] and [trailing]
 * E2 whitespace. `separators` has at least `words.length - 1` entries
 * (REQ-VALIDATOR-1 (b), E2).
 */
function joinE2Words(words: readonly string[], separators: readonly string[], leading: string, trailing: string): string {
  let body = "";
  for (let i = 0; i < words.length; i++) body += (i > 0 ? separators[i - 1] : "") + words[i];
  return leading + body + trailing;
}

const separatorArb: fc.Arbitrary<string> = fc.string({
  unit: e2SpaceArb,
  minLength: 1,
  maxLength: MAX_SEPARATOR_LENGTH,
});
const outerSpaceArb: fc.Arbitrary<string> = fc.string({ unit: e2SpaceArb, maxLength: MAX_OUTER_SPACE_LENGTH });

/**
 * A Property 1 pair with at least 1 and at most all of its Words removed.
 * A removal mask is drawn for every Word and one Word, chosen by a natural
 * number modulo the Word count, is always removed, so the Word count is
 * below the Token count by construction. Removing every Word leaves an
 * E2-only Candidate, which must also be rejected
 * (REQ-VALIDATOR-7, REQ-VALIDATOR-1, REQ-WORKERTEST-3).
 */
export const removeWordsMutationArb: fc.Arbitrary<TokensAndCandidate> = tokenListArb.chain((tokens) =>
  fc
    .tuple(
      validCandidateArb(tokens),
      fc.array(fc.boolean(), { minLength: tokens.length, maxLength: tokens.length }),
      fc.nat(),
      fc.array(separatorArb, { minLength: tokens.length, maxLength: tokens.length }),
      outerSpaceArb,
      outerSpaceArb,
    )
    .map(([valid, remove, n, separators, leading, trailing]) => {
      const words = splitE2Words(valid);
      const forced = n % words.length;
      const kept: string[] = [];
      for (let i = 0; i < words.length; i++) if (i !== forced && !remove[i]) kept.push(words[i]);
      return { tokens, candidate: joinE2Words(kept, separators, leading, trailing) };
    }),
);

/**
 * A Property 1 pair with 1 to 3 Words inserted at any positions. Each added
 * Word is 1 to 8 ASCII letters, so it is a non-empty Word and the Word count
 * is above the Token count by construction. Each position is a natural number
 * modulo the current Word count + 1. The result may exceed 200 characters,
 * which is also invalid (REQ-VALIDATOR-7, REQ-VALIDATOR-1, REQ-WORKERTEST-3).
 */
export const addWordsMutationArb: fc.Arbitrary<TokensAndCandidate> = tokenListArb.chain((tokens) =>
  fc
    .tuple(
      validCandidateArb(tokens),
      fc.array(fc.tuple(tokenArb, fc.nat()), { minLength: 1, maxLength: MAX_ADDED_WORDS }),
      fc.array(separatorArb, {
        minLength: tokens.length + MAX_ADDED_WORDS,
        maxLength: tokens.length + MAX_ADDED_WORDS,
      }),
      outerSpaceArb,
      outerSpaceArb,
    )
    .map(([valid, added, separators, leading, trailing]) => {
      const words = splitE2Words(valid);
      for (const [word, n] of added) words.splice(n % (words.length + 1), 0, word);
      return { tokens, candidate: joinE2Words(words, separators, leading, trailing) };
    }),
);

/**
 * A Property 1 pair whose Word count differs from its Token count, by
 * removing or adding Words (REQ-VALIDATOR-7, REQ-VALIDATOR-1, REQ-WORKERTEST-3).
 */
export const wordCountMutationArb: fc.Arbitrary<TokensAndCandidate> = fc.oneof(
  removeWordsMutationArb,
  addWordsMutationArb,
);

/**
 * [candidate] with the first character of every Stripped_Word uppercased when
 * it is a lowercase ASCII letter. Whitespace, strip characters and every
 * other character stay in place (REQ-REPLY-3, REQ-REPLY-5, E2, E4).
 */
function capitaliseEveryWord(candidate: string): string {
  let out = "";
  let i = 0;
  while (i < candidate.length) {
    while (i < candidate.length && isE2Unit(candidate.charCodeAt(i))) out += candidate[i++];
    while (i < candidate.length && isStripCharUnit(candidate.charCodeAt(i))) out += candidate[i++];
    if (i < candidate.length && !isE2Unit(candidate.charCodeAt(i))) {
      const u = candidate.charCodeAt(i);
      out += u >= 0x61 && u <= 0x7a ? String.fromCharCode(u - 0x20) : candidate[i];
      i++;
    }
    while (i < candidate.length && !isE2Unit(candidate.charCodeAt(i))) out += candidate[i++];
  }
  return out;
}

/**
 * Characters for the arbitrary strings of Property 4: ASCII letters, strip
 * characters, apostrophes (U+0027, U+2019), a hyphen, digits, E2 spaces,
 * non-E2 spaces (U+00A0, U+2003) and non-ASCII letters (é, ß)
 * (REQ-REPLY-5, E1 to E4).
 */
const MIXED_UNITS: readonly string[] = [
  ...ASCII_LETTERS,
  ...STRIP_CHARS,
  "'",
  "\u2019",
  "-",
  ..."0123456789",
  ...E2_SPACES,
  "\u00a0",
  "\u2003",
  "\u00e9",
  "\u00df",
];

/** Longest arbitrary string in Property 4; long enough to cross the 200 limit sometimes (E5). */
const MAX_MIXED_LENGTH = 220;

/**
 * An arbitrary string of 0 to 220 characters from `MIXED_UNITS`, used by
 * Property 4 and Property 5 (REQ-REPLY-5, REQ-REPLY-6, E1 to E5).
 */
export const mixedStringArb: fc.Arbitrary<string> = fc.string({
  unit: fc.constantFrom(...MIXED_UNITS),
  maxLength: MAX_MIXED_LENGTH,
});

/**
 * A Token_List with a string for Property 4: a Property 1 Candidate for the
 * Tokens, the same Candidate with every Word capitalised (so REQ-REPLY-3
 * applies), or an arbitrary string of the characters in `MIXED_UNITS`
 * (REQ-REPLY-5, REQ-REPLY-3, REQ-WORKERTEST-3).
 */
export const sentenceCaseInputArb: fc.Arbitrary<TokensAndCandidate> = tokenListArb.chain((tokens) =>
  fc
    .oneof(
      validCandidateArb(tokens),
      validCandidateArb(tokens).map(capitaliseEveryWord),
      mixedStringArb,
    )
    .map((candidate) => ({ tokens, candidate })),
);

/** Most items in a generated `candidates` array (Property 5). */
const MAX_REPLY_ITEMS = 12;

/** Most base Candidates that near-duplicates are made from (Property 5). */
const MAX_BASE_CANDIDATES = 6;

/** Most `.`, `!` and `?` characters appended to a near-duplicate (E7). */
const MAX_DUPLICATE_PUNCTUATION = 3;

/**
 * [candidate] with the ASCII letter case flipped where [flip] is true and
 * [punctuation] inserted before its trailing E2 whitespace, so it is
 * appended to the last Word. Its E7 duplicate key, after E2 trimming and
 * Sentence_Case, equals that of [candidate] (REQ-REPLY-4, E7).
 */
function nearDuplicate(candidate: string, flip: readonly boolean[], punctuation: string): string {
  let cased = "";
  for (let i = 0; i < candidate.length; i++) {
    const ch = candidate[i];
    const u = candidate.charCodeAt(i);
    const letter = (u >= 0x41 && u <= 0x5a) || (u >= 0x61 && u <= 0x7a);
    cased += letter && flip[i] ? withCase(ch, !(u >= 0x41 && u <= 0x5a)) : ch;
  }
  let end = cased.length;
  while (end > 0 && isE2Unit(cased.charCodeAt(end - 1))) end--;
  return cased.slice(0, end) + punctuation + cased.slice(end);
}

/**
 * A near-duplicate of one of [bases], chosen by a natural number modulo
 * their count: letters flipped in case at random and 0 to 3 of `.`, `!`, `?`
 * appended to the last Word (REQ-REPLY-4, E7).
 */
function nearDuplicateArb(bases: readonly string[]): fc.Arbitrary<string> {
  return fc
    .tuple(
      fc.nat(),
      fc.array(fc.boolean(), { maxLength: 200 }),
      fc.string({ unit: fc.constantFrom(".", "!", "?"), maxLength: MAX_DUPLICATE_PUNCTUATION }),
    )
    .map(([n, flip, punctuation]) => nearDuplicate(bases[n % bases.length], flip, punctuation));
}

/**
 * Object keys that can never be `candidates`: every key starts with `x`
 * (REQ-REPLY-1).
 */
const nonCandidatesKeyArb: fc.Arbitrary<string> = fc.string({ maxLength: 8 }).map((k) => "x" + k);

/** An object with no `candidates` key, by construction (REQ-REPLY-1). */
const noCandidatesObjectArb: fc.Arbitrary<Record<string, unknown>> = fc.dictionary(
  nonCandidatesKeyArb,
  fc.jsonValue({ maxDepth: 2 }),
  { maxKeys: 4 },
);

/**
 * A `candidates` array for [tokens]: 0 to 12 items mixing base Candidates
 * that the TS_Validator accepts, other valid Candidates, near-duplicates of
 * the bases by letter case and trailing `.!?`, the Property 4 mixed strings,
 * numbers, nulls, booleans, objects and arrays (REQ-REPLY-2, REQ-REPLY-4).
 */
function candidatesItemsArb(tokens: readonly string[]): fc.Arbitrary<unknown[]> {
  return fc
    .array(validCandidateArb(tokens), { minLength: 1, maxLength: MAX_BASE_CANDIDATES })
    .chain((bases) =>
      fc.array(
        fc.oneof(
          { arbitrary: fc.constantFrom(...bases), weight: 4 },
          { arbitrary: validCandidateArb(tokens), weight: 2 },
          { arbitrary: nearDuplicateArb(bases), weight: 4 },
          { arbitrary: mixedStringArb, weight: 2 },
          { arbitrary: fc.integer(), weight: 1 },
          { arbitrary: fc.double({ noNaN: true, noDefaultInfinity: true }), weight: 1 },
          { arbitrary: fc.constant(null), weight: 1 },
          { arbitrary: fc.boolean(), weight: 1 },
          { arbitrary: noCandidatesObjectArb, weight: 1 },
          { arbitrary: fc.array(mixedStringArb, { maxLength: 2 }), weight: 1 },
        ),
        { maxLength: MAX_REPLY_ITEMS },
      ),
    );
}

/**
 * Noise around the JSON object in a string `response`: letters, digits,
 * spaces, newlines and punctuation, but never `{` or `}`, so the E8 slice is
 * exactly the JSON object (REQ-REPLY-1, E8).
 */
const NOISE_UNITS: readonly string[] = [...ASCII_LETTERS, ..."0123456789", " ", "\n", ".", ",", ":", "!", '"', "[", "]"];
const noiseArb: fc.Arbitrary<string> = fc.string({ unit: fc.constantFrom(...NOISE_UNITS), maxLength: 40 });

/**
 * A Property 5 case: a Token_List, a Workers AI reply, and the `candidates`
 * array the reply carries, or null when, by construction, it carries none
 * (REQ-REPLY-1, REQ-REPLY-2, REQ-REPLY-4, REQ-REPLY-6).
 */
export interface ReplyCase {
  tokens: string[];
  reply: unknown;
  items: unknown[] | null;
}

/**
 * A Property 5 case. The reply is one of: a non-object; `{response: s}` for
 * arbitrary text with every `{` removed, so it is unparseable; noise, then
 * the JSON text of `{candidates}`, then noise; the same JSON text cut before
 * its closing `}`, so it is unparseable; `{response: {candidates}}`; or
 * `{response: o}` for an object with no `candidates` key. The `candidates`
 * arrays are built for the same Token_List, so outputs are often non-empty,
 * near-duplicates are dropped and the 4-item cap is reached
 * (REQ-REPLY-6, REQ-REPLY-4, REQ-REPLY-1, REQ-REPLY-2, REQ-WORKERTEST-3).
 */
export const modelReplyArb: fc.Arbitrary<ReplyCase> = tokenListArb.chain((tokens) => {
  const none = (reply: unknown): ReplyCase => ({ tokens, reply, items: null });
  const items = candidatesItemsArb(tokens);
  return fc.oneof(
    fc
      .oneof(
        fc.constant(null),
        fc.constant(undefined),
        fc.integer(),
        fc.string(),
        fc.boolean(),
        fc.array(fc.jsonValue({ maxDepth: 1 }), { maxLength: 3 }),
      )
      .map(none),
    fc
      .oneof(fc.string({ maxLength: 60 }), mixedStringArb)
      .map((s) => none({ response: s.split("{").join("") })),
    {
      weight: 3,
      arbitrary: fc
        .tuple(noiseArb, items, noiseArb)
        .map(([before, list, after]): ReplyCase => ({
          tokens,
          reply: { response: before + JSON.stringify({ candidates: list }) + after },
          items: list,
        })),
    },
    fc
      .tuple(noiseArb, items, fc.nat(), noiseArb)
      .map(([before, list, n, after]) => {
        const json = JSON.stringify({ candidates: list });
        return none({ response: before + json.slice(0, 1 + (n % (json.length - 1))) + after });
      }),
    {
      weight: 3,
      arbitrary: items.map((list): ReplyCase => ({ tokens, reply: { response: { candidates: list } }, items: list })),
    },
    noCandidatesObjectArb.map((o) => none({ response: o })),
  );
});

const utf8Encoder = new TextEncoder();

/** A valid request body with the Token_List it carries (REQ-EXPAND-4). */
export interface TokenBodyCase {
  tokens: string[];
  bytes: Uint8Array;
}

/**
 * A valid `POST /expand` body: the UTF-8 bytes of
 * `JSON.stringify({tokens: T})` for a Token_List T of 1 to 12 Tokens of 1 to
 * 8 ASCII letters (REQ-EXPAND-4, REQ-WORKERTEST-3).
 */
export const validTokenBodyArb: fc.Arbitrary<TokenBodyCase> = tokenListArb.map((tokens) => ({
  tokens,
  bytes: utf8Encoder.encode(JSON.stringify({ tokens })),
}));

/** A body built by one mutation of a valid body, labelled for counterexamples (REQ-EXPAND-4). */
export interface MutatedBodyCase {
  mutation: string;
  bytes: Uint8Array;
}

/** Fewest and most items in a too-long `tokens` list (REQ-EXPAND-4). */
const MIN_TOO_MANY_TOKENS = MAX_TOKENS + 1;
const MAX_TOO_MANY_TOKENS = 20;
/** Fewest and most letters in a too-long item (REQ-EXPAND-4). */
const MIN_TOO_LONG_LETTERS = MAX_TOKEN_LETTERS + 1;
const MAX_TOO_LONG_LETTERS = 12;

/**
 * Characters that are never ASCII letters: digits, ASCII punctuation and
 * spaces, and non-ASCII letters, including the Kelvin sign and dotted
 * capital I that case-insensitive matching can confuse with `K` and `i`
 * (REQ-EXPAND-4, E1).
 */
const NON_LETTER_UNITS: readonly string[] = [
  ..."0123456789",
  " ",
  "\t",
  "\n",
  "-",
  "_",
  "'",
  ".",
  "@",
  "[",
  "`",
  "{",
  "\u00e9",
  "\u00df",
  "\u00a0",
  "\u0130",
  "\u212a",
  "\u2019",
  "\u0430",
];

/** Keys that are never exactly `tokens` (REQ-EXPAND-4). */
const nonTokensKeyArb: fc.Arbitrary<string> = fc.oneof(
  fc.constantFrom("Tokens", "TOKENS", "token", "tokens ", " tokens", ""),
  fc.string({ maxLength: 8 }).map((k) => "x" + k),
);

/** JSON values that are not arrays: strings, numbers, booleans, null and objects (REQ-EXPAND-4). */
const nonArrayJsonArb: fc.Arbitrary<unknown> = fc.oneof(
  fc.string({ maxLength: 8 }),
  fc.integer(),
  fc.double({ noNaN: true, noDefaultInfinity: true }),
  fc.boolean(),
  fc.constant(null),
  fc.dictionary(fc.string({ maxLength: 4 }), fc.jsonValue({ maxDepth: 1 }), { maxKeys: 3 }),
);

/** JSON values that are not strings, for a non-string item (REQ-EXPAND-4). */
const nonStringJsonArb: fc.Arbitrary<unknown> = fc.oneof(
  fc.integer(),
  fc.double({ noNaN: true, noDefaultInfinity: true }),
  fc.boolean(),
  fc.constant(null),
  fc.array(tokenArb, { maxLength: 2 }),
  fc.dictionary(fc.string({ maxLength: 4 }), tokenArb, { maxKeys: 2 }),
);

/** Byte sequences that are never valid UTF-8 wherever they are inserted in ASCII text (E11, REQ-EXPAND-4). */
const INVALID_UTF8_SEQUENCES: readonly (readonly number[])[] = [
  [0xff],
  [0xfe],
  [0x80],
  [0xc0, 0x80],
  [0xc3],
  [0xe2, 0x82],
  [0xed, 0xa0, 0x80],
  [0xf8, 0x88, 0x80, 0x80, 0x80],
];

/** `{tokens: list}` as UTF-8 JSON bytes (REQ-EXPAND-4). */
function tokensBody(list: unknown): Uint8Array {
  return utf8Encoder.encode(JSON.stringify({ tokens: list }));
}

/** [tokens] with item [n] mod length replaced by [item] (REQ-EXPAND-4). */
function replaceItem(tokens: readonly string[], n: number, item: unknown): unknown[] {
  const out: unknown[] = [...tokens];
  out[n % tokens.length] = item;
  return out;
}

/**
 * A body built by exactly one mutation of a valid body, which
 * `parseTokenRequest` must reject: an extra key; no `tokens` key; `tokens`
 * not an array; 0 or 13 to 20 items; an item of 0 or 9 to 12 letters; an
 * item with one letter replaced by a non-letter or non-ASCII character; a
 * non-string item; a top-level array, `null`, number, string or boolean;
 * the JSON text cut short; or an invalid UTF-8 sequence inserted. Every
 * count and length is generated inside its bad range directly
 * (REQ-EXPAND-4, REQ-WORKERTEST-3).
 */
export const mutatedTokenBodyArb: fc.Arbitrary<MutatedBodyCase> = tokenListArb.chain((tokens) => {
  const valid = JSON.stringify({ tokens });
  const tooLongItemArb = fc.string({
    unit: asciiLetterArb,
    minLength: MIN_TOO_LONG_LETTERS,
    maxLength: MAX_TOO_LONG_LETTERS,
  });
  return fc.oneof(
    fc
      .tuple(fc.string({ maxLength: 8 }), fc.jsonValue({ maxDepth: 1 }), fc.boolean())
      .map(([k, v, before]) => {
        const key = "x" + k;
        const body = before ? { [key]: v, tokens } : { tokens, [key]: v };
        return { mutation: "extra key", bytes: utf8Encoder.encode(JSON.stringify(body)) };
      }),
    fc.oneof(
      fc.constant({ mutation: "no tokens key", bytes: utf8Encoder.encode("{}") }),
      nonTokensKeyArb.map((key) => ({
        mutation: "no tokens key",
        bytes: utf8Encoder.encode(JSON.stringify({ [key]: tokens })),
      })),
    ),
    nonArrayJsonArb.map((v) => ({ mutation: "tokens not an array", bytes: tokensBody(v) })),
    fc.constant({ mutation: "empty list", bytes: tokensBody([]) }),
    fc
      .array(tokenArb, { minLength: MIN_TOO_MANY_TOKENS, maxLength: MAX_TOO_MANY_TOKENS })
      .map((list) => ({ mutation: "13 to 20 items", bytes: tokensBody(list) })),
    fc
      .tuple(fc.nat(), fc.oneof(fc.constant(""), tooLongItemArb))
      .map(([n, item]) => ({ mutation: "item of 0 or 9 to 12 letters", bytes: tokensBody(replaceItem(tokens, n, item)) })),
    fc
      .tuple(fc.nat(), fc.nat(), fc.constantFrom(...NON_LETTER_UNITS))
      .map(([n, at, bad]) => {
        const token = tokens[n % tokens.length];
        const i = at % token.length;
        const item = token.slice(0, i) + bad + token.slice(i + 1);
        return { mutation: "non-letter character in an item", bytes: tokensBody(replaceItem(tokens, n, item)) };
      }),
    fc
      .tuple(fc.nat(), nonStringJsonArb)
      .map(([n, item]) => ({ mutation: "non-string item", bytes: tokensBody(replaceItem(tokens, n, item)) })),
    fc
      .oneof(
        fc.constant<unknown>(tokens),
        fc.constant<unknown>([{ tokens }]),
        fc.constant<unknown>(null),
        fc.integer(),
        fc.double({ noNaN: true, noDefaultInfinity: true }),
        fc.string({ maxLength: 8 }),
        fc.boolean(),
      )
      .map((v) => ({ mutation: "top-level non-object", bytes: utf8Encoder.encode(JSON.stringify(v)) })),
    fc
      .nat()
      .map((n) => ({ mutation: "truncated JSON", bytes: utf8Encoder.encode(valid.slice(0, n % valid.length)) })),
    fc
      .tuple(fc.nat(), fc.constantFrom(...INVALID_UTF8_SEQUENCES))
      .map(([n, seq]) => {
        const bytes = utf8Encoder.encode(valid);
        const at = n % (bytes.length + 1);
        return {
          mutation: "invalid UTF-8",
          bytes: new Uint8Array([...bytes.subarray(0, at), ...seq, ...bytes.subarray(at)]),
        };
      }),
  );
});
