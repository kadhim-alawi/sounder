# Implementation Plan: shorthand-expansion

## Overview

The work follows the two parts of the requirements, with the checkpoint between them.

- **Part A (tasks 1 to 7)** builds the Cloudflare Worker in TypeScript: the project in `worker/`, the TS_Validator and the shared Validator_Fixture, the Reply_Processor, request parsing, the Model_Caller, the log line, `handleExpand`, the entry point, `wrangler.jsonc`, the "Worker tests" CI step and the steering updates. Every Part A task is required, including every fast-check property test and example test, because the Worker tests gate every deploy.
- **Task 8** is the REQ-CHECKPOINT-1 checkpoint. No Part B task starts until it is done and recorded in `.kiro/evidence/`.
- **Part B (tasks 9 to 14)** builds the Flutter client in Dart: the Dart_Validator, Sentence_Tokens and narrowing (pure, in `lib/compose/`), the Expansion_Client and its HTTP transport, the notice store, the new key actions, the controller and widgets, the latency measurement in `eval/`, and the final checkpoint. The fixture test and every kiri_check property test are required. Only widget tests are optional.

Conventions for every task:

- Never guess an API or a package version. For Dart, use the dart MCP server: first register `app/` and `packages/morse_core` as roots with its `roots` tool, then use `pub_dev_search`, `pub`, `analyze_files` and the test tools. If a dart MCP tool cannot be used, run the command in the shell and say so. For npm, check versions with `npm view` and the Cloudflare docs cited in the design.
- New code goes in the folder that owns it: `worker/src/`, `worker/test/`, `fixtures/`, `app/lib/compose/`, `app/lib/net/`, `app/lib/store/`, `app/lib/input/`, `app/lib/ui/`, `app/lib/speech/`, `eval/`. One widget per file in `app/lib/ui/`.
- Every public declaration has a doc comment citing at least one requirement ID. Every test description begins with its requirement ID or IDs and a colon, for example `REQ-VALIDATOR-5: generated-valid candidates are accepted` (REQ-WORKERTEST-6, REQ-APPTEST-5).
- Mocks and fakes live only under `worker/test/` and `app/test/`, and their names begin with `Mock` (REQ-WORKERTEST-2, REQ-APPTEST-4). No test calls the real AI_Binding or the network.
- Nothing logs a Token, a Candidate, a Sentence, a request body, a Model reply, a header value or an IP address (REQ-LOG-2, REQ-LOG-3, REQ-FAIL-4). In the Worker only `log.ts` calls `console`.
- Property tests use the seeds and run counts in the design's table: fast-check seed `(600 + N) * 1000 + 7`, kiri_check seed `(600 + N) * 1000 + 3`, 200 runs, the tag comment `// Feature: shorthand-expansion, Property N: <title>`, and generators that meet preconditions by construction (no `fc.pre`, no `.filter`, no kiri_check filters).
- A task is done only when its cited tests pass: `cd worker && npm test`, `cd app && flutter test`, and `cd packages/morse_core && dart test` still passes.

## Tasks

### Part A: the `/expand` endpoint

- [x] 1. Set up the Worker project in `worker/`
  - Create `worker/package.json` (name `sounder-worker`, private, `"type": "module"`, script `"test": "tsc --noEmit && vitest run"`) with dev dependencies only: `@cloudflare/workers-types` 5.20261127.1, `fast-check` 4.11.0, `typescript` 7.0.2, `vitest` 5.1.2. Confirm each version with `npm view` before pinning
  - Create `worker/tsconfig.json` (`strict`, `noEmit`, `target`/`lib` `ES2022`, `module` `ESNext`, `moduleResolution` `Bundler`, `resolveJsonModule`, `types: ["@cloudflare/workers-types"]`, `include: ["src", "test"]`) and `worker/vitest.config.ts` (`test.include: ["test/**/*.test.ts"]`, `server.fs.allow: [".."]`)
  - Run `npm install` in `worker/` to create `package-lock.json`
  - Risk check (design, `tsconfig.json` note): add a placeholder `worker/src/env.ts` declaring the `Env` interface (`ASSETS: Fetcher`, `AI: Ai`, `EXPAND_RATE_LIMITER: RateLimit`) and run `npx tsc --noEmit`. If TypeScript 7.0.2 fails to type-check `@cloudflare/workers-types`, pin the newest 5.x TypeScript release instead (read it with `npm view typescript versions`), re-run `npm install`, and record the error and the chosen version in `.kiro/evidence/LOG.md`
  - Confirm `npm test` runs once and exits (no watch mode) with a trivial passing test, then delete that test
  - _Requirements: REQ-WORKERTEST-1_

