// Tests for the TS_Validator (worker/src/validator.ts).
import fc from "fast-check";
import { describe, expect, it } from "vitest";
import fixture from "../../fixtures/expansion_validator.json";
import { isValidCandidate } from "../src/validator";
import {
  firstLetterMutationArb,
  tokenListArb,
  validCandidateArb,
  wordCountMutationArb,
} from "./support/arbitraries";

interface FixtureCase {
  id: string;
  tags: string[];
  tokens: string[];
  candidate: string;
  valid: boolean;
}

const cases: FixtureCase[] = (fixture as { cases: FixtureCase[] }).cases;

describe("REQ-VALIDATOR-2: TS_Validator matches every Validator_Fixture case", () => {
  it("REQ-VALIDATOR-2: the fixture has cases", () => {
    expect(cases.length).toBeGreaterThan(0);
  });

  for (const c of cases) {
    it(`REQ-VALIDATOR-2: case ${c.id}`, () => {
      // The message names only the case id, never the candidate text.
      expect(isValidCandidate(c.tokens, c.candidate), `fixture case ${c.id}`).toBe(c.valid);
    });
  }
});

describe("REQ-VALIDATOR-5, REQ-VALIDATOR-1, REQ-WORKERTEST-3: TS_Validator properties", () => {
  // Feature: shorthand-expansion, Property 1: Generated-valid candidates are accepted
  it("REQ-VALIDATOR-5, REQ-VALIDATOR-1: generated-valid candidates are accepted", () => {
    const pairArb = tokenListArb.chain((tokens) =>
      validCandidateArb(tokens).map((candidate) => ({ tokens, candidate })),
    );
    fc.assert(
      fc.property(pairArb, ({ tokens, candidate }) => isValidCandidate(tokens, candidate)),
      { seed: 601007, numRuns: 200 },
    );
  });
});

describe("REQ-VALIDATOR-6, REQ-VALIDATOR-1, REQ-WORKERTEST-3: TS_Validator first-letter property", () => {
  // Feature: shorthand-expansion, Property 2: Changing a first letter makes a candidate invalid
  it("REQ-VALIDATOR-6, REQ-VALIDATOR-1: changing a first letter makes a candidate invalid", () => {
    fc.assert(
      fc.property(firstLetterMutationArb, ({ tokens, candidate }) => !isValidCandidate(tokens, candidate)),
      { seed: 602007, numRuns: 200 },
    );
  });
});

describe("REQ-VALIDATOR-7, REQ-VALIDATOR-1, REQ-WORKERTEST-3: TS_Validator word-count property", () => {
  // Feature: shorthand-expansion, Property 3: A different word count makes a candidate invalid
  it("REQ-VALIDATOR-7, REQ-VALIDATOR-1: a different word count makes a candidate invalid", () => {
    fc.assert(
      fc.property(wordCountMutationArb, ({ tokens, candidate }) => !isValidCandidate(tokens, candidate)),
      { seed: 603007, numRuns: 200 },
    );
  });
});
