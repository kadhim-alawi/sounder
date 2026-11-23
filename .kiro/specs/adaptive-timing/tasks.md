# Implementation Plan: adaptive-timing

## Overview

The timing engine is added to `packages/morse_core` in Dart, in the order the design's layers depend on each other: purity-test groundwork, value types and errors, Debouncer, Classifier, event rules and Calibrator, Batch_Decoder, Live_Decoder, then the structure and privacy tests, then a final full run. Each step adds its public types to `lib/morse_core.dart` as it creates them, so the existing morse-core tests keep passing after every task.

Where `requirements.md` is more specific than `design.md`, the requirements win. In particular:

- `TimingConfig` rejects a Word_Gap_Factor greater than 1,000 (REQ-DEBOUNCE-3, B17).
- `Calibration` rejects any value greater than 2^40 µs (REQ-CAL-14, B17).
- REQ-BATCH-9's 1 percent margin also applies to post-debounce durations. The Property 12 generator keeps the design's stricter 2 percent margin on them.
- REQ-LIVE-6 measures letter completion to the Pending_Press's press timestamp when one exists (design T7).
- B15 amends morse-core REQ-PURE-4 so that public enums count as public types.

Conventions for every task:

- One public type per file in `lib/src/`, named in `snake_case.dart`, exported from `lib/morse_core.dart`.
- Every public declaration, including each enum value, has a `///` comment citing at least one requirement ID (REQ-ENGINE-6).
- Every test description begins with the requirement IDs it covers (REQ-PBT-3).
- Tests import only `package:morse_core/morse_core.dart` from the package.
- A task is done only when `cd packages/morse_core && dart test` passes and `dart analyze` reports nothing.

## Tasks

- [x] 1. Prepare the existing purity tests for the timing engine
  - [x] 1.1 Add the adaptive-timing requirement ID set and accept it in the ID checks
    - Create `test/support/timing_requirement_ids.dart` with `timingRequirementIds`, the 96 IDs: REQ-EVENT-1 to 6, REQ-DEBOUNCE-1 to 14 and 20 to 22, REQ-CAL-1 to 16, 20, 21, 30, 31, REQ-TIMING-1 to 11, REQ-BATCH-1 to 12, REQ-LIVE-1 to 14, REQ-ENGINE-1 to 8, REQ-PBT-1 to 8
    - In `test/purity_test.dart`, make the REQ-PURE-7 "every requirement ID cited in a lib/ doc comment exists" test and the REQ-TEST-4 "every test name begins with a known requirement ID" test check against `requirementIds.union(timingRequirementIds)`
    - Make the declaration scanner `_publicDeclarations` report enum declarations and enum values, and extend its self-check source with an enum so a missing enum-value doc comment is caught
    - _Requirements: REQ-ENGINE-6, REQ-PBT-3_
  - [x] 1.2 Widen the REQ-PURE-4 file-structure test to public enums
    - Rename the test to begin `REQ-PURE-4 REQ-ENGINE-3`; accept kind `class` or `enum`; still require exactly one public type per `lib/src/` file and the `snake_case` file name
    - Keep `_srcFiles()` non-recursive so `lib/src/internal/` is outside the one-type-per-file and export checks; `_libFiles()` stays recursive
    - Leave the four-class `_publicApi` checks in place for now; task 11.1 replaces them
    - _Requirements: REQ-ENGINE-3_