- [x] 2. Implement the TS_Validator and the shared Validator_Fixture
  - [x] 2.1 Implement the TS_Validator
    - `worker/src/validator.ts`: `MAX_CANDIDATE_LENGTH = 200`, `isE2Space`, `isStripChar`, `isAsciiLetter`, `asciiLower`, `splitWords`, `stripWord`, `isWellFormedWord`, `isValidCandidate(tokens, candidate)` exactly as the design's algorithm (E1 to E5)
    - Works on UTF-16 code units; no regex with Unicode classes, no `toLowerCase`, no I/O, clock or logging
    - Returns false when `tokens` is outside the Token_List domain
    - _Requirements: REQ-VALIDATOR-1, REQ-VALIDATOR-4_
  - [x] 2.2 Create the Validator_Fixture
    - `fixtures/expansion_validator.json` in the design's format (`version: 1`, `cases` with `id`, `tags`, `tokens`, `candidate`, `valid`), plain ASCII with `\uXXXX` escapes for non-ASCII characters, unique ids
    - At least one case for every required tag in the design's tag table: `a-valid`, `a-invalid`, `len-200`, `len-201`, `b-valid`, `b-invalid`, `c-valid`, `c-invalid`, `d-valid`, `d-invalid`, each `strip-` character, `apos-ascii`, `apos-curly`, `hyphen`, `lead-apos`, `trail-apos`, `lead-hyphen`, `trail-hyphen`, `non-ascii-letter`, `unicode-space`, `token-longer-than-word`
    - Candidates are synthetic test strings, not user text
    - _Requirements: REQ-VALIDATOR-3_
  - [x] 2.3 Write the TS fixture test and the fixture coverage test
    - `worker/test/validator.test.ts`: import `../../fixtures/expansion_validator.json`; one assertion per case, `isValidCandidate(tokens, candidate) === valid`, failure message names the case id
    - `worker/test/fixture_coverage.test.ts`: check the schema shape from the design (required keys, no extra keys, `version` 1, token pattern and list length), unique ids, and that every required tag has at least one case
    - _Requirements: REQ-VALIDATOR-2, REQ-VALIDATOR-3, REQ-WORKERTEST-4_
  - [x] 2.4 Write the candidate generators and the property test for generated-valid candidates
    - `worker/test/support/arbitraries.ts`: `tokenArb` (1 to 8 ASCII letters), `tokenListArb` (1 to 12), `validCandidateArb(tokens)` with any letter case, 0 to 2 extra letters, 0 to 2 strip characters at each end, separators of 1 to 2 E2 whitespace characters and optional leading and trailing E2 whitespace, kept at or under 200 characters by the fixed caps in the design
    - Add to `worker/test/validator.test.ts` with fast-check, seed `601007`, `numRuns: 200`
    - **Property 1: Generated-valid candidates are accepted**
    - **Validates: Requirements 1.5, 1.1** (REQ-VALIDATOR-5, REQ-VALIDATOR-1, REQ-WORKERTEST-3)
  - [x] 2.5 Write the property test for a changed first letter
    - Add the first-letter mutation generator to `arbitraries.ts` (different letter is `(first + 1 + k) mod 26`, k in 0..24, position i by modulo); add the test to `validator.test.ts`, seed `602007`
    - **Property 2: Changing a first letter makes a candidate invalid**
    - **Validates: Requirements 1.6, 1.1** (REQ-VALIDATOR-6, REQ-VALIDATOR-1, REQ-WORKERTEST-3)
  - [x] 2.6 Write the property test for a different word count
    - Add the add-words and remove-words mutation generators to `arbitraries.ts` (remove at least 1 and at most all Words, or add 1 or more Words at any positions); add the test to `validator.test.ts`, seed `603007`
    - **Property 3: A different word count makes a candidate invalid**
    - **Validates: Requirements 1.7, 1.1** (REQ-VALIDATOR-7, REQ-VALIDATOR-1, REQ-WORKERTEST-3)

- [x] 3. Implement the Reply_Processor
  - [x] 3.1 Implement `reply.ts`
    - `worker/src/reply.ts`: `extractCandidatesArray` (E8: `response` as object or string, first `{` to last `}`, `JSON.parse` in `try`), `shouldSentenceCase`, `sentenceCase` (E6, length unchanged, `I`/`I'`/`I’` keep the capital), `duplicateKey` (E7), `processReply` running the steps in the order of REQ-REPLY-1 to REQ-REPLY-4, with the defensive `try` from the design's error table returning `[]`
    - Pure; no logging
    - _Requirements: REQ-REPLY-1, REQ-REPLY-2, REQ-REPLY-3, REQ-REPLY-4_
  - [x] 3.2 Write the Reply_Processor example tests
    - `worker/test/reply.test.ts`: `response` as string and as object; text around the JSON; no braces; `last < first`; `candidates` missing or not an array; non-string items dropped; trimming; `I Want Some Water Please` becomes `I want some water please`; `I'm` and `I’m` keep the capital; a single word is not converted; duplicates by case and by trailing `!`; more than 4 valid candidates keeps the first 4 in model order
    - _Requirements: REQ-REPLY-1, REQ-REPLY-2, REQ-REPLY-3, REQ-REPLY-4_
  - [x] 3.3 Write the property test for sentence-case validity
    - Add a mixed-string generator to `arbitraries.ts` (Property 1 candidates, the same with every Word capitalised, and arbitrary strings of ASCII letters, strip characters, apostrophes, hyphens, digits, E2 and non-E2 spaces and non-ASCII letters); add the test to `reply.test.ts`, seed `604007`
    - **Property 4: Sentence-case conversion preserves validity**
    - **Validates: Requirements 4.5, 4.3** (REQ-REPLY-5, REQ-REPLY-3, REQ-WORKERTEST-3)
  - [x] 3.4 Write the property test for the Reply_Processor output
    - Add a model-reply generator to `arbitraries.ts` (non-objects, `{response: s}` for arbitrary text, noise + JSON object + noise, `{response: o}`, `candidates` with 0 to 12 items mixing valid and invalid strings, case and trailing `.!?` near-duplicates, numbers, nulls and objects); add the test to `reply.test.ts`, seed `605007`
    - Assert at most 4 items, each accepted by the TS_Validator, distinct `duplicateKey`s, and in the same relative order as the trimmed, sentence-cased string items
    - **Property 5: Reply processing output is small, valid, distinct and in model order**
    - **Validates: Requirements 4.6, 4.4, 4.1, 4.2** (REQ-REPLY-6, REQ-REPLY-4, REQ-REPLY-1, REQ-REPLY-2, REQ-WORKERTEST-3)

