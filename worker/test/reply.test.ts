// Tests for the Reply_Processor (worker/src/reply.ts).
// Candidates below are synthetic test strings, not user text.
// Property 4 (task 3.3) and Property 5 (task 3.4) are at the end of this file.
import fc from "fast-check";
import { describe, expect, it } from "vitest";
import { isValidCandidate, trimE2 } from "../src/validator";
import { modelReplyArb, sentenceCaseInputArb } from "./support/arbitraries";
import {
  duplicateKey,
  extractCandidatesArray,
  processReply,
  sentenceCase,
  shouldSentenceCase,
} from "../src/reply";

const IWSWP = ["I", "W", "S", "W", "P"];

/** A Workers AI reply whose `response` is the JSON text of `{candidates}`. */
function stringReply(candidates: unknown[]): unknown {
  return { response: JSON.stringify({ candidates }) };
}

describe("REQ-REPLY-1: JSON extraction (E8)", () => {
  it("REQ-REPLY-1: response as a JSON string", () => {
    expect(extractCandidatesArray(stringReply(["a", "b"]))).toEqual(["a", "b"]);
  });

  it("REQ-REPLY-1: response as an already-parsed object", () => {
    expect(extractCandidatesArray({ response: { candidates: ["a", "b"] } })).toEqual(["a", "b"]);
  });

  it("REQ-REPLY-1: text around the JSON object is ignored", () => {
    const reply = { response: 'Here you go:\n{"candidates":["a","b"]}\nHope that helps.' };
    expect(extractCandidatesArray(reply)).toEqual(["a", "b"]);
  });

  it("REQ-REPLY-1: a string with no braces is unparseable", () => {
    expect(extractCandidatesArray({ response: "no json here" })).toBeNull();
    expect(processReply({ response: "no json here" }, IWSWP)).toEqual([]);
  });

  it("REQ-REPLY-1: a last } before the first { is unparseable", () => {
    expect(extractCandidatesArray({ response: '} "candidates" {' })).toBeNull();
  });

  it("REQ-REPLY-1: invalid JSON between the braces is unparseable", () => {
    expect(extractCandidatesArray({ response: '{"candidates":[' + "}" })).toBeNull();
  });

  it("REQ-REPLY-1: candidates missing gives an empty list", () => {
    expect(extractCandidatesArray({ response: '{"other":["a"]}' })).toBeNull();
    expect(extractCandidatesArray({ response: { other: ["a"] } })).toBeNull();
    expect(processReply({ response: { other: ["I want some water please"] } }, IWSWP)).toEqual([]);
  });

  it("REQ-REPLY-1: candidates not an array gives an empty list", () => {
    expect(extractCandidatesArray({ response: '{"candidates":"I want some water please"}' })).toBeNull();
    expect(extractCandidatesArray({ response: { candidates: { a: 1 } } })).toBeNull();
    expect(
      processReply({ response: { candidates: "I want some water please" } }, IWSWP),
    ).toEqual([]);
  });

  it("REQ-REPLY-1: a reply that is not an object, or has no response, gives an empty list", () => {
    for (const reply of [null, undefined, 42, "text", [], {}, { response: 7 }, { response: null }]) {
      expect(extractCandidatesArray(reply)).toBeNull();
      expect(processReply(reply, IWSWP)).toEqual([]);
    }
  });

  it("REQ-REPLY-1: a top-level JSON array in the response is not a candidates object", () => {
    expect(extractCandidatesArray({ response: ["I want some water please"] })).toBeNull();
  });
});

describe("REQ-REPLY-2: string items and trimming", () => {
  it("REQ-REPLY-2: non-string items are dropped and model order is kept", () => {
    const reply = stringReply([
      42,
      "I want some water please",
      null,
      { text: "I want some wine please" },
      ["I want some soup please"],
      "I will start watching programmes",
      true,
    ]);
    expect(processReply(reply, IWSWP)).toEqual([
      "I want some water please",
      "I will start watching programmes",
    ]);
  });

  it("REQ-REPLY-2: E2 whitespace is trimmed from both ends", () => {
    const reply = stringReply([" \t I want some water please \n\r", "\fI want some wine please\v"]);
    expect(processReply(reply, IWSWP)).toEqual([
      "I want some water please",
      "I want some wine please",
    ]);
  });

  it("REQ-REPLY-2: inner whitespace is kept as it is", () => {
    const reply = stringReply(["I  want some\twater please"]);
    expect(processReply(reply, IWSWP)).toEqual(["I  want some\twater please"]);
  });
});

describe("REQ-REPLY-3: Sentence_Case (E6)", () => {
  it("REQ-REPLY-3: I Want Some Water Please becomes I want some water please", () => {
    expect(shouldSentenceCase("I Want Some Water Please")).toBe(true);
    expect(sentenceCase("I Want Some Water Please")).toBe("I want some water please");
    expect(processReply(stringReply(["I Want Some Water Please"]), IWSWP)).toEqual([
      "I want some water please",
    ]);
  });

  it("REQ-REPLY-3: I'm with an ASCII apostrophe keeps the capital I", () => {
    expect(sentenceCase("Yes I'm Very Happy")).toBe("Yes I'm very happy");
    expect(processReply(stringReply(["Yes I'm Very Happy"]), ["Y", "I", "V", "H"])).toEqual([
      "Yes I'm very happy",
    ]);
  });

  it("REQ-REPLY-3: I\u2019m with a curly apostrophe keeps the capital I", () => {
    expect(sentenceCase("Yes I\u2019m Very Happy")).toBe("Yes I\u2019m very happy");
    expect(
      processReply(stringReply(["Yes I\u2019m Very Happy"]), ["Y", "I", "V", "H"]),
    ).toEqual(["Yes I\u2019m very happy"]);
  });

  it("REQ-REPLY-3: strip characters and whitespace stay in place", () => {
    expect(sentenceCase('"Please, Come Here!"')).toBe('"Please, come here!"');
    expect(sentenceCase("(Hello)  World.")).toBe("(Hello)  world.");
  });

  it("REQ-REPLY-3: a single word is not converted", () => {
    expect(shouldSentenceCase("WATER")).toBe(false);
    expect(processReply(stringReply(["WATER"]), ["W"])).toEqual(["WATER"]);
    expect(processReply(stringReply(["Water"]), ["W"])).toEqual(["Water"]);
  });

  it("REQ-REPLY-3: a candidate with a lowercase word is not converted", () => {
    expect(shouldSentenceCase("I Want some Water Please")).toBe(false);
    expect(processReply(stringReply(["I Want some Water Please"]), IWSWP)).toEqual([
      "I Want some Water Please",
    ]);
  });
});