- [x] 2. Implement the value types and the timing error
  - [x] 2.1 Implement `TimingInputErrorKind` and `TimingInputException`
    - `lib/src/timing_input_error_kind.dart`: the 16 kinds with their fixed English phrases, as in the design; each phrase unique
    - `lib/src/timing_input_exception.dart`: `kind`, optional `index`, `message` built from the phrase and index only (`"Event n: …"` for event indexes, `"Press n: …"` for Debouncer indexes, `"Invalid timing: …"` with no index); `toString()` returns `message`
    - Export both from `lib/morse_core.dart`
    - _Requirements: REQ-EVENT-3, REQ-EVENT-4, REQ-ENGINE-5_
  - [x] 2.2 Implement `SwitchEventKind`, `SwitchEvent` and `Press`
    - `SwitchEvent` with `press`/`release` named constructors, `minTimestamp`/`maxTimestamp` = ∓2^52, value equality; `Press` with `pressedAt`, `releasedAt`, `duration`, value equality, timestamps in `toString()`
    - Constructors never throw; range and order are checked by consumers
    - Export all three
    - _Requirements: REQ-EVENT-1, REQ-DEBOUNCE-4_
  - [x] 2.3 Implement `TimingConfig` and `Calibration`
    - `TimingConfig({debounceTime = defaultDebounceTime, wordGapFactor = defaultWordGapFactor})`, non-const; `defaultDebounceTime = 30000` and `defaultWordGapFactor = 2.0` appear only here; `static final defaults`
    - Validation: `debounceTime < 0` → `invalidDebounceTime` first; then factor NaN, infinite, `<= 1.0` or `> 1000` → `invalidWordGapFactor`
    - `Calibration` with the four `int` fields, value equality, validation in field order Dit, Dah, Symbol_Gap, Letter_Gap: `<= 0`, `> 2^40` (1,099,511,627,776), `dah <= dit`, `letterGap <= symbolGap`
    - Export both
    - _Requirements: REQ-DEBOUNCE-1, REQ-DEBOUNCE-2, REQ-DEBOUNCE-3, REQ-DEBOUNCE-14, REQ-CAL-14_
  - [x] 2.4 Implement `MorseSymbol`, `GapClass`, `DecodedItemKind` and `DecodedItem`
    - `MorseSymbol.dit('.')`, `MorseSymbol.dah('-')` with `code`; `GapClass` with the three values
    - `DecodedItem.letter`, `.unknownLetter`, `.wordSpace`, and `factory DecodedItem.fromSymbols(String)` using `CodeTable.characterFor`; value equality on all fields; `toString()` gives only the kind name (T12)
    - Export all four
    - _Requirements: REQ-TIMING-3, REQ-TIMING-4, REQ-BATCH-2, REQ-BATCH-3, REQ-ENGINE-5_
  - [x] 2.5 Write unit tests for `TimingConfig` and `Calibration`
    - `test/timing_config_test.dart`: REQ-DEBOUNCE-1 defaults and exact read-back; REQ-DEBOUNCE-3 each invalid case including factor 1000 accepted and the next double above 1000 rejected, and both-invalid naming the Debounce_Time; REQ-DEBOUNCE-14 (0 and 1.5 accepted, −1 and 1.0 rejected); REQ-CAL-14 one case per field, the 2^40 cap (2^40 accepted, 2^40 + 1 rejected) and the field order
    - _Requirements: REQ-DEBOUNCE-1, REQ-DEBOUNCE-3, REQ-DEBOUNCE-14, REQ-CAL-14_
  - [x] 2.6 Write property test for config and Calibration validation
    - Create `test/timing_properties_test.dart` and `test/support/timing_arbitraries.dart` (no `package:morse_core` import; plain records only); seed `(100 + N) * 1000 + 3`, `maxExamples: 200`, `onFalsify: report(seed)`
    - Generators include negative Debounce_Times, NaN, ±infinity, 1.0, values just above and below 1.0 and 1,000, and Calibration values around 0 and 2^40
    - **Property 19: Config and Calibration validation**
    - **Validates: Requirements 2.1, 2.3, 5.10** (REQ-DEBOUNCE-1, REQ-DEBOUNCE-3, REQ-CAL-14)

