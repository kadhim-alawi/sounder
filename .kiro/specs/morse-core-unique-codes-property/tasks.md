# Implementation Plan

Scope: only the REQ-CODE-4 `property(...)` block (and its preceding comment) in `packages/morse_core/test/properties_test.dart` changes. `lib/src/code_table.dart` is edited only for the temporary `E` to `'..'` mutation, which is always reverted and verified byte-identical by SHA-256 hash. `test/support/arbitraries.dart`, every other file under `lib/`, `pubspec.yaml`, `pubspec.lock` and the morse-core spec are not edited. All commands run from `packages/morse_core`.

- [x] 1. Run bug condition exploration against the unfixed REQ-CODE-4 property
  - **Property 1: Bug Condition** - A code collision fails REQ-CODE-4
  - **CRITICAL**: The expected property (REQ-CODE-4 fails on a collision table) MUST NOT hold on the unfixed test: REQ-CODE-4 passing under the mutation confirms the bug exists
  - **DO NOT attempt to fix the test or the code in this task**
  - **NOTE**: In this bugfix the property under test is REQ-CODE-4 itself, so the exploration input is a collision table produced by mutation, and the fixed REQ-CODE-4 written in task 3.1 encodes the expected behavior
  - **Scoped PBT Approach**: The bug is deterministic under seed 1003, so scope it to the concrete collision table `E` = `'..'` (collides with `I`)
  - Bug condition from design: `isBugCondition(X)` = EXISTS a != b IN keys(X) WITH X[a] == X[b] AND REQ-CODE-4 passes under seed 1003
  - Expected behavior from design: for every sampled `c` with `asciiUpper(c)` in {E, I}, the count of `CodeTable.codes` entries whose code equals `codeFor(c)` is not 1, so REQ-CODE-4 fails
  - Record baseline: `Get-FileHash lib/src/code_table.dart -Algorithm SHA256` and `git status --short` for `packages/morse_core`
  - Temporarily change `'E': '.',` to `'E': '..',` in `lib/src/code_table.dart`
  - Run `dart test test/properties_test.dart` (or the full `dart test`) on the UNFIXED `properties_test.dart`
  - **EXPECTED OUTCOME**: REQ-CODE-4 PASSES while other tests fail (the original run saw 5 failures), which confirms the bug
  - Document the counterexample: the `E`/`I` collision table, the REQ-CODE-4 pass, the names of the failing tests, and the cause (neither `(E, I)` nor `(I, E)` is among the 200 sampled pairs; miss chance (902/903)^200 ≈ 0.80)
  - Revert the mutation (`git checkout -- lib/src/code_table.dart` if the file was committed and clean at baseline, otherwise restore the line by hand), then re-run `Get-FileHash` and confirm it equals the baseline
  - Mark complete when the run is done, the result is documented, and the hash matches
  - _Requirements: 1.1, 1.2, 1.3, 2.4, 3.5_

- [x] 2. Record preservation baseline on the unfixed code (BEFORE implementing the fix)
  - **Property 2: Preservation** - Correct table and the rest of the suite are unchanged
  - **IMPORTANT**: Follow observation-first methodology on the unmodified, correct code table (where `isBugCondition` is false)
  - Run `dart test` and record every test name and outcome: REQ-CODE-4 (seed 1003), REQ-CODE-5/7/8 Property 2 (seed 2003), REQ-CODE-9 Property 3 (seed 3003), `code_table_test.dart`, `errors_test.dart`; note that none is skipped
  - Run `dart analyze` and record zero errors and zero warnings
  - Confirm no file in `packages/morse_core` imports Flutter
  - The preservation properties are the existing property-based tests (Properties 2 and 3) plus the REQ-CODE-4 pass on the correct table; no new test is written here and no test file is edited
  - **EXPECTED OUTCOME**: All tests PASS and the analyzer is clean on unfixed code (baseline to preserve)
  - Mark complete when the baseline names, outcomes and analyzer result are recorded
  - _Requirements: 3.1, 3.6, 3.7_

