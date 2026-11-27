// Example tests for the Expand_Endpoint, `handleExpand` (worker/src/expand.ts):
// status codes, the E9 check order, the rate-limit key, the Model input, the
// 5-second timeout and the response headers (REQ-EXPAND-1 to REQ-EXPAND-11,
// REQ-WORKERTEST-2, REQ-WORKERTEST-4). Every dependency is a mock from
// ./support/mocks or a captured log; nothing reaches a real binding or the
// network. Tokens and candidates are synthetic test data, not user text.
import { afterEach, describe, expect, it, vi } from "vitest";
import { handleExpand, type ExpandDeps } from "../src/expand";
import type { ExpandLogEntry } from "../src/log";
import { workersAiModelCaller } from "../src/model";
import { MODEL_ID, SYSTEM_PROMPT } from "../src/prompt";
import { MockAi, MockModelCaller, MockRateLimiter } from "./support/mocks";

const URL_EXPAND = "https://sounder.test/expand";
const VALID_BODY = '{"tokens":["I","W","S","W","P"]}';
const TEST_IP = "198.51.100.23";

/** Synthetic candidates valid for I W S W P. */
const CANDIDATE_A = "I want some water please";
const CANDIDATE_B = "I wish someone would phone";

/** A model reply in the Workers AI shape with [candidates] as a JSON string. */
function modelReply(candidates: unknown[]): unknown {
  return { response: JSON.stringify({ candidates }) };
}

interface Harness {
  deps: ExpandDeps;
  limiter: MockRateLimiter;
  model: MockModelCaller;
  logs: ExpandLogEntry[];
}

/** Builds mock dependencies; the clock advances 1 ms per read. */
function harness(reply: unknown = modelReply([CANDIDATE_A, CANDIDATE_B])): Harness {
  const limiter = new MockRateLimiter(20);
  const model = new MockModelCaller({ kind: "resolve", reply });
  const logs: ExpandLogEntry[] = [];
  let clock = 1000;
  return {
    limiter,
    model,
    logs,
    deps: {
      rateLimiter: limiter,
      modelCaller: model.caller,
      now: () => clock++,
      log: (entry) => logs.push(entry),
    },
  };
}

interface PostOptions {
  body?: string | Uint8Array;
  contentType?: string | null;
  ip?: string | null;
  method?: string;
}

/** A real Fetch `Request` to /expand. */
function request({
  body = VALID_BODY,
  contentType = "application/json",
  ip = TEST_IP,
  method = "POST",
}: PostOptions = {}): Request {
  const headers = new Headers();
  if (contentType !== null) headers.set("Content-Type", contentType);
  if (ip !== null) headers.set("CF-Connecting-IP", ip);
  const init: RequestInit = { method, headers };
  if (method !== "GET" && method !== "HEAD") init.body = body;
  return new Request(URL_EXPAND, init);
}

/**
 * A minimal Request-like POST with only the members `handleExpand` and
 * `readBodyLimited` use: `method`, `headers` and `body`. Used where a test
 * needs a `Content-Length` that disagrees with the body, or must see whether
 * the body stream was touched. Records body access, pulls and cancellation.
 */
class MockStreamRequest {
  readonly method = "POST";
  readonly headers: Headers;
  bodyAccessed = false;
  pulls = 0;
  cancelled = false;
  private readonly stream: ReadableStream<Uint8Array>;