- [x] 3. Implement the Debouncer
  - [x] 3.1 Implement `Debouncer`
    - `lib/src/debouncer.dart`: validate (`releaseBeforePress` before `pressOverlapsPrevious` at one index, lowest index wins), merge runs with Gap `< d`, then drop Presses with duration `< d`, return `List.unmodifiable`; never mutate the input
    - No numeric literal ≥ 1,000 in the file; Debounce_Time read only from `config`
    - Export it
    - _Requirements: REQ-DEBOUNCE-2, REQ-DEBOUNCE-4, REQ-DEBOUNCE-5, REQ-DEBOUNCE-6, REQ-DEBOUNCE-20_
  - [x] 3.2 Write unit tests for `Debouncer`
    - `test/debouncer_test.dart`: REQ-DEBOUNCE-10, -11, -12, -20 (both rules, both at one index, no partial result), -21, -22; and `REQ-PBT-6 REQ-DEBOUNCE-6` with a Press and a Gap of exactly `d` kept
    - _Requirements: REQ-DEBOUNCE-6, REQ-DEBOUNCE-10, REQ-DEBOUNCE-11, REQ-DEBOUNCE-12, REQ-DEBOUNCE-20, REQ-DEBOUNCE-21, REQ-DEBOUNCE-22, REQ-PBT-6_
  - [x] 3.3 Write property test for Debouncer against the reference model
    - Create `test/support/timing_oracles.dart` with `referenceDebounce(presses, d)` (group runs by index, then filter), independent of `lib/`
    - Add the `pressList` generator (0 to 50 Presses, durations 0 to 2,000,000, `d` 0 to 100,000, negative start timestamps, short durations weighted in) and a counter asserting at least 10 percent of cases contain a Press or Gap shorter than `d` (REQ-PBT-8)
    - **Property 1: Debouncer matches merge-then-drop and leaves no bounce**
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.7** (REQ-DEBOUNCE-4, -5, -6, -7, -10)
  - [x] 3.4 Write property test for debounce idempotence
    - Same generator and 10 percent counter as 3.3
    - **Property 2: Debounce is idempotent**
    - **Validates: Requirements 3.5** (REQ-DEBOUNCE-8)

- [x] 4. Implement the Classifier
  - [x] 4.1 Implement `Classifier`
    - `lib/src/classifier.dart`: `pressThreshold = dit + (dah − dit + 1) ~/ 2`, same form for `letterGapThreshold`; `wordGapThreshold` by the doubling loop and `BigInt` ceiling division, then `max(w0, letterGap + 1)`
    - `classifyPress` and `classifyGap` as threshold comparisons; a negative duration throws `negativeDuration` with no index
    - No numeric literal ≥ 1,000; only the literals the design names
    - Export it
    - _Requirements: REQ-TIMING-1, REQ-TIMING-2, REQ-TIMING-3, REQ-TIMING-4, REQ-TIMING-11, REQ-DEBOUNCE-2_
  - [x] 4.2 Write unit tests for `Classifier`
    - `test/classifier_test.dart`: REQ-TIMING-5 and REQ-TIMING-6 exact values (including factor 2.5 with Letter_Gap 700,001 → 1,750,003); REQ-TIMING-11; `REQ-PBT-6 REQ-TIMING-3 REQ-TIMING-4` boundaries (exactly Press_Threshold is dah, exactly Letter_Gap_Threshold is between letters, exactly Word_Gap_Threshold is between words); factor `1 + 2^-52` with Letter_Gap 2^40; factor 1,000 with Letter_Gap 2^40
    - _Requirements: REQ-TIMING-3, REQ-TIMING-4, REQ-TIMING-5, REQ-TIMING-6, REQ-TIMING-11, REQ-PBT-6_
  - [x] 4.3 Write property test for threshold formulas and ordering
    - Add `exactThresholds(cal, factor)` to the oracles (IEEE-754 bits via `ByteData.getUint64`, `BigInt` rationals); add `calibrationValues` and `wordGapFactor` generators (factor capped at 1,000)
    - **Property 6: Thresholds match the exact formulas and are ordered**
    - **Validates: Requirements 6.1, 6.2** (REQ-TIMING-1, REQ-TIMING-2)
  - [x] 4.4 Write property test for threshold classification
    - Add `durationNear(t)`; include negative durations for the throw case
    - **Property 7: Classification is a threshold comparison**
    - **Validates: Requirements 6.3, 6.4, 6.11** (REQ-TIMING-3, REQ-TIMING-4, REQ-TIMING-11)
  - [x] 4.5 Write property test for press jitter
    - Add `wellSeparated` and the Property 8 bands of `jitterDuration` (integer bounds `5x ≤ 6·dit`, `5x ≥ 4·dah`)
    - **Property 8: Press jitter is tolerated**
    - **Validates: Requirements 6.7** (REQ-TIMING-7)
  - [x] 4.6 Write property test for gap jitter
    - Add the three Property 9 bands of `jitterDuration`
    - **Property 9: Gap jitter is tolerated**
    - **Validates: Requirements 6.8** (REQ-TIMING-8)
  - [x] 4.7 Write property test for classification scale invariance
    - Factors that are multiples of 0.25 from 1.25 to 8.0, `k` from 1 to 1,000; keep scaled values within the 2^40 cap
    - **Property 10: Classification is scale invariant**
    - **Validates: Requirements 6.10** (REQ-TIMING-10)