describe("REQ-REPLY-4: validation, duplicates and the first 4", () => {
  it("REQ-REPLY-4: candidates the TS_Validator rejects are dropped", () => {
    const reply = stringReply([
      "You want some water please", // first letter differs
      "I want water please", // word count differs
      "I want some water please",
      "I want some caf\u00e9 please", // non-ASCII letter
    ]);
    expect(processReply(reply, IWSWP)).toEqual(["I want some water please"]);
  });

  it("REQ-REPLY-4: duplicates by letter case are dropped, the first is kept", () => {
    expect(duplicateKey("I Want Some Water Please")).toBe(duplicateKey("i want some water please"));
    const reply = stringReply([
      "I want some water please",
      "i want some water please",
      "I WANT SOME WATER PLEASE",
    ]);
    expect(processReply(reply, IWSWP)).toEqual(["I want some water please"]);
  });

  it("REQ-REPLY-4: duplicates by trailing ! are dropped, the first is kept", () => {
    expect(duplicateKey("I want some water please!")).toBe("i want some water please");
    expect(duplicateKey("I want some water please?!.")).toBe("i want some water please");
    const reply = stringReply([
      "I want some water please!",
      "I want some water please",
      "I want some water please.",
    ]);
    expect(processReply(reply, IWSWP)).toEqual(["I want some water please!"]);
  });

  it("REQ-REPLY-4: Sentence_Case runs before the duplicate check", () => {
    const reply = stringReply(["I want some water please", "I Want Some Water Please"]);
    expect(processReply(reply, IWSWP)).toEqual(["I want some water please"]);
  });

  it("REQ-REPLY-4: more than 4 valid candidates keeps the first 4 in model order", () => {
    const valid = [
      "I want some water please",
      "I would start with porridge",
      "Invalid one here", // rejected, does not use a slot
      "I will see who phoned",
      "I want some wine please",
      "I wish someone would phone",
      "I washed some white pants",
    ];
    expect(processReply(stringReply(valid), IWSWP)).toEqual([
      "I want some water please",
      "I would start with porridge",
      "I will see who phoned",
      "I want some wine please",
    ]);
  });

  it("REQ-REPLY-4: a duplicate does not use one of the 4 slots", () => {
    const reply = stringReply([
      "I want some water please",
      "I want some water please!",
      "I would start with porridge",
      "I will see who phoned",
      "I want some wine please",
    ]);
    expect(processReply(reply, IWSWP)).toEqual([
      "I want some water please",
      "I would start with porridge",
      "I will see who phoned",
      "I want some wine please",
    ]);
  });
});

describe("REQ-REPLY-5: Sentence_Case properties", () => {
  // Feature: shorthand-expansion, Property 4: Sentence-case conversion preserves validity
  it("REQ-REPLY-5, REQ-REPLY-3, REQ-WORKERTEST-3: sentence-case conversion preserves validity", () => {
    fc.assert(
      fc.property(
        sentenceCaseInputArb,
        ({ tokens, candidate }) =>
          isValidCandidate(tokens, candidate) === isValidCandidate(tokens, sentenceCase(candidate)),
      ),
      { seed: 604007, numRuns: 200 },
    );
  });
});

/**
 * The string items of [items], E2-trimmed and sentence-cased as in
 * REQ-REPLY-2 and REQ-REPLY-3, in model order; empty for null.
 */
function processedStrings(items: readonly unknown[] | null): string[] {
  const out: string[] = [];
  for (const item of items ?? []) {
    if (typeof item !== "string") continue;
    const trimmed = trimE2(item);
    out.push(shouldSentenceCase(trimmed) ? sentenceCase(trimmed) : trimmed);
  }
  return out;
}

/** True when [sub] is an in-order subsequence of [list]. */
function isSubsequence(sub: readonly string[], list: readonly string[]): boolean {
  let j = 0;
  for (const item of sub) {
    while (j < list.length && list[j] !== item) j++;
    if (j === list.length) return false;
    j++;
  }
  return true;
}

describe("REQ-REPLY-6: Reply_Processor output properties", () => {
  // Feature: shorthand-expansion, Property 5: Reply processing output is small, valid, distinct and in model order
  it("REQ-REPLY-6, REQ-REPLY-4, REQ-REPLY-1, REQ-REPLY-2, REQ-WORKERTEST-3: reply processing output is small, valid, distinct and in model order", () => {
    fc.assert(
      fc.property(modelReplyArb, ({ tokens, reply, items }) => {
        const out = processReply(reply, tokens);
        if (out.length > 4) return false;
        if (!out.every((c) => isValidCandidate(tokens, c))) return false;
        if (new Set(out.map(duplicateKey)).size !== out.length) return false;
        return isSubsequence(out, processedStrings(items));
      }),
      { seed: 605007, numRuns: 200 },
    );
  });
});
