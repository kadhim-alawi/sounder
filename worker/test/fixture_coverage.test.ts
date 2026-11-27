// Shape and coverage checks for fixtures/expansion_validator.json (REQ-VALIDATOR-3).
import { describe, expect, it } from "vitest";
import fixture from "../../fixtures/expansion_validator.json";

/** Required tags from the design's tag table (REQ-VALIDATOR-3). */
const REQUIRED_TAGS: readonly string[] = [
  "a-valid",
  "a-invalid",
  "len-200",
  "len-201",
  "b-valid",
  "b-invalid",
  "c-valid",
  "c-invalid",
  "d-valid",
  "d-invalid",
  "strip-.",
  "strip-,",
  "strip-!",
  "strip-?",
  "strip-;",
  "strip-:",
  'strip-"',
  "strip-(",
  "strip-)",
  "apos-ascii",
  "apos-curly",
  "hyphen",
  "lead-apos",
  "trail-apos",
  "lead-hyphen",
  "trail-hyphen",
  "non-ascii-letter",
  "unicode-space",
  "token-longer-than-word",
];

const ROOT_KEYS = ["cases", "version"];
const CASE_KEYS = ["candidate", "id", "tags", "tokens", "valid"];
const ID_PATTERN = /^[a-z0-9-]+$/;
const TOKEN_PATTERN = /^[A-Za-z]{1,8}$/;

const root: unknown = fixture;

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function sortedKeys(o: Record<string, unknown>): string[] {
  return Object.keys(o).sort();
}

/** Cases as raw values, so the shape checks do not trust the JSON's inferred type. */
function rawCases(): unknown[] {
  if (!isPlainObject(root) || !Array.isArray(root.cases)) return [];
  return root.cases;
}

/** Label for a failing case: its id when it has one, else its index. Never the candidate. */
function label(c: unknown, index: number): string {
  return isPlainObject(c) && typeof c.id === "string" ? c.id : `#${index}`;
}

describe("REQ-VALIDATOR-3: Validator_Fixture schema shape", () => {
  it("REQ-VALIDATOR-3: root is an object with exactly version and cases", () => {
    expect(isPlainObject(root)).toBe(true);
    expect(sortedKeys(root as Record<string, unknown>)).toEqual(ROOT_KEYS);
  });

  it("REQ-VALIDATOR-3: version is 1", () => {
    expect((root as Record<string, unknown>).version).toBe(1);
  });

  it("REQ-VALIDATOR-3: cases is a non-empty array", () => {
    expect(Array.isArray((root as Record<string, unknown>).cases)).toBe(true);
    expect(rawCases().length).toBeGreaterThan(0);
  });

  it("REQ-VALIDATOR-3: every case has exactly the required keys with the right types", () => {
    rawCases().forEach((c, i) => {
      const name = label(c, i);
      expect(isPlainObject(c), `case ${name} is an object`).toBe(true);
      const o = c as Record<string, unknown>;
      expect(sortedKeys(o), `case ${name} keys`).toEqual(CASE_KEYS);
      expect(typeof o.id === "string" && ID_PATTERN.test(o.id), `case ${name} id pattern`).toBe(true);
      expect(
        Array.isArray(o.tags) && o.tags.length >= 1 && o.tags.every((t) => typeof t === "string"),
        `case ${name} tags`,
      ).toBe(true);
      expect(typeof o.candidate, `case ${name} candidate type`).toBe("string");
      expect(typeof o.valid, `case ${name} valid type`).toBe("boolean");
    });
  });

  it("REQ-VALIDATOR-3: every case has 1 to 12 tokens of 1 to 8 ASCII letters", () => {
    rawCases().forEach((c, i) => {
      const name = label(c, i);
      const tokens = (c as Record<string, unknown>).tokens;
      expect(Array.isArray(tokens), `case ${name} tokens is an array`).toBe(true);
      const list = tokens as unknown[];
      expect(list.length >= 1 && list.length <= 12, `case ${name} token count`).toBe(true);
      for (const t of list) {
        expect(typeof t === "string" && TOKEN_PATTERN.test(t), `case ${name} token pattern`).toBe(true);
      }
    });
  });

  it("REQ-VALIDATOR-3: case ids are unique", () => {
    const seen = new Set<string>();
    const duplicates: string[] = [];
    rawCases().forEach((c, i) => {
      const id = label(c, i);
      if (seen.has(id)) duplicates.push(id);
      seen.add(id);
    });
    expect(duplicates).toEqual([]);
  });
});

describe("REQ-VALIDATOR-3: Validator_Fixture covers every required tag", () => {
  const present = new Set<string>();
  for (const c of rawCases()) {
    if (isPlainObject(c) && Array.isArray(c.tags)) {
      for (const t of c.tags) if (typeof t === "string") present.add(t);
    }
  }

  for (const tag of REQUIRED_TAGS) {
    it(`REQ-VALIDATOR-3: at least one case has tag ${tag}`, () => {
      expect(present.has(tag), `required tag ${tag}`).toBe(true);
    });
  }
});
