# Requirements Document

## Introduction

`shorthand-expansion` lets the user key the start of each word in Morse (for example `I W S W P`), choose Expand, and see up to 4 full sentences (for example `I want some water please`). Choosing a sentence speaks it. Nothing is spoken that the user did not choose. The flow never dead-ends: the typed text can always be spoken as it is with the existing Speak_Action from the key-screen spec.

The model decision comes from spike 3 (`spikes/RESULTS.md`): Cloudflare Workers AI, model `@cf/meta/llama-4-scout-17b-16e-instruct`, temperature 0.2, max_tokens 200. In the spike, Llama 3.3 70B scored 2/6 hits against Scout's 4 to 5 of 6.

The work is ordered in two parts with a checkpoint between them:

- **Part A (server):** the `/expand` endpoint, served by the same Cloudflare Worker that serves the app.
- **Checkpoint:** Part A is tested, merged and deployed before Part B starts (REQ-CHECKPOINT-1).
- **Part B (client):** the Expand flow in the Flutter app.

Every acceptance criterion has an ID in the style of the earlier specs. Part A areas: `REQ-VALIDATOR-n` (initials validator, shared by both parts), `REQ-ROUTE-n` (Worker routing and config), `REQ-EXPAND-n` (request handling), `REQ-REPLY-n` (model reply processing), `REQ-LOG-n` (privacy and logging), `REQ-WORKERTEST-n` (Worker tests), `REQ-PIPE-n` (CI pipeline), `REQ-STEER-n` (steering updates). Checkpoint: `REQ-CHECKPOINT-n`. Part B areas: `REQ-TOKENS-n`, `REQ-NOTICE-n`, `REQ-WAIT-n`, `REQ-CHOICE-n`, `REQ-NARROW-n`, `REQ-FAIL-n`, `REQ-LATENCY-n`, `REQ-APPTEST-n`. None of these reuse an area name from the morse-core, adaptive-timing or key-screen specs. Tests and doc comments cite these IDs.

### Conflicts with steering (recorded decisions)

The brief conflicts with the steering files in these places. The brief wins in each case. The steering files are updated as part of this spec (REQ-STEER-1 to REQ-STEER-3), not silently overridden.

- **S1. Backend host and folder.** `tech.md` says the backend is one stateless serverless function in `functions/expand` on Netlify Functions. The brief and the current repo use a Cloudflare Worker: the root `wrangler.jsonc` already serves the web build as static assets, and `.github/workflows/deploy.yml` deploys it with `cloudflare/wrangler-action`. Decision: the `/expand` endpoint is part of that same Worker, with its code in a new top-level folder `worker/`. `tech.md` and `structure.md` are updated (REQ-STEER-1, REQ-STEER-2).
- **S2. New top-level folders.** `structure.md` forbids new top-level folders without updating it. This spec adds `worker/` (Worker code and tests) and `fixtures/` (the shared validator fixture). `spikes/` already exists and is not listed. `structure.md` is updated to list all three and to drop `functions/expand/` (REQ-STEER-2). `structure.md` already lists `eval/` ("benchmark phrase set, runner, results"), but the folder does not exist on disk yet. This spec creates `eval/` to hold the REQ-LATENCY-1 latency results (E26), and updates the existing `eval/` entry to read: "`eval/` benchmark phrase set, runner, results, and measurements of the hosted app, such as expansion latency; nothing here ships." (REQ-STEER-2).
- **S3. Expansion performance budget.** `tech.md` says expansion has a median under 1.5 s, times out at 2.5 s and falls back to saved phrases. Spike 3 measured a 2,813 ms median for Scout. Decision, from the brief: median under 3 s on a normal connection (REQ-LATENCY-1), client timeout 6 s (REQ-WAIT-5), server model timeout 5 s (REQ-EXPAND-9), and on failure a message instead of saved phrases, because saved phrases are out of scope (REQ-FAIL-1). `tech.md` is updated (REQ-STEER-1).
- **S4. Speech.** `tech.md` says speech uses the platform's own text-to-speech. This spec agrees and reuses the key-screen Speech_Service. No change.
- **S5. Opt-in cloud expansion.** `product.md` says cloud expansion is opt-in. The one-time Expansion_Notice with Send and Cancel (REQ-NOTICE-1 to REQ-NOTICE-5) is the opt-in. No change. `product.md` also says expansion may send recent sentences; this spec sends only tokens (conversation context is out of scope). The notice text ends `Sounder stores nothing.` instead of the brief's `Nothing is stored.`: the user changed the wording on review because Sounder can promise what Sounder does, not what Cloudflare does.

### Decisions and assumptions

These points were not fixed by the brief. Each is a recorded decision, flagged for review.

