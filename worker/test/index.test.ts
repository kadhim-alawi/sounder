// Routing pass-through tests for the Worker entry point (worker/src/index.ts,
// REQ-ROUTE-5, E15). Every binding is a mock from ./support/mocks; nothing
// reaches a real binding or the network.
import { describe, expect, it } from "vitest";
import type { Env } from "../src/env";
import worker from "../src/index";
import { MockAi, MockAssets, MockRateLimiter } from "./support/mocks";

/** Mock bindings and the `Env` built from them (REQ-ROUTE-5). */
interface Bindings {
  env: Env;
  assets: MockAssets;
  ai: MockAi;
  limiter: MockRateLimiter;
}

/** Builds an `Env` whose bindings are all mocks (REQ-ROUTE-5, REQ-WORKERTEST-2). */
function bindings(): Bindings {
  const assets = new MockAssets(new Response("asset body", { status: 200 }));
  const ai = new MockAi();
  const limiter = new MockRateLimiter(20);
  const env: Env = {
    ASSETS: assets.asFetcher(),
    AI: ai.asAi(),
    EXPAND_RATE_LIMITER: limiter as unknown as RateLimit,
  };
  return { env, assets, ai, limiter };
}

describe("REQ-ROUTE-5: paths other than /expand pass to ASSETS unchanged", () => {
  it("REQ-ROUTE-5: GET /main.dart.js is passed to ASSETS unchanged", async () => {
    const { env, assets, ai, limiter } = bindings();
    const request = new Request("https://sounder.test/main.dart.js", { method: "GET" });

    const response = await worker.fetch(request, env);

    expect(assets.requests).toHaveLength(1);
    expect(assets.requests[0]).toBe(request);
    expect(response).toBe(assets.response);
    expect(ai.runs).toHaveLength(0);
    expect(limiter.calls).toBe(0);
  });

  it("REQ-ROUTE-5: POST /other is passed to ASSETS unchanged", async () => {
    const { env, assets, ai, limiter } = bindings();
    const request = new Request("https://sounder.test/other", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: '{"tokens":["I"]}',
    });

    const response = await worker.fetch(request, env);

    expect(assets.requests).toHaveLength(1);
    expect(assets.requests[0]).toBe(request);
    expect(response).toBe(assets.response);
    expect(ai.runs).toHaveLength(0);
    expect(limiter.calls).toBe(0);
  });
});
