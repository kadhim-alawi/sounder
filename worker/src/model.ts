/**
 * The Model_Caller and the 5-second model timeout for `POST /expand`
 * (REQ-EXPAND-8, REQ-EXPAND-9, D6).
 *
 * Nothing here logs or keeps the Tokens, the reply or an error object
 * (REQ-LOG-2, REQ-LOG-3). The only I/O is through the injected caller.
 */

import { buildMessages, MAX_TOKENS, MODEL_ID, TEMPERATURE, type ChatMessage } from "./prompt";

/**
 * Calls the Model with [messages] and resolves to its raw reply
 * (REQ-EXPAND-8). Injected into the Expand_Endpoint so tests can pass a mock
 * (REQ-WORKERTEST-2). [signal] is a best-effort cancel (C2, D6).
 */
export type ModelCaller = (messages: ChatMessage[], signal: AbortSignal) => Promise<unknown>;

/**
 * Result of one Model call (REQ-EXPAND-9, REQ-EXPAND-10): the raw reply, a
 * thrown error, or no result within the time limit.
 */
export type ModelOutcome = { kind: "ok"; reply: unknown } | { kind: "error" } | { kind: "timeout" };

/** The slice of the Workers AI binding the Model_Caller uses (C2). */
interface LooseAi {
  run(model: string, inputs: unknown, options: { signal: AbortSignal }): Promise<unknown>;
}

/**
 * Builds the real Model_Caller over the Workers AI binding (REQ-EXPAND-8, C2).
 *
 * Calls `ai.run(MODEL_ID, { messages, temperature, max_tokens }, { signal })`.
 * It sends no `response_format`, because Scout is not in the JSON Mode list,
 * and no `tags`, so no user text reaches dashboard metadata.
 */
export function workersAiModelCaller(ai: Ai): ModelCaller {
  // The model union and a loose inputs object do not match one overload, so
  // cast at this boundary (kept from the spike).
  const loose = ai as unknown as LooseAi;
  return (messages, signal) =>
    loose.run(
      MODEL_ID,
      { messages, temperature: TEMPERATURE, max_tokens: MAX_TOKENS },
      { signal },
    );
}

/**
 * Makes one Model call for [tokens] and races it against a [timeoutMs] timer
 * (REQ-EXPAND-9, D6).
 *
 * If the timer fires first, aborts the call's AbortController (best effort,
 * C2) and resolves to `{ kind: "timeout" }`; a later result is ignored. If
 * the call settles first, the timer is cleared and the outcome is
 * `{ kind: "ok", reply }` on success or `{ kind: "error" }` on a throw. The
 * error object is neither kept nor logged (REQ-LOG-2).
 */
export function callModelWithTimeout(
  caller: ModelCaller,
  tokens: string[],
  timeoutMs: number,
): Promise<ModelOutcome> {
  const controller = new AbortController();
  const messages = buildMessages(tokens);

  return new Promise<ModelOutcome>((resolve) => {
    let settled = false;

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      controller.abort();
      resolve({ kind: "timeout" });
    }, timeoutMs);

    const finish = (outcome: ModelOutcome): void => {
      clearTimeout(timer);
      if (settled) return;
      settled = true;
      resolve(outcome);
    };

    // The async wrapper turns a synchronous throw into a rejection.
    (async () => caller(messages, controller.signal))().then(
      (reply) => finish({ kind: "ok", reply }),
      () => finish({ kind: "error" }),
    );
  });
}