- **E1. Letters are ASCII.** "Letters" in a Token and in a candidate word means the ASCII letters `A`-`Z` and `a`-`z`. Lowercasing is ASCII lowercasing. Tokens come from the Morse code table, whose letters are `A`-`Z`. This also keeps the TypeScript and Dart validators identical, because Unicode case mapping and `\p{L}` differ between runtimes. A candidate with a non-ASCII letter such as `café` fails the validator.
- **E2. Whitespace.** Candidates are split on runs of the ASCII whitespace characters U+0009 to U+000D and U+0020. Other Unicode spaces are not separators, so they end up inside a word and make it fail.
- **E3. Apostrophes and hyphens.** An apostrophe is U+0027 `'` or U+2019 `’`. A hyphen is U+002D `-`. Each apostrophe or hyphen in a stripped word must have an ASCII letter directly before it and directly after it. So `don't` and `well-known` pass; `'til`, `rock-`, `a--b` fail.
- **E4. Strip characters.** The characters stripped from both ends of each word are exactly `.` `,` `!` `?` `;` `:` `"` `(` `)`, removed repeatedly until the first and last characters are not in that set. Curly quotes are not stripped.
- **E5. Length unit.** "At most 200 characters" counts UTF-16 code units, which is what both `String.length` in TypeScript and Dart return. Whitespace trimmed before counting is the E2 set.
- **E6. Sentence-case scope.** Sentence-case conversion changes only ASCII letter case and keeps every other character, including whitespace and punctuation, in place. "Every word starts with a capital letter" means the first character of every stripped word is `A`-`Z`. In the converted text, the first ASCII letter of the candidate is uppercase; a stripped word equal to `I`, or starting with `I'` or `I’`, keeps an uppercase `I` and lowercases the rest; every other ASCII letter is lowercase.
- **E7. Duplicate key.** Two candidates are duplicates when they are equal after ASCII lowercasing and removing the trailing run of `.`, `!` and `?` characters. The first one in model order is kept.
- **E8. JSON extraction.** The Workers AI reply's `response` field may be a string or an already-parsed object (seen in spike 3). If it is an object, the object is used. If it is a string, the text from the first `{` to the last `}` inclusive is parsed as JSON. Any other shape, or a parse error, counts as an unparseable reply.
- **E9. Check order.** The `/expand` checks run in this order: method (405), rate limit (429), Content-Type (415), body size (413), body shape (400), then the model (503 or 200). A request rejected at an earlier check never reaches a later one. Non-POST requests get 405 and do not call the Rate_Limiter; the limit applies to POST `/expand` only. Every POST `/expand` calls the Rate_Limiter exactly once, before the body is read, so requests later rejected with 415, 413 or 400 still count against the limit. The brief listed the rate limit after the body checks; the user chose this order on review so that invalid requests are limited too.
- **E10. Content-Type matching.** The Content-Type check compares the media type only, case-insensitively, so `application/json; charset=utf-8` passes. A missing header fails with 415.
- **E11. Body size.** The 1,024-byte limit applies to the bytes actually read from the body, not only to the Content-Length header. A body of exactly 1,024 bytes is accepted.
- **E12. Error bodies.** The brief requires Content-Type `application/json` on every `/expand` response. Error responses therefore carry a JSON body `{"error":"<code>"}` with the codes listed in REQ-EXPAND-11. Clients use only the status code.
- **E13. Missing client IP.** If the `CF-Connecting-IP` header is missing, the rate-limit key is the fixed string `unknown`, one bucket shared by all such requests. Cloudflare sets `CF-Connecting-IP` on every request it proxies, so the header is missing only in local development (`wrangler dev`) and in tests, never in the hosted build.
- **E14. Rate limit accuracy.** The Cloudflare rate-limiting binding is approximate and counts separately in each Cloudflare location ([Cloudflare docs](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)). "20 requests per 60 seconds" is therefore a configured limit, not a strict guarantee. The binding's `period` must be 10 or 60; 60 is used.
- **E15. Non-`/expand` requests that reach the Worker.** With `run_worker_first` set to `["/expand"]`, other requests are served by the asset router. If any other request does reach the Worker script, the Worker passes it unchanged to the ASSETS binding, so it is served as today.
- **E16. Words of the Sentence.** A word of the Sentence is a maximal run of non-Word_Space Decoded_Items. Leading, trailing and repeated Word_Spaces create no empty words. An Unknown_Letter_Item (Placeholder) is a non-letter.
- **E17. Expand not offered.** "Expand is not offered" means the Expand button is shown disabled (so the layout does not move, product principle 5) and ArrowDown does nothing. The brief names one reason (a non-letter). This spec adds the two server limits, because a request breaking them would get a 400: more than 12 words, or a word longer than 8 letters. Each reason has its own message (REQ-TOKENS-3). An empty Sentence disables Expand with no message, so the first screen stays quiet.
- **E18. Keys while the Expansion_Notice is shown.** The brief keeps Space as the Morse key everywhere. While the Expansion_Notice is shown, Space still drives the Live_Decoder and activates neither Send nor Cancel, a non-repeat ArrowDown activates Send, and a non-repeat Escape activates Cancel. Enter keeps its key-screen meaning (speak the typed text).
- **E19. Pending request and Sentence changes.** If the Sentence changes while a request is pending, the pending request is abandoned: "Thinking…" is removed and its reply is ignored when it arrives, with no failure message. A new Expand while a request is pending starts a new request, and only the reply to the newest request can be shown.
- **E20. Candidates after choosing.** Choosing a candidate leaves the Sentence and the Candidate_List unchanged, so the user can speak it again or refine it.
- **E21. Fallback text for a candidate.** If speaking a chosen candidate fails, the key-screen Fallback_View shows the candidate text instead of the Sentence text. This amends key-screen REQ-SPEAK-3 for candidates only (REQ-CHOICE-5).
- **E22. Messages stay until the user acts.** The failure message and the Tokens_Message stay on screen until the Sentence changes or the user chooses Expand again. They never close on a timer (product principle 3).
- **E23. Key-screen REQ-KEY-12 is extended.** REQ-KEY-12 lists the only events that may change the Key_Screen. This spec adds three: an Expansion_Client result (reply, error or timeout), activation of Expand, Send, Cancel or a Candidate_Button, and an ArrowDown, number or Escape key event. The 6-second timeout changes the screen without a user action; this is accepted because it is the result of the user's Expand, and the message it shows then stays (E22).
- **E24. Number keys.** A number key means a non-repeat key-down of the digit-row keys `1` to `4` or the numpad keys `1` to `4`.
- **E25. Known limitation: one-switch reach.** Expand (ArrowDown), Send, Cancel and the number keys need a keyboard or pointer. A user with only the Space switch cannot reach them until the switch-scanning spec exists. This matches key-screen K10.
- **E26. Latency is measured, not unit-tested.** The 3-second median (REQ-LATENCY-1) is checked by a manual measurement against the hosted Worker, recorded in `eval/`. Automated tests never call the model.

