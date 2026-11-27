/**
 * Worker_Log: the single log line written for each `/expand` request
 * (REQ-LOG-2, REQ-LOG-3).
 *
 * This is the only Worker file allowed to call `console`. The line holds four
 * numbers and nothing else: no Token, Candidate, request body, Model reply
 * text, header value or IP address ever reaches it.
 */

/**
 * The four numbers logged for one `/expand` request (REQ-LOG-2): the response
 * status, the latency in milliseconds, the Token count (0 when the body was
 * not read or was not a valid Token_List) and the Candidate count (0 for
 * non-200 responses).
 */
export interface ExpandLogEntry {
  status: number;
  latencyMs: number;
  tokenCount: number;
  candidateCount: number;
}

/**
 * Writes one JSON line with `event: "expand"` and exactly the four numbers of
 * [e] (REQ-LOG-2). The object is built from the four named fields only, never
 * by spreading [e], so extra properties on the argument cannot reach the log
 * (REQ-LOG-3).
 */
export const consoleLog = (e: ExpandLogEntry): void => {
  console.log(
    JSON.stringify({
      event: "expand",
      status: e.status,
      latencyMs: e.latencyMs,
      tokenCount: e.tokenCount,
      candidateCount: e.candidateCount,
    }),
  );
};
