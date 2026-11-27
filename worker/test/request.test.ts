// Example tests for request parsing (worker/src/request.ts): the capped body
// read (REQ-EXPAND-3, design D7, E11) and the body shape check (REQ-EXPAND-4).
// Bodies below are synthetic test data, not user text. Nothing is logged.
// Property 6 (task 5.3) is at the end of this file.
import fc from "fast-check";
import { describe, expect, it } from "vitest";
import { parseTokenRequest, readBodyLimited } from "../src/request";
import { mutatedTokenBodyArb, validTokenBodyArb } from "./support/arbitraries";

const LIMIT = 1024;
const encoder = new TextEncoder();

/** A real Fetch `Request` POSTing [body] to /expand. */
function postRequest(body: string | Uint8Array): Request {
  return new Request("https://sounder.test/expand", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body,
  });
}

/**
 * A minimal Request-like object with only the two members readBodyLimited
 * uses: `headers` and `body`. Used where a test needs a `Content-Length`
 * header that disagrees with the body, which a real `Request` cannot be
 * relied on to keep. It records whether `body` was accessed, whether the
 * stream was pulled, and whether the reader was cancelled.
 */
class MockRequestWithBody {
  bodyAccessed = false;
  pulls = 0;
  cancelled = false;
  readonly headers: Headers;
  private readonly stream: ReadableStream<Uint8Array>;

  constructor(contentLength: string | null, chunks: Uint8Array[]) {
    this.headers = new Headers();
    if (contentLength !== null) this.headers.set("Content-Length", contentLength);
    let index = 0;
    // highWaterMark 0: the stream pulls only when a reader asks for data,
    // so `pulls` counts real reads (no eager pull at construction).
    this.stream = new ReadableStream<Uint8Array>(
      {
        pull: (controller) => {
          this.pulls += 1;
          if (index < chunks.length) controller.enqueue(chunks[index++]!);
          else controller.close();
        },
        cancel: () => {
          this.cancelled = true;
        },
      },
      { highWaterMark: 0 },
    );
  }

  get body(): ReadableStream<Uint8Array> {
    this.bodyAccessed = true;
    return this.stream;
  }

  asRequest(): Request {
    return this as unknown as Request;
  }
}

function bytesOf(length: number): Uint8Array {
  return new Uint8Array(length).fill(0x61); // "a"
}

function utf8(text: string): Uint8Array {
  return encoder.encode(text);
}

describe("REQ-EXPAND-3: capped body read (D7, E11)", () => {
  it("REQ-EXPAND-3: a body of exactly 1,024 bytes is accepted and returned whole", async () => {
    const body = bytesOf(LIMIT);
    const result = await readBodyLimited(postRequest(body), LIMIT);
    expect(result).not.toBe("too_large");
    expect(result).toEqual(body);
  });

  it("REQ-EXPAND-3: a body of 1,025 bytes is too large", async () => {
    const result = await readBodyLimited(postRequest(bytesOf(LIMIT + 1)), LIMIT);
    expect(result).toBe("too_large");
  });

  it("REQ-EXPAND-3: a valid token body is returned byte for byte", async () => {
    const text = '{"tokens":["I","W","S","W","P"]}';
    const result = await readBodyLimited(postRequest(text), LIMIT);
    expect(result).toEqual(utf8(text));
  });

  it("REQ-EXPAND-3: a Content-Length over 1,024 is rejected without reading the body", async () => {
    const mock = new MockRequestWithBody("5000", [bytesOf(10)]);
    const result = await readBodyLimited(mock.asRequest(), LIMIT);
    expect(result).toBe("too_large");
    expect(mock.bodyAccessed).toBe(false);
    expect(mock.pulls).toBe(0);
  });

  it("REQ-EXPAND-3: a body larger than its Content-Length claims is too large and the reader is cancelled", async () => {
    // The header claims 10 bytes; the stream sends 3 x 400 = 1,200 bytes.
    const mock = new MockRequestWithBody("10", [bytesOf(400), bytesOf(400), bytesOf(400)]);
    const result = await readBodyLimited(mock.asRequest(), LIMIT);
    expect(result).toBe("too_large");
    expect(mock.cancelled).toBe(true);
  });

  it("REQ-EXPAND-3: a streamed body of exactly 1,024 bytes in chunks is accepted", async () => {
    const mock = new MockRequestWithBody("1024", [bytesOf(512), bytesOf(512)]);
    const result = await readBodyLimited(mock.asRequest(), LIMIT);
    expect(result).toEqual(bytesOf(LIMIT));
    expect(mock.cancelled).toBe(false);
  });
});

describe("REQ-EXPAND-4: body shape (Token_List)", () => {
  it("REQ-EXPAND-4: a valid body parses to its Token_List", () => {
    expect(parseTokenRequest(utf8('{"tokens":["I","W","S","W","P"]}'))).toEqual([
      "I",
      "W",
      "S",
      "W",
      "P",
    ]);
  });

  it("REQ-EXPAND-4: 12 tokens of 8 letters are accepted", () => {
    const tokens = Array.from({ length: 12 }, () => "abcdefgh");
    expect(parseTokenRequest(utf8(JSON.stringify({ tokens })))).toEqual(tokens);
  });

  it("REQ-EXPAND-4: invalid UTF-8 returns null", () => {
    // `{"tokens":["I` + lone 0xFF byte + `"]}`
    const bytes = new Uint8Array([...utf8('{"tokens":["I'), 0xff, ...utf8('"]}')]);
    expect(parseTokenRequest(bytes)).toBeNull();
  });

  it("REQ-EXPAND-4: an extra key returns null", () => {
    expect(parseTokenRequest(utf8('{"tokens":["I"],"extra":1}'))).toBeNull();
  });

  it("REQ-EXPAND-4: an empty tokens list returns null", () => {
    expect(parseTokenRequest(utf8('{"tokens":[]}'))).toBeNull();
  });

  it("REQ-EXPAND-4: 13 tokens return null", () => {
    const tokens = Array.from({ length: 13 }, () => "a");
    expect(parseTokenRequest(utf8(JSON.stringify({ tokens })))).toBeNull();
  });

  it("REQ-EXPAND-4: a 9-letter token returns null", () => {
    expect(parseTokenRequest(utf8('{"tokens":["abcdefghi"]}'))).toBeNull();
  });

  it("REQ-EXPAND-4: a token holding a non-ASCII letter returns null", () => {
    expect(parseTokenRequest(utf8('{"tokens":["caf\u00e9"]}'))).toBeNull();
  });

  it("REQ-EXPAND-4: a top-level array returns null", () => {
    expect(parseTokenRequest(utf8('[{"tokens":["I"]}]'))).toBeNull();
  });
});

describe("REQ-EXPAND-4: body shape properties", () => {
  // Feature: shorthand-expansion, Property 6: Request body parsing accepts exactly the Token_List shape
  it("REQ-EXPAND-4, REQ-WORKERTEST-3: request body parsing accepts exactly the Token_List shape", () => {
    fc.assert(
      fc.property(
        fc.oneof(
          validTokenBodyArb.map(({ tokens, bytes }) => ({ expected: tokens as string[] | null, bytes })),
          mutatedTokenBodyArb.map(({ bytes }) => ({ expected: null as string[] | null, bytes })),
        ),
        ({ expected, bytes }) => {
          const parsed = parseTokenRequest(bytes);
          if (expected === null) return parsed === null;
          return (
            parsed !== null &&
            parsed.length === expected.length &&
            parsed.every((token, i) => token === expected[i])
          );
        },
      ),
      { seed: 606007, numRuns: 200 },
    );
  });
});