- [x] 4. Checkpoint - Ensure all Worker tests pass
  - Run `cd worker && npm test`.
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement request handling, the Model_Caller, logging and `handleExpand`
  - [x] 5.1 Implement request parsing
    - `worker/src/request.ts`: `readBodyLimited(request, 1024)` (D7: `Content-Length` over 1,024 returns `"too_large"` unread; otherwise count bytes chunk by chunk and cancel the reader on the first byte past 1,024); `parseTokenRequest(bytes)` (fatal UTF-8 decode, `JSON.parse`, non-null non-array object, keys exactly `["tokens"]`, 1 to 12 strings matching `^[A-Za-z]{1,8}$`, else `null`)
    - _Requirements: REQ-EXPAND-3, REQ-EXPAND-4_
  - [x] 5.2 Write the request parsing example tests
    - `worker/test/request.test.ts`: 1,024 bytes accepted; 1,025 bytes rejected; a large `Content-Length` rejected unread; a body larger than its `Content-Length` claims rejected; invalid UTF-8, extra key, empty list, 13 items, 9-letter item, `é` in an item, top-level array return `null`
    - _Requirements: REQ-EXPAND-3, REQ-EXPAND-4_
  - [x] 5.3 Write the property test for request body parsing
    - Add the valid-body and one-mutation generators to `arbitraries.ts` (13 to 20 items and 9 to 12 letters generated directly); add the test to `request.test.ts`, seed `606007`
    - **Property 6: Request body parsing accepts exactly the Token_List shape**
    - **Validates: Requirements 3.4** (REQ-EXPAND-4)
  - [x] 5.4 Implement the prompt and the Model_Caller
    - `worker/src/prompt.ts`: `MODEL_ID = "@cf/meta/llama-4-scout-17b-16e-instruct"`, `TEMPERATURE = 0.2`, `MAX_TOKENS = 200`, `SYSTEM_PROMPT` as in the design, `buildMessages(tokens)` (system message, then the Tokens joined by single spaces)
    - `worker/src/model.ts`: `ModelCaller` type, `workersAiModelCaller(ai)` calling `ai.run(MODEL_ID, { messages, temperature, max_tokens }, { signal })` with no `response_format` and no `tags`; `callModelWithTimeout(caller, tokens, 5000)` racing the call against a `setTimeout` (D6), aborting the controller when the timer wins, clearing the timer when the model wins, mapping a throw to `{ kind: "error" }` without keeping the error object
    - _Requirements: REQ-EXPAND-8, REQ-EXPAND-9_
  - [x] 5.5 Implement the log line
    - `worker/src/log.ts`: `ExpandLogEntry` with `status`, `latencyMs`, `tokenCount`, `candidateCount`; `consoleLog` writes one JSON line with `event: "expand"` and exactly those four numbers
    - _Requirements: REQ-LOG-2, REQ-LOG-3_
  - [x] 5.6 Implement `handleExpand` and the test mocks
    - `worker/src/expand.ts`: `RateLimiter`, `ExpandDeps`, `jsonResponse(status, body, extraHeaders?)` (always `Content-Type: application/json` and `Cache-Control: no-store`, never `Access-Control-Allow-Origin`), and `handleExpand` running the E9 order: 405 with `Allow: POST` and no limiter call; one `limit({ key })` call with `CF-Connecting-IP` or `unknown`, before the body is read, a throw treated as allowed (D5); 429; 415 by media type (E10); 413; 400 (stream read error also 400); model call; 503 or 200 with `processReply` output. Each return logs one entry with the counts from the design's error table
    - `worker/test/support/mocks.ts`: `MockRateLimiter` (counts calls, configurable limit per window, can throw), `MockModelCaller` (records messages and signal, resolves, rejects or never resolves), `MockAi` (records `run` arguments)
    - No storage, cache or binding writes other than the limiter key
    - _Requirements: REQ-EXPAND-1, REQ-EXPAND-2, REQ-EXPAND-3, REQ-EXPAND-4, REQ-EXPAND-5, REQ-EXPAND-6, REQ-EXPAND-7, REQ-EXPAND-8, REQ-EXPAND-9, REQ-EXPAND-10, REQ-EXPAND-11, REQ-LOG-1, REQ-LOG-2, REQ-WORKERTEST-2_
  - [x] 5.7 Write the `handleExpand` example tests
    - `worker/test/expand.test.ts` with `MockRateLimiter`, `MockModelCaller` and a captured log
    - 200 with candidates and 200 with an empty list; 405 with `Allow: POST` and no limiter call; 415 for a missing header and `text/plain`, with `application/json; charset=utf-8` and `Application/JSON` accepted; 413 cases; 400 cases
    - Check order: an over-limit request with an invalid body returns 429 and its body stream is not read; requests rejected with 415, 413 and 400 still count, so the 21st request in a window returns 429
    - Key from `CF-Connecting-IP`, and `unknown` when missing
    - Model input: system prompt clauses (one word per item, in order; exactly 4 candidates as `{"candidates":[...]}`; everyday first-person language), user message `I W S W P`, temperature 0.2, max_tokens 200; `workersAiModelCaller(MockAi)` passes the model id and options
    - 503 on a model error, and on a never-resolving model with `vi.useFakeTimers()` and `vi.advanceTimersByTimeAsync(5000)`, with the signal aborted
    - Headers and exact error bodies on every status
    - _Requirements: REQ-EXPAND-1 to REQ-EXPAND-11, REQ-WORKERTEST-2, REQ-WORKERTEST-4_
  - [x] 5.8 Write the log privacy test
    - `worker/test/log.test.ts`: spy on `console.log` during 200, 400, 429 and 503 requests carrying the Token `QZXW`, known candidate strings and `CF-Connecting-IP: 203.0.113.7`; assert none of those strings appear in the joined output and each entry has exactly the keys `event`, `status`, `latencyMs`, `tokenCount`, `candidateCount`
    - _Requirements: REQ-LOG-2, REQ-LOG-3, REQ-WORKERTEST-5_