- [x] 5. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Implement event rules and the Calibrator
  - [x] 6.1 Implement the internal event rules
    - `lib/src/internal/event_rules.dart`, not exported, top-level functions only: `firstEventViolation(events)` with the REQ-EVENT-3 precedence per index (range, starts with release, two presses, two releases, decreasing) and `endsWithPress` only after the loop; `pairPresses(events)`
    - Read-only on the input list
    - _Requirements: REQ-EVENT-3, REQ-EVENT-5, REQ-EVENT-6, REQ-BATCH-1, REQ-CAL-5_
  - [x] 6.2 Implement `RejectionReason`, `CalibrationRejection` and `CalibrationResult`
    - Enum in REQ-CAL-12 precedence order; `CalibrationRejection(reason, message)` with `toString()` returning `message`; `CalibrationResult.accepted` / `.rejected` with `isAccepted`
    - Export all three
    - _Requirements: REQ-CAL-3, REQ-CAL-12, REQ-CAL-13, REQ-CAL-31_
  - [x] 6.3 Implement `Calibrator`
    - `lib/src/calibrator.dart`: `defaultWord = 'PARIS'`, `Calibrator([TimingConfig? config])`, `calibrate(events, {word})` running the nine design steps in order: word check (UTF-16 units, the seven REQ-CAL-3 rules in order), expected plan via `CodeTable.codeFor`, event check (`invalidEvents` with index and rule phrase), debounce, count (`wrongPressCount` message with expected and received counts), dit/dah then gap separation, medians rounded half up with the overflow-safe midpoint, zero check, accept
    - Never throws; messages contain no timestamps, durations or Symbols
    - Export it
    - _Requirements: REQ-CAL-1, REQ-CAL-2, REQ-CAL-3, REQ-CAL-5, REQ-CAL-6, REQ-CAL-7, REQ-CAL-8, REQ-CAL-9, REQ-CAL-10, REQ-CAL-11, REQ-CAL-12, REQ-CAL-13, REQ-CAL-20, REQ-CAL-30, REQ-CAL-31, REQ-EVENT-2, REQ-EVENT-5, REQ-EVENT-6_
  - [x] 6.4 Write unit tests for `Calibrator`
    - `test/calibrator_test.dart`: REQ-CAL-1, REQ-CAL-3 (one test per rule, and an invalid sequence with an empty word giving `unsuitableWord`), -4, -5 (one bounce press removed), -8 (message contains 14 and 13), -9, -10, -11, -12, -13, -16, -20, -21, -30 (`d = 0`, zero-length dit), -31
    - _Requirements: REQ-CAL-1, REQ-CAL-3, REQ-CAL-4, REQ-CAL-5, REQ-CAL-8, REQ-CAL-9, REQ-CAL-10, REQ-CAL-11, REQ-CAL-12, REQ-CAL-13, REQ-CAL-16, REQ-CAL-20, REQ-CAL-21, REQ-CAL-30, REQ-CAL-31_
  - [x] 6.5 Write property test for the calibration round trip
    - Add `idealTiming(text, cal, factor, start)` to the oracles and `suitableWord()` (inserts `A`, random ASCII case) to the generators; `d ≤ min(dit, symbolGap)`
    - **Property 4: Calibration round trip**
    - **Validates: Requirements 4.2, 4.5, 5.2, 5.11** (REQ-CAL-2, REQ-CAL-6, REQ-CAL-15, REQ-CAL-20)
  - [x] 6.6 Write property test for rejection order and totality
    - Add `referenceValidate` (collect-all-violations shape) and `referenceCalibrate` to the oracles; add `unsuitableWord()` and `calibrationKeying(word, cal)` to the generators; assert the caller's list equals its pre-call copy
    - **Property 5: Calibrator follows the rejection order and never throws**
    - **Validates: Requirements 4.3, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.14, 1.2, 1.6** (REQ-CAL-3, -7, -8, -9, -10, -11, -12, -31, REQ-EVENT-2, REQ-EVENT-6)