- [x] 3. Fix the REQ-CODE-4 uniqueness property

  - [x] 3.1 Rewrite the REQ-CODE-4 property block in `test/properties_test.dart`
    - Replace the comment above the block with: `Feature: morse-core, Property 1: for any Supported_Character c, exactly one entry of CodeTable.codes has the code codeFor(c). Changed by bugfix spec morse-core-unique-codes-property.`
    - Remove `final keys = table.codes.keys.toList();` and the `combine2(...).filter(...)` pair arbitrary
    - Use `forAll(supportedChar(), (c) { ... })` with the existing, unchanged `supportedChar()` from `support/arbitraries.dart`; do not enumerate keys in place of sampling
    - In the callback: `final code = table.codeFor(c);` then `expect(code, isNotNull, reason: 'codeFor($c) is null');`
    - Count over all of `table.codes.entries` the keys whose value equals `code`, and `expect(sharing.length, equals(1), reason: ...)` with a reason naming `c`, its code, the count and the sharing keys
    - Keep the test name `'REQ-CODE-4 codes are unique'`, `maxExamples: 200`, `seed: 1003`, `onFalsify: report(1003)`
    - Do not touch Properties 2 and 3, the imports or `const CodeTable table`; no other file changes
    - _Bug_Condition: isBugCondition(X) where two distinct keys of X share a code and REQ-CODE-4 still passes under seed 1003_
    - _Expected_Behavior: Property 1 from design: for each sampled c whose upper form is a colliding key, the sharing count is not 1, so REQ-CODE-4 fails and reports via report(1003)_
    - _Preservation: Preservation Requirements from design (3.1 to 3.7)_
    - _Requirements: 2.1, 2.2, 2.5, 3.2, 3.3, 3.4, 3.5_

  - [x] 3.2 Verify the fixed property detects the `E` to `'..'` mutation
    - **Property 1: Expected Behavior** - A code collision fails REQ-CODE-4
    - **IMPORTANT**: Use the SAME mutation as task 1 and the SAME fixed property from task 3.1; do not write a new test
    - Record the baseline hash: `Get-FileHash lib/src/code_table.dart -Algorithm SHA256` (must equal the task 1 baseline)
    - Temporarily change `'E': '.',` to `'E': '..',` and run `dart test`
    - **EXPECTED OUTCOME**: REQ-CODE-4 FAILS; its output contains `Falsifying example: <c>, seed: 1003` with `c` in `E`, `e`, `I`, `i`, and the reason `codeFor(<c>) is "..", shared by 2 entries: E I`. Other tests failing as well is expected
    - **If REQ-CODE-4 passes under the mutation, STOP**: revert the mutation, verify the hash, and report the result to the user. Do NOT change seed 1003 or `maxExamples` to force a failure
    - Revert the mutation (`git checkout -- lib/src/code_table.dart` if it was clean at baseline, otherwise restore by hand)
    - Re-run `Get-FileHash` and confirm it equals the baseline; confirm `git status` shows no change under `lib/` or to `pubspec.yaml` / `pubspec.lock`
    - _Requirements: 2.1, 2.3, 2.4, 2.5, 3.5_

  - [x] 3.3 Verify preservation after the fix
    - **Property 2: Preservation** - Correct table and the rest of the suite are unchanged
    - **IMPORTANT**: Re-run the SAME checks from task 2; do not write new tests
    - With the mutation reverted, run `dart test` and compare names and outcomes to the task 2 baseline: REQ-CODE-4 passes on the correct table, Properties 2 (seed 2003) and 3 (seed 3003), `code_table_test.dart` and `errors_test.dart` pass with the same names and seeds, none skipped
    - Run `dart analyze`: zero errors, zero warnings; no Flutter imports
    - Confirm `git status` shows only `test/properties_test.dart` modified under `packages/morse_core`
    - **EXPECTED OUTCOME**: All tests PASS and the analyzer is clean (no regressions)
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 4. Checkpoint - Ensure all tests pass
  - Run `cd packages/morse_core && dart test`: all tests pass, none skipped
  - Run `cd packages/morse_core && dart analyze`: no errors, no warnings
  - Confirm the `lib/src/code_table.dart` SHA-256 hash equals the baseline from task 1
  - Ensure all tests pass, ask the user if questions arise
  - _Requirements: 2.4, 3.5, 3.6, 3.7_