## Glossary

- **Worker**: The Cloudflare Worker named `sounder`, configured by the root `wrangler.jsonc`, with its TypeScript code in `worker/`. It serves the app's static assets and the `/expand` endpoint.
- **Wrangler_Config**: The root file `wrangler.jsonc`.
- **ASSETS_Binding**: The Worker's static assets binding, named `ASSETS`, serving `./app/build/web`.
- **AI_Binding**: The Worker's Workers AI binding, named `AI`, called through `env.AI.run`.
- **Rate_Limiter**: The Worker's rate-limiting binding (Cloudflare `ratelimits`), configured for 20 requests per 60 seconds.
- **Expand_Endpoint**: The Worker's handler for the path `/expand`.
- **Model**: Workers AI model `@cf/meta/llama-4-scout-17b-16e-instruct`, called with temperature 0.2 and max_tokens 200.
- **Model_Caller**: The Worker component that calls the Model. It is injected into the Expand_Endpoint so that tests replace it with a mock.
- **System_Prompt**: The system message sent to the Model, adapted from spike 3 (REQ-EXPAND-8).
- **Token**: One typed word start: 1 to 8 ASCII letters (E1).
- **Token_List**: An ordered list of 1 to 12 Tokens.
- **Candidate**: A string proposed by the Model as an expansion of a Token_List.
- **Word**: One piece of a Candidate after splitting on runs of whitespace (E2).
- **Stripped_Word**: A Word with the strip characters (E4) removed from both ends.
- **Initials_Validator**: The rule of REQ-VALIDATOR-1, which decides whether a Candidate is valid for a Token_List. Defined once, implemented twice: TS_Validator and Dart_Validator.
- **TS_Validator**: The TypeScript implementation of the Initials_Validator in `worker/`.
- **Dart_Validator**: The pure Dart implementation of the Initials_Validator in `app/lib/compose/`.
- **Validator_Fixture**: The file `fixtures/expansion_validator.json`, holding inputs and expected results read by both test suites.
- **Sentence_Case**: The conversion of REQ-REPLY-3 and E6.
- **Reply_Processor**: The Worker component that turns the Model reply into the final candidate list (REQ-REPLY-1 to REQ-REPLY-6).
- **Worker_Log**: Anything the Worker writes with `console` or any other logging API.
- **Deploy_Workflow**: The GitHub Actions file `.github/workflows/deploy.yml`.
- **Key_Screen**, **Live_Decoder**, **Composer**, **Sentence**, **Decoded_Item**, **Letter_Item**, **Unknown_Letter_Item**, **Word_Space**, **Placeholder**, **Speak_Text**, **Speak_Action**, **Speech_Service**, **Speech_Failure**, **Fallback_View**, **Repeat_Event**: As defined in the key-screen spec.
- **Sentence_Tokens**: The Token_List built from the Sentence: its words in order (E16).
- **Expand_Action**: Activation of the on-screen Expand button, or a non-repeat ArrowDown key-down on the Key_Screen while the Expansion_Notice is not shown.
- **Tokens_Message**: The short message that says why Expand is not offered (REQ-TOKENS-3).
- **Expansion_Notice**: The one-time notice shown on the first Expand_Action, with Send and Cancel controls (REQ-NOTICE-1).
- **Notice_Acceptance**: The record in browser storage that the user chose Send on the Expansion_Notice.
- **Expansion_Client**: The app component in `app/lib/compose/` that sends a Token_List to `/expand` and returns the result.
- **Pending_Request**: An Expansion_Client request that has been sent and has neither returned, failed nor timed out, and has not been abandoned.
- **Thinking_Indicator**: The static text `Thinking…` (ending in U+2026) shown while a Pending_Request exists.
- **Candidate_List**: The ordered list of 0 to 4 Candidates shown on the Key_Screen.
- **Candidate_Button**: A large on-screen button for one Candidate in the Candidate_List, numbered 1 to 4.
- **Failure_Message**: The text `No suggestions. Add letters or speak what you typed.`

## Requirements

