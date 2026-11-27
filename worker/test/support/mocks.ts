// Test-only mocks for the Worker (REQ-WORKERTEST-2). Every class name begins
// with `Mock`, and none of them reaches a real Cloudflare binding or the
// network. Data recorded here stays in memory for assertions only.
import type { RateLimiter } from "../../src/expand";
import type { ModelCaller } from "../../src/model";
import type { ChatMessage } from "../../src/prompt";

/**
 * Mock Rate_Limiter (REQ-EXPAND-6, REQ-EXPAND-7, REQ-WORKERTEST-2).
 *
 * Records the key of every `limit` call. Allows up to [limitPerWindow]
 * calls per key in the current window; like the real binding (C3), a call
 * that returns `success: false` does not add to the count. `resetWindow()`
 * starts a new window. Set `throwOnLimit` to make `limit` reject (D5).
 */
export class MockRateLimiter implements RateLimiter {
  /** Keys passed to `limit`, in call order. */
  readonly keys: string[] = [];
  /** When true, `limit` rejects instead of answering. */
  throwOnLimit = false;
  private readonly counts = new Map<string, number>();

  constructor(public limitPerWindow = 20) { }

  /** Number of `limit` calls so far. */
  get calls(): number {
    return this.keys.length;
  }

  async limit(options: { key: string }): Promise<{ success: boolean }> {
    this.keys.push(options.key);
    if (this.throwOnLimit) throw new Error("MockRateLimiter failure");
    const used = this.counts.get(options.key) ?? 0;
    if (used >= this.limitPerWindow) return { success: false };
    this.counts.set(options.key, used + 1);
    return { success: true };
  }

  /** Starts a new rate-limit window with every count at 0. */
  resetWindow(): void {
    this.counts.clear();
  }
}

/** How a MockModelCaller answers: resolve with a reply, reject, or never settle. */
export type MockModelBehaviour =
  | { kind: "resolve"; reply: unknown }
  | { kind: "reject" }
  | { kind: "never" };

/** One recorded call to a MockModelCaller. */
export interface MockModelCall {
  messages: ChatMessage[];
  signal: AbortSignal;
}

/**
 * Mock Model_Caller (REQ-EXPAND-8, REQ-EXPAND-9, REQ-WORKERTEST-2).
 *
 * Pass `mock.caller` wherever a `ModelCaller` is expected. Each call records
 * its messages and abort signal, then follows `behaviour`.
 */
export class MockModelCaller {
  /** Calls received, in order. */
  readonly calls: MockModelCall[] = [];

  constructor(public behaviour: MockModelBehaviour = { kind: "resolve", reply: { response: "" } }) { }

  /** The `ModelCaller` function backed by this mock. */
  readonly caller: ModelCaller = (messages, signal) => {
    this.calls.push({ messages, signal });
    const b = this.behaviour;
    if (b.kind === "resolve") return Promise.resolve(b.reply);
    if (b.kind === "reject") return Promise.reject(new Error("MockModelCaller failure"));
    return new Promise<unknown>(() => undefined);
  };
}

/** One recorded call to `MockAi.run`. */
export interface MockAiRunCall {
  model: string;
  inputs: unknown;
  options: unknown;
}

/**
 * Mock Workers AI binding (REQ-EXPAND-8, REQ-WORKERTEST-2).
 *
 * Records the arguments of every `run` call and resolves to `reply`. Use
 * `asAi()` to pass it to `workersAiModelCaller`.
 */
export class MockAi {
  /** Calls received, in order. */
  readonly runs: MockAiRunCall[] = [];

  constructor(public reply: unknown = { response: "" }) { }

  async run(model: string, inputs: unknown, options?: unknown): Promise<unknown> {
    this.runs.push({ model, inputs, options });
    return this.reply;
  }

  /** This mock typed as the `Ai` binding. */
  asAi(): Ai {
    return this as unknown as Ai;
  }
}

/**
 * Mock ASSETS binding (REQ-ROUTE-5, REQ-WORKERTEST-2).
 *
 * Records every `Request` passed to `fetch` and answers each with the same
 * `response` object, so tests can check identity of both. Use `asFetcher()`
 * to place it in an `Env`.
 */
export class MockAssets {
  /** Requests received, in order. */
  readonly requests: Request[] = [];

  constructor(public response: Response = new Response("mock asset", { status: 200 })) { }

  async fetch(request: Request): Promise<Response> {
    this.requests.push(request);
    return this.response;
  }

  /** This mock typed as the `Fetcher` binding. */
  asFetcher(): Fetcher {
    return this as unknown as Fetcher;
  }
}