- [x] 6. Wire the Worker entry point, configuration and CI
  - [x] 6.1 Implement the entry point and update `wrangler.jsonc`
    - Finish `worker/src/env.ts`; write `worker/src/index.ts` as in the design: `/expand` goes to `handleExpand` with real deps from `env`; every other path goes to `env.ASSETS.fetch(request)` unchanged
    - Update the root `wrangler.jsonc` to the design's version: keep `name`, `compatibility_date`, `assets.directory`, `assets.not_found_handling`; add `main: "./worker/src/index.ts"`, `assets.binding: "ASSETS"`, `assets.run_worker_first: ["/expand"]`, `ai.binding: "AI"`, and one `ratelimits` entry `EXPAND_RATE_LIMITER` with `namespace_id: "1001"`, `simple.limit` 20, `simple.period` 60. Add no `observability` block
    - Check field names against the Cloudflare pages cited in the design before editing
    - _Requirements: REQ-ROUTE-1, REQ-ROUTE-5_
  - [x] 6.2 Write the routing pass-through test
    - `worker/test/index.test.ts`: add `MockAssets` to `support/mocks.ts`; `GET /main.dart.js` and `POST /other` reach `MockAssets.fetch` with the same `Request` object and its `Response` is returned unchanged
    - _Requirements: REQ-ROUTE-5_
  - [x] 6.3 Add the "Worker tests" step to the Deploy_Workflow
    - In `.github/workflows/deploy.yml`, insert after `actions/checkout@v4` and before the Flutter setup: `actions/setup-node@v7` (Node 22, npm cache on `worker/package-lock.json`) and a step named `Worker tests` with `working-directory: worker` running `npm ci` then `npm test`
    - Leave "Engine tests", "App tests", "Build web app" and "Deploy to Cloudflare" unchanged, including `wranglerVersion`; add no `continue-on-error`
    - _Requirements: REQ-PIPE-1, REQ-PIPE-2, REQ-PIPE-3_
  - [x] 6.4 Write the configuration and source smoke tests
    - `worker/test/config.test.ts`: parse `../wrangler.jsonc` with comments stripped and check every REQ-ROUTE-1 field; read `../.github/workflows/deploy.yml` as text and check the "Worker tests" step has `working-directory: worker`, runs `npm ci` then `npm test`, comes before "Build web app", and no `continue-on-error` appears; scan `worker/src/` for no use of `caches`, KV, D1 or R2 and no `console` outside `log.ts`; check that every `describe`/`it`/`test` description in `worker/test/` starts with REQ IDs and a colon
    - _Requirements: REQ-ROUTE-1, REQ-PIPE-1, REQ-PIPE-3, REQ-LOG-1, REQ-LOG-3, REQ-VALIDATOR-4, REQ-WORKERTEST-6_

- [x] 7. Update the steering files
  - [x] 7.1 Update `.kiro/steering/tech.md`
    - Backend: one Cloudflare Worker, `sounder`, code in `worker/`, serving the web build and `POST /expand` with Workers AI (`@cf/meta/llama-4-scout-17b-16e-instruct`), config in the root `wrangler.jsonc`
    - Layering: replace the "function holds the model API key" line with the Worker line from the design
    - Testing: add `cd worker && npm test`
    - Performance budgets: median under 3 s on a normal connection, client timeout 6 s, server model timeout 5 s, Failure_Message `No suggestions. Add letters or speak what you typed.` on failure
    - _Requirements: REQ-STEER-1, REQ-STEER-3_
  - [x] 7.2 Update `.kiro/steering/structure.md`
    - Remove `functions/expand/`; add `worker/`, `fixtures/` and `spikes/` with one line each as in the design; change the `eval/` entry to the exact text of REQ-STEER-2; add `lib/net/` under `app/` (D9)
    - _Requirements: REQ-STEER-2, REQ-STEER-3_