## Part A: the `/expand` endpoint

### Requirement 1: Initials validator

**User Story:** As a person who typed word starts, I want every suggested sentence to match my letters word for word, so that I am never offered words I did not start.

#### Acceptance Criteria

1. REQ-VALIDATOR-1: THE Initials_Validator SHALL accept a Candidate for a Token_List only when all of these hold: (a) the Candidate, trimmed of E2 whitespace, is at most 200 characters (E5); (b) splitting the Candidate on runs of E2 whitespace, ignoring leading and trailing whitespace, gives exactly as many Words as the Token_List has Tokens; (c) every Stripped_Word is non-empty and made only of ASCII letters, apostrophes and hyphens, with each apostrophe and hyphen between two ASCII letters (E3); and (d) for every i, Stripped_Word i, ASCII-lowercased, starts with Token i, ASCII-lowercased. THE Initials_Validator SHALL reject every other Candidate.
2. REQ-VALIDATOR-2: THE TS_Validator and THE Dart_Validator SHALL each return, for every case in the Validator_Fixture, the expected result recorded for that case.
3. REQ-VALIDATOR-3: THE Validator_Fixture SHALL be one JSON file at `fixtures/expansion_validator.json` holding a list of cases, each with a Token_List, a Candidate and the expected result (valid or invalid), and SHALL include at least one valid and one invalid case for each of the conditions (a) to (d) in REQ-VALIDATOR-1, the boundary lengths 200 and 201, each strip character, both apostrophes, a hyphen, a word with a leading and with a trailing apostrophe or hyphen, a non-ASCII letter, a Unicode non-ASCII space, and a Token longer than its Word.
4. REQ-VALIDATOR-4: THE TS_Validator and THE Dart_Validator SHALL each be a pure function of the Token_List and the Candidate, with no I/O, no clock and no logging.
5. REQ-VALIDATOR-5: FOR ALL Token_Lists, and FOR ALL Candidates generated so that Word i starts with Token i in any mix of letter case and continues with 0 or more ASCII letters, joined by 1 or more E2 whitespace characters, optionally with strip characters at the ends of Words, and at most 200 characters after trimming, THE TS_Validator and THE Dart_Validator SHALL accept the Candidate (generated-valid property).
6. REQ-VALIDATOR-6: FOR ALL Candidates generated as in REQ-VALIDATOR-5 and FOR ALL positions i, replacing the first letter of Stripped_Word i with a different ASCII letter (ignoring case) SHALL make THE TS_Validator and THE Dart_Validator reject the Candidate (first-letter property).
7. REQ-VALIDATOR-7: FOR ALL Candidates generated as in REQ-VALIDATOR-5 and then given one or more Words added or removed so that the Word count differs from the Token count, THE TS_Validator and THE Dart_Validator SHALL reject the Candidate (word-count property).

### Requirement 2: Worker routing and configuration

**User Story:** As a Sounder user, I want the app to load exactly as it does today, so that adding the endpoint breaks nothing.

#### Acceptance Criteria

1. REQ-ROUTE-1: THE Wrangler_Config SHALL keep `name` `sounder`, the `compatibility_date`, `assets.directory` `./app/build/web` and `assets.not_found_handling` `single-page-application`, and SHALL add: `main` pointing to the TypeScript entry point in `worker/`; `assets.binding` `ASSETS`; `assets.run_worker_first` set to `["/expand"]`; an `ai` binding named `AI`; and one `ratelimits` binding with `simple.limit` 20 and `simple.period` 60.
2. REQ-ROUTE-2: THE design SHALL cite the current Cloudflare documentation page for each Wrangler_Config field and each runtime API used (`assets.run_worker_first`, `assets.binding`, the `ai` binding, `env.AI.run`, the `ratelimits` binding and its `limit` method), with the date it was checked.
3. REQ-ROUTE-3: WHEN the deployed Worker receives `GET /`, THE Worker SHALL return the app's `index.html` with status 200, as the current deployment does.
4. REQ-ROUTE-4: WHEN the deployed Worker receives a navigation request for a path that matches no asset and is not `/expand`, THE Worker SHALL return the app's `index.html` through single-page-application handling, as the current deployment does.
5. REQ-ROUTE-5: IF a request for a path other than `/expand` reaches the Worker script, THEN THE Worker SHALL pass the request unchanged to the ASSETS_Binding and return its response unchanged (E15).

### Requirement 3: Request handling

**User Story:** As the Sounder operator, I want the endpoint to accept only well-formed, limited requests, so that it cannot be misused or run up model costs.

#### Acceptance Criteria