- [x] 7. Implement the Batch_Decoder
  - [x] 7.1 Implement `BatchDecoder`
    - `lib/src/batch_decoder.dart`: constructor throws `debounceTimeTooLong` when Debounce_Time > Dit_Length or > Symbol_Gap (equal accepted); `decode` runs `firstEventViolation` before any debounce, then `pairPresses`, `Debouncer`, gap and press classification, letter flushing via `DecodedItem.fromSymbols`, Word_Space only between two letters; returns `List.unmodifiable`
    - Export it
    - _Requirements: REQ-BATCH-1, REQ-BATCH-2, REQ-BATCH-3, REQ-BATCH-4, REQ-EVENT-2, REQ-EVENT-3, REQ-EVENT-5, REQ-EVENT-6, REQ-TIMING-9_
  - [x] 7.2 Write unit tests for `BatchDecoder`
    - `test/batch_decoder_test.dart`: REQ-BATCH-3, -4 (empty input, all presses debounced away), -5 (`SOS`), -6 (`HI THERE`), -7, -10, -11, -12; REQ-DEBOUNCE-13 (empty at `d = 30,000`, `E` at `d = 10,000`)
    - _Requirements: REQ-BATCH-3, REQ-BATCH-4, REQ-BATCH-5, REQ-BATCH-6, REQ-BATCH-7, REQ-BATCH-10, REQ-BATCH-11, REQ-BATCH-12, REQ-DEBOUNCE-13_
  - [x] 7.3 Write property test for bounce never becoming a Symbol
    - Add `validEvents(cal, cfg)` (durations 0 to 10,000,000, negative starts, last event within 2^52) and `decoderConfig(cal)`; count the 10 percent short-duration share (REQ-PBT-8)
    - **Property 3: Bounce never becomes a Symbol**
    - **Validates: Requirements 3.6, 7.1** (REQ-DEBOUNCE-9, REQ-BATCH-1)
  - [x] 7.4 Write property test for jitter tolerance of batch decoding
    - Add `jitteredText(cal)`; draw the Calibration from `wellSeparated(min: 1000)`
    - **Property 11: Jittered keying decodes to the text**
    - **Validates: Requirements 7.8, 7.2** (REQ-BATCH-8, REQ-BATCH-2)
  - [x] 7.5 Write property test for batch scale invariance
    - Add `marginScenario()`: values ≥ 1,000 µs; raw durations more than 1 percent and post-debounce durations (merged Presses, Gaps containing a dropped Press) more than 2 percent from `d` and every threshold; bounce only when `d ≥ 1,011`; `k` from 0.25 to 4; scaled Calibration within the 2^40 cap
    - **Property 12: Batch decoding is scale invariant**
    - **Validates: Requirements 7.9** (REQ-BATCH-9)
  - [x] 7.6 Write property test for batch output against the reference decoder
    - Add `referenceDecode` to the oracles
    - **Property 13: Batch output matches the reference decoder and is well formed**
    - **Validates: Requirements 7.1, 7.3, 7.4, 1.2** (REQ-BATCH-1, REQ-BATCH-3, REQ-BATCH-4, REQ-EVENT-2)
  - [x] 7.7 Write property test for invalid-sequence rejection
    - Add `corrupted(events)` (1 to 3 edits: swap a kind, drop an event, lower a timestamp, push a timestamp just past ±2^52, append a press); compare kind and index with `referenceValidate`; assert the input is unchanged
    - **Property 14: Invalid sequences are rejected at the lowest index**
    - **Validates: Requirements 1.3, 1.5, 1.6** (REQ-EVENT-3, REQ-EVENT-5, REQ-EVENT-6)