- [x] 8. Checkpoint - Part A is tested, deployed and recorded (REQ-CHECKPOINT-1)
  - Run `cd worker && npm test`, `cd packages/morse_core && dart test` and `cd app && flutter test`; record the pass counts.
  - Ask the user before committing and pushing the Part A commit; then record the GitHub Actions run URL and its result.
  - On the hosted Worker, check that `GET https://sounder.kadhim-alawi.workers.dev/` loads the app and a navigation to `/no-such-page` loads the app with status 200 (REQ-ROUTE-3, REQ-ROUTE-4).
  - Send one manual `POST /expand` with `{"tokens":["I","W","S","W","P"]}` (for example with `fetch` from the browser console); record the status (200), the candidate count and whether every candidate passes the validator. Do not copy candidate text into the evidence.
  - Write the results to `.kiro/evidence/shorthand-expansion-checkpoint.md`, one line per check, and append a summary line to `.kiro/evidence/LOG.md`.
  - Ensure all tests pass, ask the user if questions arise. Do not start task 9 until every check passes.
  - _Requirements: REQ-CHECKPOINT-1, REQ-ROUTE-3, REQ-ROUTE-4_

### Part B: the client

- [x] 9. Implement the pure Dart expansion rules in `app/lib/compose/`
  - [x] 9.1 Add the app dependencies
    - Register `app/` and `packages/morse_core` as dart MCP roots; confirm `http` and `shared_preferences` versions and web support with `pub_dev_search`; add `http: ^1.6.0` and `shared_preferences: ^2.5.6` to `app/pubspec.yaml` with the dart MCP `pub` tool (or `flutter pub add` in the shell, saying so)
    - _Requirements: REQ-WAIT-3, REQ-NOTICE-2_
  - [x] 9.2 Implement the Dart_Validator
    - `app/lib/compose/initials_validator.dart`: `maxCandidateLength`, `isE2Space`, `isStripChar`, `isAsciiLetter`, `asciiLower` (maps only 0x41..0x5A), `splitWords`, `stripWord`, `isWellFormedWord`, `isValidCandidate(tokens, candidate)`, the same algorithm as the TS_Validator over `codeUnitAt`; no `toLowerCase`, no regex Unicode classes
    - Pure Dart under the existing REQ-COMPOSE-1 source rule (D8)
    - _Requirements: REQ-VALIDATOR-1, REQ-VALIDATOR-4_
  - [x] 9.3 Write the Dart fixture test (required)
    - `app/test/initials_validator_fixture_test.dart`: read `File('../fixtures/expansion_validator.json')`, check the schema shape, and assert each case's expected result, naming the case id on failure
    - _Requirements: REQ-VALIDATOR-2, REQ-APPTEST-1_
  - [x] 9.4 Write the Dart candidate generators and the property test for generated-valid candidates (required)
    - `app/test/support/expansion_arbitraries.dart`: Token, Token_List and valid-candidate generators matching the fast-check ones (check kiri_check combinators with the dart MCP server before use)
    - Create `app/test/expansion_properties_test.dart`, seed `601003`, `maxExamples: 200`
    - **Property 1: Generated-valid candidates are accepted**
    - **Validates: Requirements 1.5, 1.1** (REQ-VALIDATOR-5, REQ-VALIDATOR-1, REQ-APPTEST-2)
  - [x] 9.5 Write the Dart property test for a changed first letter (required)
    - Add the mutation generator to `expansion_arbitraries.dart`; add the test to `expansion_properties_test.dart`, seed `602003`
    - **Property 2: Changing a first letter makes a candidate invalid**
    - **Validates: Requirements 1.6, 1.1** (REQ-VALIDATOR-6, REQ-VALIDATOR-1, REQ-APPTEST-2)
  - [x] 9.6 Write the Dart property test for a different word count (required)
    - Add the add-words and remove-words generators to `expansion_arbitraries.dart`; add the test to `expansion_properties_test.dart`, seed `603003`
    - **Property 3: A different word count makes a candidate invalid**
    - **Validates: Requirements 1.7, 1.1** (REQ-VALIDATOR-7, REQ-VALIDATOR-1, REQ-APPTEST-2)
  - [x] 9.7 Implement Sentence_Tokens
    - `app/lib/compose/sentence_tokens.dart`: `TokensCheck` (`TokensEmpty`, `TokensBlocked` with `TokensBlock.nonLetter`, `tooManyWords`, `wordTooLong` checked in that order, `TokensReady`), `sentenceTokens(items)` with words as maximal runs of non-Word_Space items (E16), and `tokensMessageFor(check)` returning the three exact messages
    - _Requirements: REQ-TOKENS-1, REQ-TOKENS-2, REQ-TOKENS-3_
  - [x] 9.8 Write the property test for Sentence_Tokens (required)
    - Add a Sentence generator to `expansion_arbitraries.dart` (0 to 14 words of 1 to 10 items, mostly ASCII Letter_Items, sometimes an Unknown_Letter_Item, digit or punctuation Letter_Item, 1 or more Word_Spaces between words, optional at the ends), reusing `item_arbitraries.dart` patterns; add the test to `expansion_properties_test.dart`, seed `607003`
    - **Property 7: Sentence_Tokens follow the words of the Sentence**
    - **Validates: Requirements 10.1, 10.2, 10.3** (REQ-TOKENS-1, REQ-TOKENS-2, REQ-TOKENS-3)
  - [x] 9.9 Implement narrowing
    - `app/lib/compose/narrowing.dart`: `narrowCandidates(candidates, check)` returns `[]` unless `TokensReady`, else the in-order sublist the Dart_Validator accepts
    - _Requirements: REQ-NARROW-1_
  - [x] 9.10 Write the property test for narrowing keeps exactly the valid candidates (required)
    - Add a Candidate_List generator (0 to 6 strings mixing valid candidates and arbitrary strings) and a TokensCheck generator to `expansion_arbitraries.dart`; add the test to `expansion_properties_test.dart`, seed `608003`
    - **Property 8: Narrowing keeps exactly the valid candidates, in order**
    - **Validates: Requirements 14.3, 14.1** (REQ-NARROW-3, REQ-NARROW-1, REQ-APPTEST-2)
  - [x] 9.11 Write the property test for adding letters only narrows (required)
    - Add the T to T′ generator (append letters to 1 or more Tokens, each at most 8 letters, built by construction) to `expansion_arbitraries.dart`; candidates mostly valid for T′; add the test to `expansion_properties_test.dart`, seed `609003`
    - **Property 9: Adding letters to tokens only narrows**
    - **Validates: Requirements 14.4** (REQ-NARROW-4, REQ-APPTEST-2)
  - [x] 9.12 Write the property test for narrowing idempotence (required)
    - Add the test to `expansion_properties_test.dart`, seed `610003`
    - **Property 10: Narrowing is idempotent**
    - **Validates: Requirements 14.5** (REQ-NARROW-5, REQ-APPTEST-2)