1. REQ-EXPAND-1: IF a request to `/expand` uses a method other than POST, THEN THE Expand_Endpoint SHALL return status 405 with the header `Allow: POST`.
2. REQ-EXPAND-2: IF a POST to `/expand` has no Content-Type header, or a Content-Type whose media type is not `application/json` (E10), THEN THE Expand_Endpoint SHALL return status 415.
3. REQ-EXPAND-3: IF the body of a POST to `/expand` is longer than 1,024 bytes (E11), THEN THE Expand_Endpoint SHALL return status 413.
4. REQ-EXPAND-4: IF the body of a POST to `/expand` is not a JSON object with exactly one field, `tokens`, whose value is a Token_List (an array of 1 to 12 strings, each 1 to 8 ASCII letters), THEN THE Expand_Endpoint SHALL return status 400.
5. REQ-EXPAND-5: THE Expand_Endpoint SHALL run its checks in the order of E9 and SHALL return the status of the first check that fails.
6. REQ-EXPAND-6: WHEN a POST to `/expand` is received, THE Expand_Endpoint SHALL call the Rate_Limiter exactly once, before reading the body, with the value of the `CF-Connecting-IP` header as the key, or `unknown` if the header is missing (E13).
7. REQ-EXPAND-7: IF the Rate_Limiter reports that the key is over the limit, THEN THE Expand_Endpoint SHALL return status 429 without reading the body and without making a Model call.
8. REQ-EXPAND-8: WHEN the Rate_Limiter allows the request and the request passes REQ-EXPAND-2 to REQ-EXPAND-4, THE Expand_Endpoint SHALL make one Model call with temperature 0.2, max_tokens 200, the System_Prompt as the system message and the Tokens joined by single spaces as the user message. THE System_Prompt SHALL say that each input item is the start of one word (one or more letters), in order; that the reply is exactly 4 different candidates as JSON `{"candidates":[...]}`; that each candidate has one word per item; and that the language is everyday first-person language to a carer or friend.
9. REQ-EXPAND-9: IF the Model call raises an error, or returns no result within 5 seconds of the call starting, THEN THE Expand_Endpoint SHALL return status 503.
10. REQ-EXPAND-10: WHEN the Model call returns within 5 seconds, THE Expand_Endpoint SHALL return status 200 with body `{"candidates":[...]}` holding the Reply_Processor output of 0 to 4 Candidates.
11. REQ-EXPAND-11: THE Expand_Endpoint SHALL give every response the headers `Content-Type: application/json` and `Cache-Control: no-store` and no `Access-Control-Allow-Origin` header, and SHALL give every non-200 response the body `{"error":"<code>"}`, with code `method_not_allowed` (405), `unsupported_media_type` (415), `payload_too_large` (413), `bad_request` (400), `rate_limited` (429) or `model_unavailable` (503) (E12).

### Requirement 4: Reply processing

**User Story:** As a person choosing a sentence, I want suggestions that are clean, different and valid, so that every option is worth one press.

#### Acceptance Criteria

1. REQ-REPLY-1: WHEN the Model returns, THE Reply_Processor SHALL extract the JSON object as in E8 and take its `candidates` array. IF the reply is unparseable or has no `candidates` array, THEN THE Reply_Processor SHALL return an empty list.
2. REQ-REPLY-2: THE Reply_Processor SHALL keep only the string items of the `candidates` array, in model order, and SHALL trim E2 whitespace from both ends of each.
3. REQ-REPLY-3: WHEN a trimmed Candidate has 2 or more Words and the first character of every Stripped_Word is an uppercase ASCII letter, THE Reply_Processor SHALL convert the Candidate to Sentence_Case as defined in E6.
4. REQ-REPLY-4: THE Reply_Processor SHALL drop every Candidate that the TS_Validator rejects for the request's Token_List, then drop every Candidate that is a duplicate (E7) of an earlier kept Candidate, then keep the first 4 remaining Candidates in model order. The steps SHALL run in the order of REQ-REPLY-1 to REQ-REPLY-4.
5. REQ-REPLY-5: FOR ALL Candidates and Token_Lists, THE TS_Validator SHALL give the same result for a Candidate and for its Sentence_Case conversion (sentence-case validity property).
6. REQ-REPLY-6: FOR ALL Model replies, including non-JSON text, JSON of any shape, non-string items and any number of items, and FOR ALL Token_Lists, THE Reply_Processor SHALL return at most 4 Candidates, each accepted by the TS_Validator for that Token_List, with no two duplicates under E7 (output property).

### Requirement 5: Privacy and logging

**User Story:** As a person whose words are private, I want the server to keep nothing I typed, so that my messages stay mine.

#### Acceptance Criteria

1. REQ-LOG-1: THE Worker SHALL store no request data: no Tokens, Candidates, request bodies or IP addresses are written to any storage, cache or binding other than the key passed to the Rate_Limiter (REQ-EXPAND-6).
2. REQ-LOG-2: THE Worker_Log SHALL contain, for each `/expand` request, only the response status, the latency in milliseconds, the Token count (0 when the body was not read or was not a valid Token_List) and the Candidate count (0 for non-200 responses).
3. REQ-LOG-3: THE Worker_Log SHALL contain no Token, Candidate, request body, Model reply text, header value or IP address, including in error messages.

### Requirement 6: Worker tests

**User Story:** As a Sounder developer, I want the endpoint tested without calling the real model, so that tests are fast, free and repeatable.

#### Acceptance Criteria

