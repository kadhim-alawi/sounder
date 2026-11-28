# Expansion latency (REQ-LATENCY-1)

**REQ-LATENCY-1: NOT MET (3,881 ms ≥ 3,000 ms)**

Status: recorded as a failed measurement, by the user's decision. This is one run. Task 13.2 stays open until the user re-runs the measurement or decides what to do about the budget. No code, requirement or budget was changed because of this result.

## Method

- Date: 2026-11-28.
- Site: https://sounder.kadhim-alawi.workers.dev/ (the hosted Worker `sounder`).
- Browser: Firefox 159.0, developer tools console.
- Connection: broadband (not further specified by the user).
- Run by: the user. The agent sent no requests.
- Script: `eval/expansion_latency.js`, pasted into the console on the hosted page.
- Requests: the six spike-3 Token_Lists (L1 to L6) in turn, four rounds, 24 `POST /expand` requests in total. Sends start at least 3.5 s apart, so the Worker's limit of 20 requests per 60 s is never reached.
- Timing: `performance.now()` from just before `fetch()` to the parsed JSON reply, rounded to whole ms.
- One frame (17 ms) is added to the reported median for showing the result (design L5).
- Recorded: request number, Token_List id, HTTP status, duration and candidate count. No candidate text, reply bodies or error messages were printed or recorded.

## Raw results

| Request | List | Status | ms | Candidates |
|---:|:---:|:---:|---:|:---:|
| 1 | L1 | 200 | 2063 | 3 |
| 2 | L2 | 200 | 3494 | 4 |
| 3 | L3 | 200 | 3710 | 3 |
| 4 | L4 | 200 | 2438 | 2 |
| 5 | L5 | 200 | 1651 | 1 |
| 6 | L6 | 200 | 1175 | 3 |
| 7 | L1 | 200 | 3196 | 3 |
| 8 | L2 | 200 | 4017 | 4 |
| 9 | L3 | 200 | 3391 | 3 |
| 10 | L4 | 503 | 5226 | - |
| 11 | L5 | 200 | 4709 | 1 |
| 12 | L6 | 200 | 3460 | 3 |
| 13 | L1 | 200 | 3284 | 2 |
| 14 | L2 | 200 | 4126 | 4 |
| 15 | L3 | 200 | 5109 | 4 |
| 16 | L4 | 503 | 5207 | - |
| 17 | L5 | 200 | 5056 | 1 |
| 18 | L6 | 200 | 5233 | 3 |
| 19 | L1 | 503 | 5121 | - |
| 20 | L2 | 200 | 4486 | 4 |
| 21 | L3 | 200 | 4332 | 3 |
| 22 | L4 | 200 | 4581 | 2 |
| 23 | L5 | 503 | 5145 | - |
| 24 | L6 | 200 | 4900 | 3 |

Raw ms, all requests in order: 2063, 3494, 3710, 2438, 1651, 1175, 3196, 4017, 3391, 5226, 4709, 3460, 3284, 4126, 5109, 5207, 5056, 5233, 5121, 4486, 4332, 4581, 5145, 4900.

Statuses: `{"200":20,"503":4}`. No aborts or network errors.

Network panel durations for the 503 replies, as read by the user: request 10 5156 ms (HTTP/3 503), request 16 5063 ms, request 19 5084 ms, request 23 5084 ms. The console durations are 37 to 144 ms longer because they also include reading and parsing the reply.

## Medians

Recomputed from the raw numbers above. They agree with the snippet's printed summary; the snippet rounds half up.

| Measure | Exact | Snippet printed |
|---|---:|---:|
| Median, 200 replies only (20) | 3863.5 ms | 3864 ms |
| Median, 200 only, + one frame | 3880.5 ms | 3881 ms |
| Median, all 24 requests | 4229 ms | not printed |
| Median, all 24 requests, + one frame | 4246 ms | 4246 ms |

Budget: under 3,000 ms. Both medians are over it. REQ-LATENCY-1 times every request until the Candidate_List or the Failure_Message is shown, so the all-requests figure (4,246 ms) also applies, and it is further over budget.

## Observations

- **503 replies at the server model timeout.** All four 503 replies took 5,121 to 5,226 ms in the console (5,063 to 5,156 ms in the network panel). That matches the Worker's 5 s server model timeout (REQ-EXPAND-9) plus transfer time. The app would show the Failure_Message for these, within the 6 s client timeout. The 503 replies were for L4 twice, L1 once and L5 once. None came in the first 9 requests.
- **Latency rose during the run.**

  | Requests | Median (all statuses) | Median (200 only) |
  |---|---:|---:|
  | 1 to 6 (round 1) | 2250.5 ms | 2250.5 ms |
  | 7 to 12 (round 2) | 3738.5 ms | 3460 ms |
  | 13 to 18 (round 3) | 5082.5 ms | 5056 ms |
  | 19 to 24 (round 4) | 4740.5 ms | 4533.5 ms |

  The first 6 requests had a median of 2,250.5 ms, under budget. The last 6 had a median of 4,740.5 ms. This one run cannot tell whether the rise came from the model service, the connection or the request rate.
- **Candidate counts per list** (200 replies only): L1 3, 3, 2; L2 4, 4, 4, 4; L3 3, 3, 4, 3; L4 2, 2; L5 1, 1, 1; L6 3, 3, 3, 3. Every 200 reply had at least one candidate.

## Limits

- One run, one browser, one connection that was not further described.
- The snippet measures send to parsed reply. The frame that shows the result is added as a fixed 17 ms (design L5), not measured.