- [x] 10. Implement the Expansion_Client, transport, notice store and key actions
  - [x] 10.1 Implement the Expansion_Client
    - `app/lib/compose/expansion_client.dart`: `Delay`, `TransportResponse`, `ExpansionTransport`, `ExpansionResult` (`ExpansionReply`, `ExpansionFailure` with `timeout`, `network`, `status`, `unreadable`), `ExpansionClient`, `TransportExpansionClient` (`jsonEncode({'tokens': tokens})`, `Future.any` of the transport and `delay(6 s)`, any throw is `network`, non-200 is `status`, bad JSON or no `candidates` list is `unreadable`, else the string items in order)
    - No `Timer`, clock, Flutter or I/O imports (REQ-COMPOSE-1 source rule); no validation; no logging; no state
    - _Requirements: REQ-WAIT-3, REQ-WAIT-5, REQ-FAIL-1, REQ-FAIL-4_
  - [x] 10.2 Write the Expansion_Client unit tests
    - `app/test/expansion_client_test.dart` with `MockExpansionTransport` and `MockDelay` (a `Delay` whose futures the test completes): body is `{"tokens":[...]}` for the Sentence_Tokens; 200 reply keeps string items in order; non-200, unreadable, thrown error and timeout results; a late reply after the timeout does not change the result
    - _Requirements: REQ-WAIT-3, REQ-WAIT-5, REQ-FAIL-1, REQ-APPTEST-4_
  - [x] 10.3 Implement the HTTP transport
    - `app/lib/net/http_expansion_transport.dart`: `HttpExpansionTransport(http.Client)` posting to `Uri.base.resolve('/expand')` with `Content-Type: application/json`, returning `TransportResponse(statusCode, utf8.decode(bodyBytes, allowMalformed: true))`; check the `http` API with the dart MCP server
    - _Requirements: REQ-WAIT-3, REQ-FAIL-4_
  - [x] 10.4 Implement the notice store
    - `app/lib/store/notice_store.dart`: `NoticeStore` (`isAccepted`, `accept`, both may throw) and `SharedPreferencesNoticeStore` using `SharedPreferencesAsync` with key `sounder.expansion_notice_accepted` and value `true`; nothing else stored; check the `SharedPreferencesAsync` API with the dart MCP server
    - _Requirements: REQ-NOTICE-2, REQ-NOTICE-3, REQ-NOTICE-5_
  - [x] 10.5 Add the new key actions
    - `app/lib/input/keyboard_adapter.dart`: `KeyAction.expand` for a non-repeat ArrowDown key-down; `choose1` to `choose4` for non-repeat key-downs of `digit1`..`digit4` and `numpad1`..`numpad4` (E24); their key-ups and Repeat_Events return `swallow`; update the doc-comment table
    - _Requirements: REQ-TOKENS-4, REQ-CHOICE-3, REQ-NOTICE-2_
  - [x] 10.6 Write the key action unit tests
    - Add to `app/test/keyboard_adapter_test.dart`: ArrowDown down, up and repeat; digits and numpad 1 to 4; digit 5 ignored; Space, Enter and Escape unchanged
    - _Requirements: REQ-TOKENS-4, REQ-CHOICE-3_

