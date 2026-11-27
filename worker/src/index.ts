/**
 * Fetch entry point of the Sounder Worker (REQ-ROUTE-1, REQ-ROUTE-5, design
 * D1, D2).
 *
 * `run_worker_first: ["/expand"]` in `wrangler.jsonc` sends `/expand` here
 * before asset serving. Other paths reach this script only when they match no
 * asset and are not navigation requests (C1); they are passed to the ASSETS
 * binding unchanged, which applies the same single-page-application fallback.
 */

import type { Env } from "./env";
import { handleExpand } from "./expand";
import { consoleLog } from "./log";
import { workersAiModelCaller } from "./model";

/**
 * The Worker's exported handler (REQ-ROUTE-1, REQ-ROUTE-5): `/expand` goes to
 * `handleExpand` with real dependencies built from `env` (D2); every other
 * request goes to `env.ASSETS.fetch` unchanged (E15).
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/expand") {
      return handleExpand(request, {
        rateLimiter: env.EXPAND_RATE_LIMITER,
        modelCaller: workersAiModelCaller(env.AI),
        now: () => Date.now(),
        log: consoleLog,
      });
    }
    return env.ASSETS.fetch(request); // REQ-ROUTE-5, E15: unchanged in, unchanged out
  },
} satisfies ExportedHandler<Env>;