  constructor(headers: Record<string, string>, chunks: Uint8Array[]) {
    this.headers = new Headers(headers);
    let index = 0;
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

/** A body of exactly [length] bytes that is a valid Token_List (padded with spaces). */
function validBodyOfLength(length: number): string {
  return VALID_BODY + " ".repeat(length - VALID_BODY.length);
}

async function bodyOf(response: Response): Promise<unknown> {
  return JSON.parse(await response.text());
}

/** Checks the REQ-EXPAND-11 headers on [response]. */
function expectStandardHeaders(response: Response): void {
  expect(response.headers.get("Content-Type")).toBe("application/json");
  expect(response.headers.get("Cache-Control")).toBe("no-store");
  expect(response.headers.has("Access-Control-Allow-Origin")).toBe(false);
}

afterEach(() => {
  vi.useRealTimers();
});

describe("REQ-EXPAND-10: 200 responses", () => {
  it("REQ-EXPAND-10: a valid request returns 200 with the processed candidates", async () => {
    const h = harness();
    const response = await handleExpand(request(), h.deps);
    expect(response.status).toBe(200);
    expect(await bodyOf(response)).toEqual({ candidates: [CANDIDATE_A, CANDIDATE_B] });
    expect(h.model.calls).toHaveLength(1);
    expect(h.logs).toHaveLength(1);
    expect(h.logs[0]).toMatchObject({ status: 200, tokenCount: 5, candidateCount: 2 });
  });

  it("REQ-EXPAND-10, REQ-REPLY-4: candidates the validator rejects are dropped from the 200 body", async () => {
    const h = harness(modelReply(["You want some water please", CANDIDATE_A, 42]));
    const response = await handleExpand(request(), h.deps);
    expect(response.status).toBe(200);
    expect(await bodyOf(response)).toEqual({ candidates: [CANDIDATE_A] });
  });

  it("REQ-EXPAND-10: an unparseable model reply returns 200 with an empty list", async () => {
    const h = harness({ response: "no json here" });
    const response = await handleExpand(request(), h.deps);
    expect(response.status).toBe(200);
    expect(await bodyOf(response)).toEqual({ candidates: [] });
    expect(h.logs[0]).toMatchObject({ status: 200, tokenCount: 5, candidateCount: 0 });
  });
});

describe("REQ-EXPAND-1: method", () => {
  for (const method of ["GET", "PUT", "DELETE"]) {
    it(`REQ-EXPAND-1, REQ-EXPAND-5: ${method} returns 405 with Allow: POST and no limiter call`, async () => {
      const h = harness();
      const response = await handleExpand(request({ method }), h.deps);
      expect(response.status).toBe(405);
      expect(response.headers.get("Allow")).toBe("POST");
      expect(await bodyOf(response)).toEqual({ error: "method_not_allowed" });
      expect(h.limiter.calls).toBe(0);
      expect(h.model.calls).toHaveLength(0);
    });
  }
});

describe("REQ-EXPAND-2: Content-Type", () => {
  it("REQ-EXPAND-2: a missing Content-Type returns 415", async () => {
    const h = harness();
    const response = await handleExpand(request({ contentType: null }), h.deps);
    expect(response.status).toBe(415);
    expect(await bodyOf(response)).toEqual({ error: "unsupported_media_type" });
    expect(h.model.calls).toHaveLength(0);
  });

  it("REQ-EXPAND-2: Content-Type text/plain returns 415", async () => {
    const h = harness();
    const response = await handleExpand(request({ contentType: "text/plain" }), h.deps);
    expect(response.status).toBe(415);
    expect(await bodyOf(response)).toEqual({ error: "unsupported_media_type" });
  });

  for (const contentType of ["application/json; charset=utf-8", "Application/JSON"]) {
    it(`REQ-EXPAND-2: Content-Type "${contentType}" is accepted`, async () => {
      const h = harness();
      const response = await handleExpand(request({ contentType }), h.deps);
      expect(response.status).toBe(200);
    });
  }
});

describe("REQ-EXPAND-3: body size", () => {
  it("REQ-EXPAND-3: a valid body of exactly 1,024 bytes is accepted", async () => {
    const h = harness();
    const response = await handleExpand(request({ body: validBodyOfLength(1024) }), h.deps);
    expect(response.status).toBe(200);
  });

  it("REQ-EXPAND-3: a body of 1,025 bytes returns 413", async () => {
    const h = harness();
    const response = await handleExpand(request({ body: validBodyOfLength(1025) }), h.deps);
    expect(response.status).toBe(413);
    expect(await bodyOf(response)).toEqual({ error: "payload_too_large" });
    expect(h.model.calls).toHaveLength(0);
  });

  it("REQ-EXPAND-3: a large Content-Length returns 413 without reading the body", async () => {
    const h = harness();
    const mock = new MockStreamRequest(
      { "Content-Type": "application/json", "Content-Length": "5000" },
      [bytesOf(10)],
    );
    const response = await handleExpand(mock.asRequest(), h.deps);
    expect(response.status).toBe(413);
    expect(mock.bodyAccessed).toBe(false);
    expect(mock.pulls).toBe(0);
  });

  it("REQ-EXPAND-3: a body larger than its Content-Length claims returns 413", async () => {
    const h = harness();
    const mock = new MockStreamRequest(
      { "Content-Type": "application/json", "Content-Length": "10" },
      [bytesOf(400), bytesOf(400), bytesOf(400)],
    );
    const response = await handleExpand(mock.asRequest(), h.deps);
    expect(response.status).toBe(413);
    expect(mock.cancelled).toBe(true);
  });
});

describe("REQ-EXPAND-4: body shape", () => {
  const badBodies: Array<[string, string | Uint8Array]> = [
    ["not JSON", "tokens: I W"],
    ["an extra key", '{"tokens":["I"],"extra":1}'],
    ["an empty list", '{"tokens":[]}'],
    ["13 tokens", JSON.stringify({ tokens: Array.from({ length: 13 }, () => "a") })],
    ["a 9-letter token", '{"tokens":["abcdefghi"]}'],
    ["a token with a digit", '{"tokens":["a1"]}'],
    ["a top-level array", '["I","W"]'],
    ["an empty body", ""],
    ["invalid UTF-8", new Uint8Array([0x7b, 0xff, 0x7d])],
  ];
  for (const [name, body] of badBodies) {
    it(`REQ-EXPAND-4: ${name} returns 400`, async () => {
      const h = harness();
      const response = await handleExpand(request({ body }), h.deps);
      expect(response.status).toBe(400);
      expect(await bodyOf(response)).toEqual({ error: "bad_request" });
      expect(h.model.calls).toHaveLength(0);
      expect(h.logs[0]).toMatchObject({ status: 400, tokenCount: 0, candidateCount: 0 });
    });
  }
});

describe("REQ-EXPAND-5: check order (E9)", () => {
  it("REQ-EXPAND-5, REQ-EXPAND-7: an over-limit request with an invalid body returns 429 and its body is not read", async () => {
    const h = harness();
    h.limiter.limitPerWindow = 0;
    const mock = new MockStreamRequest(
      { "Content-Type": "text/plain", "CF-Connecting-IP": TEST_IP },
      [new TextEncoder().encode("not json")],
    );
    const response = await handleExpand(mock.asRequest(), h.deps);
    expect(response.status).toBe(429);
    expect(await bodyOf(response)).toEqual({ error: "rate_limited" });
    expect(mock.bodyAccessed).toBe(false);
    expect(mock.pulls).toBe(0);
    expect(h.limiter.calls).toBe(1);
    expect(h.model.calls).toHaveLength(0);
  });

  it("REQ-EXPAND-5, REQ-EXPAND-6: requests rejected with 415, 413 and 400 still count, so the 21st request returns 429", async () => {
    const h = harness();
    const statuses: number[] = [];
    for (let i = 0; i < 20; i++) {
      const kind = i % 4;
      const req =
        kind === 0
          ? request({ contentType: "text/plain" })
          : kind === 1
            ? request({ body: validBodyOfLength(1025) })
            : kind === 2
              ? request({ body: '{"tokens":[]}' })
              : request();
      statuses.push((await handleExpand(req, h.deps)).status);
    }
    expect(statuses.filter((s) => s === 415)).toHaveLength(5);
    expect(statuses.filter((s) => s === 413)).toHaveLength(5);
    expect(statuses.filter((s) => s === 400)).toHaveLength(5);
    expect(statuses.filter((s) => s === 200)).toHaveLength(5);

    const response = await handleExpand(request(), h.deps);
    expect(response.status).toBe(429);
    expect(h.limiter.calls).toBe(21);
    expect(h.model.calls).toHaveLength(5);
  });

  it("REQ-EXPAND-6: a throwing Rate_Limiter is treated as allowed (D5)", async () => {
    const h = harness();
    h.limiter.throwOnLimit = true;
    const response = await handleExpand(request(), h.deps);
    expect(response.status).toBe(200);
  });
});

describe("REQ-EXPAND-6: rate-limit key", () => {
  it("REQ-EXPAND-6: the key is the CF-Connecting-IP value, used exactly once", async () => {
    const h = harness();
    await handleExpand(request({ ip: TEST_IP }), h.deps);
    expect(h.limiter.keys).toEqual([TEST_IP]);
  });

  it("REQ-EXPAND-6: the key is unknown when CF-Connecting-IP is missing (E13)", async () => {
    const h = harness();
    await handleExpand(request({ ip: null }), h.deps);
    expect(h.limiter.keys).toEqual(["unknown"]);
  });
});

describe("REQ-EXPAND-8: Model input", () => {
  it("REQ-EXPAND-8: the system prompt states the required clauses", () => {
    expect(SYSTEM_PROMPT).toContain("Each item is the start of one word (one or more letters), in order.");
    expect(SYSTEM_PROMPT).toContain("exactly 4 different candidate sentences as JSON");
    expect(SYSTEM_PROMPT).toContain('{"candidates":[');
    expect(SYSTEM_PROMPT).toContain("exactly one word per item");
    expect(SYSTEM_PROMPT).toContain("everyday, first-person language");
    expect(SYSTEM_PROMPT).toContain("carer or friend");
  });

  it("REQ-EXPAND-8: one Model call with the system prompt and the tokens joined by spaces", async () => {
    const h = harness();
    await handleExpand(request(), h.deps);
    expect(h.model.calls).toHaveLength(1);
    expect(h.model.calls[0]!.messages).toEqual([
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: "I W S W P" },
    ]);
  });

  it("REQ-EXPAND-8, REQ-WORKERTEST-2: workersAiModelCaller passes the model id, temperature 0.2 and max_tokens 200", async () => {
    const ai = new MockAi({ response: "{}" });
    const caller = workersAiModelCaller(ai.asAi());
    const messages = [
      { role: "system" as const, content: SYSTEM_PROMPT },
      { role: "user" as const, content: "I W S W P" },
    ];
    const signal = new AbortController().signal;
    await caller(messages, signal);
    expect(ai.runs).toHaveLength(1);
    const run = ai.runs[0]!;
    expect(run.model).toBe(MODEL_ID);
    expect(MODEL_ID).toBe("@cf/meta/llama-4-scout-17b-16e-instruct");
    expect(run.inputs).toEqual({ messages, temperature: 0.2, max_tokens: 200 });
    expect(run.options).toEqual({ signal });
  });
});

describe("REQ-EXPAND-9: Model failure and timeout", () => {
  it("REQ-EXPAND-9: a Model error returns 503", async () => {
    const h = harness();
    h.model.behaviour = { kind: "reject" };
    const response = await handleExpand(request(), h.deps);
    expect(response.status).toBe(503);
    expect(await bodyOf(response)).toEqual({ error: "model_unavailable" });
    expect(h.logs[0]).toMatchObject({ status: 503, tokenCount: 5, candidateCount: 0 });
  });

  it("REQ-EXPAND-9: a Model that never resolves returns 503 after 5 seconds and the signal is aborted", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    const h = harness();
    h.model.behaviour = { kind: "never" };
    let settled: Response | undefined;
    const pending = handleExpand(request(), h.deps).then((r) => (settled = r));

    // Let the checks and body read run until the Model call starts.
    for (let i = 0; i < 100 && h.model.calls.length === 0; i++) {
      await vi.advanceTimersByTimeAsync(0);
    }
    expect(h.model.calls).toHaveLength(1);
    const signal = h.model.calls[0]!.signal;

    await vi.advanceTimersByTimeAsync(4999);
    expect(settled).toBeUndefined();
    expect(signal.aborted).toBe(false);

    await vi.advanceTimersByTimeAsync(1);
    const response = await pending;
    expect(response.status).toBe(503);
    expect(await bodyOf(response)).toEqual({ error: "model_unavailable" });
    expect(signal.aborted).toBe(true);
  });
});