- [x] 8. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Implement the Live_Decoder
  - [x] 9.1 Implement `LiveDecoder`
    - `lib/src/live_decoder.dart`: same `debounceTimeTooLong` check as `BatchDecoder`; getters `items` (unmodifiable view), `partialSequence`, `isPressed`, `latestTimestamp`
    - Validate before mutating in every call: range, `timestamp < latest` (`decreasingTimestamp`), press while pressed (`twoPressesInARow`), release while not pressed (`startsWithRelease` when no event accepted yet, else `twoReleasesInARow`); `press`/`release` errors carry the accepted-event count as index, `advanceTo` errors carry none (T9)
    - `press`: merge when `t − pendingEnd < d`, else `_settle(t)`; `release`: record pending end, confirm nothing; `advanceTo`: record only while pressed, else `_settle`
    - `_settle`: confirm or discard the pending press once `now − end ≥ d`; complete the letter when no Pending_Press exists and `now − r ≥ letterGapThreshold`, or when the Pending_Press's press timestamp minus `r` is at least `letterGapThreshold` (REQ-LIVE-6)
    - `_appendKept`: flush on a between-letters Gap, Word_Space only when the Partial_Sequence is empty, items are non-empty and the Gap reaches `wordGapThreshold`; silence never adds a Word_Space
    - Export it
    - _Requirements: REQ-LIVE-1, REQ-LIVE-2, REQ-LIVE-3, REQ-LIVE-4, REQ-LIVE-5, REQ-LIVE-6, REQ-LIVE-7, REQ-LIVE-8, REQ-LIVE-9, REQ-LIVE-10, REQ-LIVE-14, REQ-EVENT-5, REQ-TIMING-9_
  - [x] 9.2 Write unit tests for `LiveDecoder`
    - `test/live_decoder_test.dart`: REQ-LIVE-2 (fresh state; reads do not mutate), -3, -5, -6 (both branches, including a dah held across the Letter_Gap_Threshold staying in its letter), -7, -8, -9 (each rule, state unchanged), -10, -12, -13, -14
    - _Requirements: REQ-LIVE-2, REQ-LIVE-3, REQ-LIVE-5, REQ-LIVE-6, REQ-LIVE-7, REQ-LIVE-8, REQ-LIVE-9, REQ-LIVE-10, REQ-LIVE-12, REQ-LIVE-13, REQ-LIVE-14_
  - [x] 9.3 Write unit tests for switch-event validation across all consumers
    - `test/switch_event_test.dart`: REQ-EVENT-3 one case per rule plus precedence at one index; REQ-EVENT-4 phrases unique across `TimingInputErrorKind.values` and messages carry the index; REQ-EVENT-5 at ±(2^52 + 1) for batch, calibrator and live, and ±2^52 accepted; REQ-EVENT-6 input unchanged for batch and calibrator
    - _Requirements: REQ-EVENT-3, REQ-EVENT-4, REQ-EVENT-5, REQ-EVENT-6_
  - [x] 9.4 Write unit tests for the decoder Debounce_Time limit
    - Add to `test/classifier_test.dart`: REQ-TIMING-9 for both `BatchDecoder` and `LiveDecoder` (`d = dit` and `d = symbolGap` accepted, one more rejected with `debounceTimeTooLong`)
    - _Requirements: REQ-TIMING-9_
  - [x] 9.5 Write property test for live and batch equivalence
    - Add `liveScenario()` and `liveOracleTrace`; final `advanceTo(lastRelease + max(d, letterGapThreshold))`; check every intermediate state; counters assert at least 100 counted cases and at least 10 percent with `advanceTo` calls (REQ-PBT-1, REQ-PBT-8)
    - **Property 15: Live decoding equals batch decoding**
    - **Validates: Requirements 8.3, 8.4, 8.7, 8.8, 8.11** (REQ-LIVE-3, -4, -7, -8, -11)
  - [x] 9.6 Write property test for invalid live calls
    - Valid prefix plus one invalid call; state unchanged; continuing gives the same result as a decoder that never saw the call
    - **Property 16: Invalid live calls change nothing**
    - **Validates: Requirements 8.9, 1.5** (REQ-LIVE-9, REQ-EVENT-5)
  - [x] 9.7 Write property test for determinism
    - Two new instances of each of `Debouncer`, `Classifier`, `Calibrator`, `BatchDecoder`, `LiveDecoder` given the same calls return equal results or the same error kind and index; test name begins `REQ-ENGINE-2`
    - **Property 17: Determinism**
    - **Validates: Requirements 9.2** (REQ-ENGINE-2)
  - [x] 9.8 Write property test for message privacy
    - Reuse the Property 5, 14 and 16 generators shifted so every timestamp is ≥ 1,000,000 and differs from every index; test name begins `REQ-ENGINE-5 REQ-EVENT-4 REQ-CAL-13`
    - **Property 18: Messages leak no input**
    - **Validates: Requirements 1.4, 5.9, 9.5** (REQ-EVENT-4, REQ-CAL-13, REQ-ENGINE-5)