1. REQ-WORKERTEST-1: THE `worker/` folder SHALL have its own `package.json` and `package-lock.json` with `vitest` and `fast-check` as dev dependencies, and an `npm test` script that runs every Worker test once and exits (no watch mode).
2. REQ-WORKERTEST-2: THE Worker tests SHALL use an injected mock Model_Caller, whose name begins with `Mock`, and SHALL make no call to the real AI_Binding.
3. REQ-WORKERTEST-3: THE Worker tests SHALL include `fast-check` property tests for REQ-VALIDATOR-5, REQ-VALIDATOR-6, REQ-VALIDATOR-7, REQ-REPLY-5 and REQ-REPLY-6, each with a fixed seed and at least 100 runs, generating inputs that satisfy their preconditions by construction, with no `fc.pre` and no `.filter`.
4. REQ-WORKERTEST-4: THE Worker tests SHALL include example tests for each status code 200 (with candidates and with an empty list), 405 (including the `Allow` header), 413, 415, 400, 429 and 503 (both model error and timeout), tests of the E9 check order (an over-limit request with an invalid body returns 429; a request rejected with 415, 413 or 400 still counts against the limit; a non-POST request returns 405 and makes no Rate_Limiter call), a test of the headers in REQ-EXPAND-11, and a test that reads the Validator_Fixture and checks REQ-VALIDATOR-2 for the TS_Validator.
5. REQ-WORKERTEST-5: THE Worker tests SHALL include a test that captures the Worker_Log during requests carrying known Tokens and Candidates and checks that none of those strings and no IP address appear in it (REQ-LOG-3).
6. REQ-WORKERTEST-6: Every Worker test description SHALL begin with the requirement ID or IDs the test covers, followed by a colon.

### Requirement 7: CI pipeline

**User Story:** As a Sounder developer, I want Worker tests to gate every deploy, so that a broken endpoint never ships.

#### Acceptance Criteria

1. REQ-PIPE-1: THE Deploy_Workflow SHALL contain a step named "Worker tests", with working directory `worker`, that runs `npm ci` and then `npm test`, placed before the "Build web app" step, with no `continue-on-error` on that step or its job.
2. REQ-PIPE-2: IF `npm test` in `worker/` exits with a non-zero code, THEN THE Deploy_Workflow run SHALL fail and neither the "Build web app" step nor the "Deploy to Cloudflare" step SHALL run.
3. REQ-PIPE-3: THE Deploy_Workflow SHALL keep the "Engine tests", "App tests", "Build web app" and "Deploy to Cloudflare" steps as they are, including the `wranglerVersion` value.

### Requirement 8: Steering updates

**User Story:** As a Sounder developer, I want the steering files to match what we build, so that later specs are not misled.

#### Acceptance Criteria

1. REQ-STEER-1: THE file `.kiro/steering/tech.md` SHALL describe the backend as the Cloudflare Worker in `worker/` that serves the app and `/expand` with Workers AI (S1), SHALL state the expansion budget as median under 3 s, client timeout 6 s, server model timeout 5 s and the Failure_Message on failure (S3), and SHALL list the Worker test command (`cd worker && npm test`).
2. REQ-STEER-2: THE file `.kiro/steering/structure.md` SHALL list the top-level folders `worker/`, `fixtures/` and `spikes/` with one line each on what they hold, SHALL no longer list `functions/expand/`, and SHALL change the existing `eval/` entry to read "`eval/` benchmark phrase set, runner, results, and measurements of the hosted app, such as expansion latency; nothing here ships." (S2). THE `eval/` folder SHALL be created by this feature and SHALL hold the REQ-LATENCY-1 latency results (E26).
3. REQ-STEER-3: THE steering updates in REQ-STEER-1 and REQ-STEER-2 SHALL be made in Part A, before the checkpoint.

## Checkpoint

### Requirement 9: Checkpoint between Part A and Part B

**User Story:** As a Sounder developer, I want the server finished and live before the client work starts, so that the client is built against a real endpoint.

#### Acceptance Criteria

1. REQ-CHECKPOINT-1: WHEN Part A is complete, THE team SHALL confirm, before any Part B work starts, that: `npm test` in `worker/`, `dart test` in `packages/morse_core` and `flutter test` in `app/` all pass; the Deploy_Workflow run for the Part A commit succeeded; on the hosted Worker, `GET /` returns the app and an unknown navigation path returns the app (REQ-ROUTE-3, REQ-ROUTE-4); and one manual `POST /expand` with `{"tokens":["I","W","S","W","P"]}` returns status 200 with a valid `candidates` list. The result of each check SHALL be recorded in `.kiro/evidence/`.

## Part B: the client

### Requirement 10: Tokens from the Sentence

**User Story:** As a person keying word starts, I want my typed words used as the starts of the sentence, so that Expand works on exactly what I see.

#### Acceptance Criteria

1. REQ-TOKENS-1: THE Key_Screen SHALL build the Sentence_Tokens from the words of the Sentence in order (E16), each word's Letter_Items giving one Token.
2. REQ-TOKENS-2: WHILE the Sentence is empty, or any word of the Sentence holds a non-letter (an Unknown_Letter_Item, a digit or a punctuation character), or the Sentence has more than 12 words, or a word has more than 8 letters, THE Key_Screen SHALL show the Expand button disabled and SHALL ignore Expand_Actions (E17).
3. REQ-TOKENS-3: WHILE Expand is disabled for a non-empty Sentence, THE Key_Screen SHALL show one Tokens_Message: `Expand needs letters only.` for a non-letter, `Expand takes up to 12 words.` for more than 12 words, or `Expand takes up to 8 letters a word.` for a word over 8 letters, checked in that order.
4. REQ-TOKENS-4: THE Key_Screen SHALL offer Expand as an `Expand` button in the action bar and as a non-repeat ArrowDown key-down. THE Key_Screen SHALL keep the Space key as the Morse key in every state of this spec, including while the Expansion_Notice, the Thinking_Indicator, the Candidate_List or the Failure_Message is shown.