- [x] 11. Checkpoint - Ensure all tests pass
  - Run `cd app && flutter test` and `cd packages/morse_core && dart test` (dart MCP test tools where available).
  - Ensure all tests pass, ask the user if questions arise.

- [x] 12. Wire the Expand flow into the Key_Screen
  - [x] 12.1 Extend `KeyScreenState`
    - `app/lib/ui/key_screen_state.dart`: `noticeVisible`, `thinking`, `candidates` (unmodifiable, 0 to 4), `failureVisible`, `fallbackCandidate` with a private sentinel in `copyWith` so it can be reset to `null`
    - _Requirements: REQ-NOTICE-1, REQ-WAIT-1, REQ-CHOICE-1, REQ-FAIL-1, REQ-CHOICE-5_
  - [x] 12.2 Extend `KeyScreenController`
    - `app/lib/ui/key_screen_controller.dart`: `expansionClientProvider` (real `TransportExpansionClient` with `HttpExpansionTransport(http.Client())` and `Future<void>.delayed`) and `noticeStoreProvider`
    - `build()` starts `_loadAcceptance()` (error is `false`, D10); `expand()`, `sendNotice()` (D11), `cancelNotice()`, `_send(tokens)` with `_requestSeq` and `_pendingId`, the newest-and-same-tokens check, the Dart_Validator and `take(4)`; `choose(n)`; `speak()` resets `fallbackCandidate`; `escape()` (D12); `arrowDown()`; `_publish()` sentence-change hook (D15) abandoning the pending request, clearing the Failure_Message and narrowing
    - Only `speak()` and `choose()` call the Speech_Service; nothing prints or logs text
    - _Requirements: REQ-TOKENS-2, REQ-NOTICE-1 to REQ-NOTICE-5, REQ-WAIT-3, REQ-WAIT-4, REQ-WAIT-6, REQ-CHOICE-1, REQ-CHOICE-3 to REQ-CHOICE-6, REQ-NARROW-1, REQ-NARROW-2, REQ-FAIL-1, REQ-FAIL-2, REQ-FAIL-4_
  - [x] 12.3 Implement the expansion widgets
    - One file each in `app/lib/ui/`: `tokens_message.dart` (24 px), `expansion_notice.dart` (inline panel, constant `expansionNoticeText` with the exact REQ-NOTICE-1 text, `Send` and `Cancel` with `sounderButtonStyle()`), `thinking_indicator.dart` (static `Thinking\u2026` in a live region, no spinner), `failure_message.dart` (live region), `candidate_list.dart` (numbered `FilledButton`s, 32 px, wrapping, at least 64 by 64, semantic label `n. text`)
    - _Requirements: REQ-TOKENS-3, REQ-NOTICE-1, REQ-WAIT-1, REQ-FAIL-1, REQ-FAIL-2, REQ-CHOICE-2_
  - [x] 12.4 Add the Expand button and the candidate fallback text
    - `app/lib/ui/action_bar.dart`: `Expand` button after Clear, disabled when Expand is not offered, same colours when disabled
    - `app/lib/speech/fallback_view.dart`: optional `candidateText` shown at 36 px in place of `SentenceDisplay`
    - _Requirements: REQ-TOKENS-2, REQ-TOKENS-4, REQ-CHOICE-5_
  - [x] 12.5 Wire `KeyScreen`
    - `app/lib/ui/key_screen.dart`: expansion area below the action bar in the D14 order, so the Sentence, Partial_Sequence and On_Screen_Key never move; `_onKeyEvent` maps `expand` to `arrowDown()`, `choose1..4` to `choose(n)`, `closeFallback` to `escape()`; Space, Enter and repeat handling unchanged; pass `fallbackCandidate` to `FallbackView`
    - _Requirements: REQ-TOKENS-4, REQ-NOTICE-2, REQ-NOTICE-3, REQ-WAIT-2, REQ-CHOICE-3, REQ-FAIL-3_
  - [x] 12.6 Extend the source rules test
    - `app/test/source_rules_test.dart`: no `print`, `debugPrint` or `log` call in the expansion files under `lib/compose/`, `lib/net/`, `lib/store/` and the controller; no string literal under `lib/` equal (ASCII-lowercased, trailing `.!?` removed) to any valid fixture candidate or any of the six spike-3 sentences; confirm the REQ-COMPOSE-1 and `Mock` naming rules cover the new files
    - _Requirements: REQ-FAIL-4, REQ-APPTEST-4, REQ-APPTEST-5_
  - [x] 12.7 Write widget tests for the Expansion_Notice
    - Create `app/test/support/expansion_mocks.dart` if not present (`MockExpansionClient` that records calls and completes replies on demand, `MockNoticeStore` with a settable result that can throw) and `app/test/expansion_screen_test.dart`, overriding providers with these, `MockSpeechService` and `ManualTimeBase`; use `pump`, not `pumpAndSettle`
    - Exact notice text; Send by button and ArrowDown sends one request; Cancel by button and Escape sends nothing and keeps the Sentence; stored acceptance skips the notice; a throwing store shows the notice again next time and still sends for an activated Send
    - _Requirements: REQ-NOTICE-1 to REQ-NOTICE-5, REQ-APPTEST-3_
  - [x] 12.8 Write widget tests for waiting, stale replies and narrowing
    - Add to `expansion_screen_test.dart` (create the mocks file if not present): Thinking_Indicator shown in a live region; Space, Undo, Clear and Speak work while pending; a Sentence change abandons the request; a second Expand supersedes the first; a stale reply is ignored; adding a letter narrows the Candidate_List
    - _Requirements: REQ-WAIT-1, REQ-WAIT-2, REQ-WAIT-4, REQ-WAIT-6, REQ-NARROW-1, REQ-NARROW-2, REQ-APPTEST-3_
  - [x] 12.9 Write widget tests for choosing, failure and the Tokens_Message
    - Add to `expansion_screen_test.dart` (create the mocks file if not present): choose by click and by number key, one speech call each, Sentence unchanged; Enter speaks the typed text while candidates are shown; speech failure shows the candidate in the Fallback_View; a reply arriving makes no speech call; locally invalid candidates dropped; Candidate_Button size, font and semantic label, wrapping at 320 px; Failure_Message for timeout, non-200 and an empty list, staying until the Sentence changes or Expand is pressed again; the three Tokens_Message texts with Expand disabled
    - _Requirements: REQ-CHOICE-1 to REQ-CHOICE-6, REQ-FAIL-1 to REQ-FAIL-3, REQ-TOKENS-2, REQ-TOKENS-3, REQ-APPTEST-3_

