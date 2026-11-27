// Log privacy test for the Worker_Log (REQ-LOG-2, REQ-LOG-3, REQ-WORKERTEST-5).
// Requests go through `handleExpand` with the real `consoleLog` as the `log`
// dependency, and `console.log` is spied on to capture what would be written.
// The Rate_Limiter and Model_Caller are mocks from ./support/mocks; nothing
// reaches a real binding or the network. The token, candidates and IP are
// synthetic test data, not user text.
import { afterEach, beforeEach, describe, expect, it, vi, type MockInstance } from "vitest";
import { handleExpand, type ExpandDeps } from "../src/expand";
import { consoleLog } from "../src/log";
import { MockModelCaller, MockRateLimiter } from "./support/mocks";

const URL_EXPAND = "https://sounder.test/expand";
const TOKEN = "QZXW";
const TEST_IP = "203.0.113.7";
const VALID_BODY = JSON.stringify({ tokens: [TOKEN] });
/** Not a Token_List (extra key), but still carries the token, so it must not leak either. */
const BAD_BODY = JSON.stringify({ tokens: [TOKEN], note: TOKEN });

/** Synthetic one-word candidates, each valid for the single token QZXW. */
const CANDIDATES = ["Qzxwalpha", "Qzxwbravo.", "Qzxwcharlie!"];

const LOG_KEYS = ["candidateCount", "event", "latencyMs", "status", "tokenCount"];

interface Case {
  name: string;
  status: number;
  body: string;
  setup: (limiter: MockRateLimiter, model: MockModelCaller) => void;
}

const cases: Case[] = [
  { name: "200", status: 200, body: VALID_BODY, setup: () => undefined },
  { name: "400", status: 400, body: BAD_BODY, setup: () => undefined },
  {
    name: "429",
    status: 429,
    body: VALID_BODY,
    setup: (limiter) => {
      limiter.limitPerWindow = 0;
    },
  },
  {
    name: "503",
    status: 503,
    body: VALID_BODY,
    setup: (_limiter, model) => {
      model.behaviour = { kind: "reject" };
    },
  },
];

function request(body: string): Request {
  return new Request(URL_EXPAND, {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": TEST_IP },
    body,
  });
}

let logSpy: MockInstance<typeof console.log>;
let errorSpy: MockInstance<typeof console.error>;
let warnSpy: MockInstance<typeof console.warn>;

beforeEach(() => {
  logSpy = vi.spyOn(console, "log").mockImplementation(() => undefined);
  errorSpy = vi.spyOn(console, "error").mockImplementation(() => undefined);
  warnSpy = vi.spyOn(console, "warn").mockImplementation(() => undefined);
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("REQ-LOG-2, REQ-LOG-3, REQ-WORKERTEST-5: Worker_Log privacy", () => {
  for (const c of cases) {
    it(`REQ-LOG-2, REQ-LOG-3, REQ-WORKERTEST-5: a ${c.name} response logs one JSON line of numbers with no token, candidate, body or IP`, async () => {
      const limiter = new MockRateLimiter(20);
      const model = new MockModelCaller({
        kind: "resolve",
        reply: { response: JSON.stringify({ candidates: CANDIDATES }) },
      });
      c.setup(limiter, model);
      let clock = 1000;
      const deps: ExpandDeps = {
        rateLimiter: limiter,
        modelCaller: model.caller,
        now: () => clock++,
        log: consoleLog,
      };

      const response = await handleExpand(request(c.body), deps);
      expect(response.status).toBe(c.status);
      if (c.status === 200) {
        // The 200 case really returned the known candidates, so they were in play.
        expect(await response.json()).toEqual({ candidates: CANDIDATES });
      }

      expect(errorSpy).not.toHaveBeenCalled();
      expect(warnSpy).not.toHaveBeenCalled();
      expect(logSpy).toHaveBeenCalledTimes(1);

      const lines = logSpy.mock.calls.map((args) => args.map(String).join(" "));
      const output = lines.join("\n");
      for (const secret of [TOKEN, ...CANDIDATES, TEST_IP, c.body]) {
        expect(output).not.toContain(secret);
      }
      expect(output.toLowerCase()).not.toContain(TOKEN.toLowerCase());

      for (const line of lines) {
        const entry = JSON.parse(line) as Record<string, unknown>;
        expect(Object.keys(entry).sort()).toEqual(LOG_KEYS);
        expect(entry["event"]).toBe("expand");
        expect(entry["status"]).toBe(c.status);
        expect(typeof entry["latencyMs"]).toBe("number");
        expect(entry["tokenCount"]).toBe(c.status === 200 || c.status === 503 ? 1 : 0);
        expect(entry["candidateCount"]).toBe(c.status === 200 ? CANDIDATES.length : 0);
      }
    });
  }
});