### Requirement 11: One-time notice

**User Story:** As a person whose words are private, I want to know before my letters leave the device, so that cloud expansion is my choice.

#### Acceptance Criteria

1. REQ-NOTICE-1: WHEN an Expand_Action occurs and no Notice_Acceptance is stored, THE Key_Screen SHALL show the Expansion_Notice with the exact text `Expand sends the letters you typed to Cloudflare Workers AI to suggest sentences. Sounder stores nothing.` and the controls `Send` and `Cancel`, and SHALL send no request until Send is activated.
2. REQ-NOTICE-2: WHEN the user activates Send (button or non-repeat ArrowDown, E18), THE Key_Screen SHALL close the Expansion_Notice, store the Notice_Acceptance in browser storage, and send the Sentence_Tokens through the Expansion_Client.
3. REQ-NOTICE-3: WHEN the user activates Cancel (button or non-repeat Escape, E18), THE Key_Screen SHALL close the Expansion_Notice, send no request, store nothing, and leave the Sentence unchanged.
4. REQ-NOTICE-4: WHEN an Expand_Action occurs and a Notice_Acceptance is stored, THE Key_Screen SHALL send the Sentence_Tokens through the Expansion_Client without showing the Expansion_Notice.
5. REQ-NOTICE-5: IF reading or writing the Notice_Acceptance fails, THEN THE Key_Screen SHALL treat the Notice_Acceptance as not stored, so that the next Expand_Action shows the Expansion_Notice again, and SHALL still send the request for a Send already activated.

### Requirement 12: Waiting for suggestions

**User Story:** As a person waiting for suggestions, I want to see that the app is working and keep control of my sentence, so that waiting never traps me.

#### Acceptance Criteria

1. REQ-WAIT-1: WHILE a Pending_Request exists, THE Key_Screen SHALL show the Thinking_Indicator as static text and SHALL announce `Thinking…` to screen readers once when it appears.
2. REQ-WAIT-2: WHILE a Pending_Request exists, THE Key_Screen SHALL handle Space, Undo, Clear and Speak_Actions exactly as when no request is pending, and SHALL show no modal barrier.
3. REQ-WAIT-3: WHEN the Expansion_Client sends a request, THE Expansion_Client SHALL send one same-origin `POST /expand` with `Content-Type: application/json` and body `{"tokens":[...]}` holding the Sentence_Tokens.
4. REQ-WAIT-4: WHEN the Sentence changes while a Pending_Request exists, THE Key_Screen SHALL abandon that request, remove the Thinking_Indicator, and ignore its reply when it arrives (E19).
5. REQ-WAIT-5: IF a Pending_Request has no reply 6 seconds after it was sent, THEN THE Expansion_Client SHALL end it as a timeout.
6. REQ-WAIT-6: WHEN an Expand_Action occurs while a Pending_Request exists, THE Key_Screen SHALL abandon the older request and send a new one for the current Sentence_Tokens.

### Requirement 13: Choosing a candidate

**User Story:** As a person who cannot speak, I want to pick a suggested sentence with one action and hear it at once, so that I say a whole sentence with few presses.

#### Acceptance Criteria

1. REQ-CHOICE-1: WHEN the Expansion_Client returns status 200 for the newest request and the reply's Token_List equals the current Sentence_Tokens, THE Key_Screen SHALL run the Dart_Validator on every returned Candidate against the Sentence_Tokens, drop every Candidate it rejects, and show the first 4 remaining Candidates as the Candidate_List.
2. REQ-CHOICE-2: THE Key_Screen SHALL show each Candidate as a Candidate_Button labelled with its number (1 to 4, in list order) and its full text, at a font size of at least 32 logical pixels with wrapping and no truncation, a touch target of at least 48 by 48 logical pixels, and a semantic label holding the number and the text, meeting key-screen REQ-A11Y-3 and REQ-A11Y-4.
3. REQ-CHOICE-3: WHEN the user activates Candidate_Button n, or a number key n occurs (E24) and the Candidate_List has at least n Candidates, THE Key_Screen SHALL pass that Candidate's text to the Speech_Service exactly once, and SHALL leave the Sentence and the Candidate_List unchanged (E20).
4. REQ-CHOICE-4: WHEN a Speak_Action occurs while the Candidate_List is shown, THE Key_Screen SHALL speak the Speak_Text of the typed Sentence as in key-screen REQ-SPEAK-1, not a Candidate.
5. REQ-CHOICE-5: IF speaking a chosen Candidate ends in a Speech_Failure, THEN THE Key_Screen SHALL show the Fallback_View with that Candidate's text in place of the Sentence text, with all other key-screen REQ-SPEAK-3 to REQ-SPEAK-5 behaviour unchanged (E21).
6. REQ-CHOICE-6: THE Key_Screen SHALL pass a Candidate to the Speech_Service only as a result of REQ-CHOICE-3; a reply arriving, the Candidate_List changing or a number key with no matching Candidate SHALL make no Speech_Service call.