- [ ] 13. Measure expansion latency in `eval/`
  - [x] 13.1 Write the latency script
    - Create the `eval/` folder and `eval/expansion_latency.js`: a browser-console snippet for the hosted page that sends the six spike-3 Token_Lists in turn, 24 requests, one every 3.5 s, timing `performance.now()` from send to parsed reply; it prints durations and statuses only, never candidate text
    - _Requirements: REQ-LATENCY-1, REQ-STEER-2_
  - [ ] 13.2 Run the manual latency measurement and record it
    - Run the snippet on the hosted site over broadband; write `eval/expansion_latency.md` with the method, every raw duration in ms, the statuses and the median plus one frame (about 17 ms, design L5); the median must be under 3,000 ms. Ask the user if the median is over budget
    - _Requirements: REQ-LATENCY-1_

- [x] 14. Final checkpoint - Ensure all tests pass
  - Run `cd worker && npm test`, `cd packages/morse_core && dart test` and `cd app && flutter test`.
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Part A has no optional tasks. In Part B only the widget tests (12.7 to 12.9) are optional, marked with `*`; the fixture test, every kiri_check property test, the unit tests and the source rules test are required.
- Properties 1 to 3 are tested in both suites (fast-check in `worker/`, kiri_check in `app/`); Properties 4 to 6 only in `worker/`; Properties 7 to 10 only in `app/`.
- Tasks 8 and 13.2 include manual steps the user asked for (deploy check, hosted requests, latency measurement). Ask the user before pushing or deploying.
- Each task cites requirement IDs for traceability; property tasks also cite the requirement clause numbers from the design.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1"] },
    { "id": 1, "tasks": ["2.1", "2.2"] },
    { "id": 2, "tasks": ["2.3", "3.1"] },
    { "id": 3, "tasks": ["2.4", "3.2"] },
    { "id": 4, "tasks": ["2.5"] },
    { "id": 5, "tasks": ["2.6"] },
    { "id": 6, "tasks": ["3.3"] },
    { "id": 7, "tasks": ["3.4"] },
    { "id": 8, "tasks": ["4"] },
    { "id": 9, "tasks": ["5.1", "5.4", "5.5"] },
    { "id": 10, "tasks": ["5.2", "5.6"] },
    { "id": 11, "tasks": ["5.3", "5.7"] },
    { "id": 12, "tasks": ["5.8", "6.1"] },
    { "id": 13, "tasks": ["6.2", "6.3", "7.1", "7.2"] },
    { "id": 14, "tasks": ["6.4"] },
    { "id": 15, "tasks": ["8"] },
    { "id": 16, "tasks": ["9.1", "9.2", "9.7"] },
    { "id": 17, "tasks": ["9.3", "9.4", "9.9", "10.1", "10.5"] },
    { "id": 18, "tasks": ["9.5", "10.2", "10.3", "10.4", "10.6"] },
    { "id": 19, "tasks": ["9.6"] },
    { "id": 20, "tasks": ["9.8"] },
    { "id": 21, "tasks": ["9.10"] },
    { "id": 22, "tasks": ["9.11"] },
    { "id": 23, "tasks": ["9.12"] },
    { "id": 24, "tasks": ["11"] },
    { "id": 25, "tasks": ["12.1", "12.3", "12.4"] },
    { "id": 26, "tasks": ["12.2"] },
    { "id": 27, "tasks": ["12.5"] },
    { "id": 28, "tasks": ["12.6", "12.7"] },
    { "id": 29, "tasks": ["12.8"] },
    { "id": 30, "tasks": ["12.9"] },
    { "id": 31, "tasks": ["13.1"] },
    { "id": 32, "tasks": ["13.2"] },
    { "id": 33, "tasks": ["14"] }
  ]
}
```