describe("REQ-EXPAND-11: headers and error bodies", () => {
  const cases: Array<{
    name: string;
    status: number;
    body: unknown;
    make: (h: Harness) => Request;
  }> = [
    { name: "200", status: 200, body: { candidates: [CANDIDATE_A, CANDIDATE_B] }, make: () => request() },
    { name: "405", status: 405, body: { error: "method_not_allowed" }, make: () => request({ method: "GET" }) },
    {
      name: "429",
      status: 429,
      body: { error: "rate_limited" },
      make: (h) => {
        h.limiter.limitPerWindow = 0;
        return request();
      },
    },
    { name: "415", status: 415, body: { error: "unsupported_media_type" }, make: () => request({ contentType: "text/plain" }) },
    { name: "413", status: 413, body: { error: "payload_too_large" }, make: () => request({ body: validBodyOfLength(1025) }) },
    { name: "400", status: 400, body: { error: "bad_request" }, make: () => request({ body: "{}" }) },
    {
      name: "503",
      status: 503,
      body: { error: "model_unavailable" },
      make: (h) => {
        h.model.behaviour = { kind: "reject" };
        return request();
      },
    },
  ];
  for (const c of cases) {
    it(`REQ-EXPAND-11: a ${c.name} response has the standard headers and the exact body`, async () => {
      const h = harness();
      const req = c.make(h);
      const response = await handleExpand(req, h.deps);
      expect(response.status).toBe(c.status);
      expectStandardHeaders(response);
      expect(await bodyOf(response)).toEqual(c.body);
      expect(h.logs).toHaveLength(1);
      expect(h.logs[0]!.status).toBe(c.status);
    });
  }
});