### Requirement 14: Narrowing and stale replies

**User Story:** As a person refining my words, I want adding letters to narrow the suggestions instead of starting over, so that each extra press brings me closer.

#### Acceptance Criteria

1. REQ-NARROW-1: WHEN the Sentence changes while the Candidate_List is shown, THE Key_Screen SHALL keep, in order, only the Candidates that the Dart_Validator accepts for the new Sentence_Tokens, and SHALL clear the Candidate_List if none remain or if the new Sentence disables Expand (REQ-TOKENS-2).
2. REQ-NARROW-2: IF a reply arrives for a request that is not the newest, or whose Token_List differs from the current Sentence_Tokens, THEN THE Key_Screen SHALL ignore the reply and leave the Candidate_List, the Thinking_Indicator and the Failure_Message as they are.
3. REQ-NARROW-3: FOR ALL Candidate_Lists and Sentence_Tokens, applying the narrowing rule SHALL give a list that is an in-order sublist of the original, every item of which the Dart_Validator accepts for the new Sentence_Tokens (narrowing subset property).
4. REQ-NARROW-4: FOR ALL Token_Lists T and Candidates C, and FOR ALL Token_Lists T′ made from T by appending one or more ASCII letters to one or more Tokens while each stays at most 8 letters, IF the Dart_Validator accepts C for T′, THEN the Dart_Validator SHALL accept C for T (adding letters only narrows property).
5. REQ-NARROW-5: FOR ALL Candidate_Lists and Sentence_Tokens, applying the narrowing rule twice with the same Sentence_Tokens SHALL give the same list as applying it once (narrowing idempotence property).

### Requirement 15: Failure

**User Story:** As a person relying on Sounder to talk, I want a clear way forward when suggestions fail, so that I am never stuck.

#### Acceptance Criteria

1. REQ-FAIL-1: IF the newest request ends in a timeout, a network error, a non-200 status, an unreadable body, or a Candidate_List that is empty after REQ-CHOICE-1, THEN THE Key_Screen SHALL remove the Thinking_Indicator, clear the Candidate_List and show the Failure_Message `No suggestions. Add letters or speak what you typed.`
2. REQ-FAIL-2: THE Key_Screen SHALL keep the Failure_Message shown until the Sentence changes or the next Expand_Action, with no timer removing it (E22), and SHALL announce it to screen readers once when it appears.
3. REQ-FAIL-3: WHILE the Failure_Message is shown, THE Key_Screen SHALL handle Space, Undo, Clear, Speak_Actions and Expand_Actions as usual, with no modal barrier.
4. REQ-FAIL-4: THE Expansion_Client and THE Key_Screen SHALL log no Token, Candidate or Sentence text.

### Requirement 16: Latency

**User Story:** As a person waiting to speak, I want suggestions within a few seconds, so that conversation keeps moving.

#### Acceptance Criteria

1. REQ-LATENCY-1: WHEN the hosted Worker is measured from a browser on a normal broadband connection over at least 20 Expand requests using the six spike-3 Token_Lists, THE time from sending each request to showing the Candidate_List or the Failure_Message SHALL have a median under 3,000 milliseconds, and the measurement method and results SHALL be recorded in `eval/` (E26).

### Requirement 17: App tests

**User Story:** As a Sounder developer, I want the client tested without the real model, so that tests are fast and the two validators stay in step.

#### Acceptance Criteria

1. REQ-APPTEST-1: WHEN `flutter test` runs in `app/`, THE app test suite SHALL exit with code 0 and SHALL include a test that reads `../fixtures/expansion_validator.json` and checks REQ-VALIDATOR-2 for the Dart_Validator.
2. REQ-APPTEST-2: THE app test suite SHALL include `kiri_check` property tests for REQ-VALIDATOR-5, REQ-VALIDATOR-6, REQ-VALIDATOR-7, REQ-NARROW-3, REQ-NARROW-4 and REQ-NARROW-5, each with a fixed seed and at least 100 generated cases, generating inputs that satisfy their preconditions by construction.
3. REQ-APPTEST-3: THE app test suite SHALL include widget tests for: the Expansion_Notice text, Send, Cancel and the storage-failure case (REQ-NOTICE-1 to REQ-NOTICE-5); the Thinking_Indicator and Undo, Clear and Speak while waiting (REQ-WAIT-1, REQ-WAIT-2); choosing a Candidate by click and by number key (REQ-CHOICE-3); Enter speaking the typed text while Candidates are shown (REQ-CHOICE-4); the Failure_Message for timeout, non-200 status and an empty list (REQ-FAIL-1); the stale-reply rule (REQ-NARROW-2); and the Tokens_Message cases (REQ-TOKENS-3).
4. REQ-APPTEST-4: THE app tests SHALL use a mock Expansion_Client and a mock clock or timer for the 6-second timeout, defined only under `app/test/` with class names beginning with `Mock`, and SHALL make no network request. No file under `app/lib/` SHALL define or import a class whose name begins with `Mock` or contain a hardcoded Candidate (key-screen REQ-CI-3 extended).
5. REQ-APPTEST-5: Every app test description SHALL begin with the requirement ID or IDs the test covers, followed by a colon.