- [x] 10. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 11. Replace the public-API test and add the structure and privacy tests
  - [x] 11.1 Replace the REQ-PURE-6 public-API list with the REQ-ENGINE-4 list
    - In `test/purity_test.dart`, replace `_publicApi` with `_publicTypes`, the 23 names: the 4 morse-core classes and the 19 timing types
    - Add `REQ-ENGINE-4 REQ-PURE-6 lib/morse_core.dart exports exactly the public API`: collect the public classes and enums of every exported file and assert the set equals `_publicTypes`; add a self-check on a planted extra export
    - Update the REQ-PURE-6 description and `example/` tests to require only that the names used are a subset of `_publicTypes`; update the REQ-PURE-7 scanner check to expect `_publicTypes`
    - Add a REQ-PURE-5 assertion that `lib/morse_core.dart` exports nothing under `src/internal/`
    - Remove every check of the old four-class list
    - _Requirements: REQ-ENGINE-3, REQ-ENGINE-4, REQ-PBT-7_
  - [x] 11.2 Add the REQ-ENGINE-1, REQ-ENGINE-2, REQ-ENGINE-5 and REQ-DEBOUNCE-2 source scans
    - `REQ-ENGINE-1`: the REQ-PURE-1 import rules on every file under `lib/` recursively, and `pubspec.yaml` lists no `dependencies`; self-check on a planted forbidden import
    - `REQ-ENGINE-2`: the existing impure-identifier and mutable-global scans applied to every timing file, including `lib/src/internal/`
    - `REQ-ENGINE-5`: no `print(`, `dart:developer`, `log(`, `stdout` or `stderr` in any timing file; self-check on each planted violation
    - `REQ-DEBOUNCE-2`: after stripping comments and strings, no numeric literal ≥ 1,000 (decimal or hex) in `debouncer.dart`, `classifier.dart`, `calibrator.dart`, `batch_decoder.dart`, `live_decoder.dart`; `30000` and `2.0` appear in `timing_config.dart` only; self-check on planted `30000` and `0x100000`
    - _Requirements: REQ-ENGINE-1, REQ-ENGINE-2, REQ-ENGINE-5, REQ-DEBOUNCE-2, REQ-PBT-7_
  - [x] 11.3 Add the REQ-ENGINE-3, REQ-ENGINE-6, REQ-ENGINE-8 and REQ-PBT-3 meta-tests
    - `REQ-ENGINE-3`: every timing type in `_publicTypes` has its `snake_case.dart` file in `lib/src/` and is reachable through the single public import
    - `REQ-ENGINE-6`: every public declaration in a timing file, including enum values, has a `///` comment citing an ID from either requirement set
    - `REQ-ENGINE-8 REQ-PBT-3`: using `_testNames`, every ID listed in REQ-PBT-1, REQ-PBT-2, REQ-PBT-6 and REQ-PBT-7, and each of REQ-ENGINE-1 to REQ-ENGINE-6, begins at least one test name
    - _Requirements: REQ-ENGINE-3, REQ-ENGINE-6, REQ-ENGINE-8, REQ-PBT-3_

