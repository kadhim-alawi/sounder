/**
 * Bindings available to the Sounder Worker, as configured in the root
 * `wrangler.jsonc` (REQ-ROUTE-1, REQ-ROUTE-5, design D1, D16). The types come
 * from `@cloudflare/workers-types`.
 */
export interface Env {
  /**
   * Static assets of the Flutter web build (`assets.binding`, REQ-ROUTE-1).
   * Every path other than `/expand` is passed to it unchanged (REQ-ROUTE-5).
   */
  ASSETS: Fetcher;
  /** Workers AI binding (`ai.binding`) used by the Model_Caller (REQ-ROUTE-1, REQ-EXPAND-8). */
  AI: Ai;
  /**
   * Per-client rate limiter for `POST /expand` (`ratelimits`, namespace
   * `"1001"`, 20 per 60 s; REQ-ROUTE-1, REQ-EXPAND-6, REQ-EXPAND-7, D16).
   */
  EXPAND_RATE_LIMITER: RateLimit;
}