- [x] 12. Final checkpoint - Ensure all tests pass
  - Run `cd packages/morse_core && dart analyze` (zero errors and warnings, REQ-ENGINE-7) and `dart test` (zero failures, errors and skips, under 60 seconds, REQ-PBT-5).
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional test sub-tasks. Task 11 is not optional: REQ-PBT-7 and REQ-ENGINE-8 are met only by those tests. If optional tasks are skipped, task 11.3 fails until the tests for every ID listed in REQ-PBT-1, REQ-PBT-2 and REQ-PBT-6 exist, so the optional tests are needed to complete the spec.
- The oracles in `test/support/timing_oracles.dart` and the generators in `test/support/timing_arbitraries.dart` grow with the property tasks. A property task that runs before the one that normally adds a helper adds that helper itself.
- Each property test uses seed `(100 + N) * 1000 + 3`, `maxExamples: 200`, and generate-to-satisfy generators (no `.filter`, no early `return`), so every generated case counts toward REQ-PBT-1's 100.
- Each property test carries the comment `// Feature: adaptive-timing, Property N: <title>`.
- Tasks 1.1 and 1.2 must land before any timing file exists; otherwise the existing REQ-PURE-4 and REQ-PURE-7 tests fail on the first enum or the first new requirement ID.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2"] },
    { "id": 2, "tasks": ["2.1"] },
    { "id": 3, "tasks": ["2.2"] },
    { "id": 4, "tasks": ["2.3"] },
    { "id": 5, "tasks": ["2.4", "2.5"] },
    { "id": 6, "tasks": ["2.6", "3.1"] },
    { "id": 7, "tasks": ["3.2", "3.3"] },
    { "id": 8, "tasks": ["3.4", "4.1"] },
    { "id": 9, "tasks": ["4.2", "4.3"] },
    { "id": 10, "tasks": ["4.4"] },
    { "id": 11, "tasks": ["4.5"] },
    { "id": 12, "tasks": ["4.6"] },
    { "id": 13, "tasks": ["4.7"] },
    { "id": 14, "tasks": ["5"] },
    { "id": 15, "tasks": ["6.1", "6.2"] },
    { "id": 16, "tasks": ["6.3"] },
    { "id": 17, "tasks": ["6.4", "6.5"] },
    { "id": 18, "tasks": ["6.6"] },
    { "id": 19, "tasks": ["7.1"] },
    { "id": 20, "tasks": ["7.2", "7.3"] },
    { "id": 21, "tasks": ["7.4"] },
    { "id": 22, "tasks": ["7.5"] },
    { "id": 23, "tasks": ["7.6"] },
    { "id": 24, "tasks": ["7.7"] },
    { "id": 25, "tasks": ["8"] },
    { "id": 26, "tasks": ["9.1"] },
    { "id": 27, "tasks": ["9.2", "9.3", "9.4", "9.5"] },
    { "id": 28, "tasks": ["9.6"] },
    { "id": 29, "tasks": ["9.7"] },
    { "id": 30, "tasks": ["9.8"] },
    { "id": 31, "tasks": ["10"] },
    { "id": 32, "tasks": ["11.1"] },
    { "id": 33, "tasks": ["11.2"] },
    { "id": 34, "tasks": ["11.3"] },
    { "id": 35, "tasks": ["12"] }
  ]
}
```
