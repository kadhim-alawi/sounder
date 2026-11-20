# Bugfix Requirements Document

## Introduction

The REQ-CODE-4 property test in `packages/morse_core/test/properties_test.dart` (Property 1, "Codes are unique") is too weak to catch a duplicate code in the code table. It samples 200 ordered pairs of distinct keys from the 43 keys of `CodeTable.codes`. When one pair of keys collides, only 2 of the 1,806 ordered pairs (1 in 903) expose the collision, so 200 samples miss it about 80% of the time ((902/903)^200 ≈ 0.80). In a real mutation run, changing `E` from `.` to `..` (the code of `I`) made 5 other tests fail while REQ-CODE-4 passed.

The defect is in the test, not in production code. The fix changes only the REQ-CODE-4 property. For each sampled Supported_Character `c` drawn with `supportedChar()`, the test asserts that exactly one entry of `CodeTable.codes` has the code `codeFor(c)`. Because each check now scans the whole table, a collision is caught whenever either colliding character is sampled.

`supportedChar()` draws from 69 characters: the 43 table keys and the lowercase letters `a`-`z`. For the `E`/`I` collision, 4 of the 69 characters (`E`, `e`, `I`, `i`) expose it, so 200 random draws would miss it with probability about (65/69)^200 ≈ 7 × 10^-6. The fixed seed 1003 makes the outcome deterministic: one run of the mutated table settles whether this seed catches the mutation. The worst case is a collision between two punctuation keys. Only 2 of the 69 characters expose it, and the miss chance for a random seed is about (67/69)^200 ≈ 0.3%. The requirements below therefore require a mutation run under seed 1003, not just the probability estimate.

Bug condition C(X): X is a code table in which two distinct keys `a` and `b` have `codes[a] == codes[b]`. Property P: for every such X, the REQ-CODE-4 property fails under seed 1003. Preservation: for the correct ITU table, which has no collisions, the property passes, and the rest of the suite behaves as it does today.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN `CodeTable.codes` contains two distinct keys with the same code (for example `E` mutated to `..`, colliding with `I`) THEN the REQ-CODE-4 property passes in most runs, because it fails only if the one colliding pair is among the 200 sampled pairs

1.2 WHEN the `E` to `..` mutation is applied and `cd packages/morse_core && dart test` is run THEN the REQ-CODE-4 property passes while other tests fail, so the suite does not attribute the failure to the uniqueness requirement

1.3 WHEN a collision exists THEN whether the REQ-CODE-4 property detects it depends on whether the pair sampler happens to draw the colliding pair, so detection is unreliable for any one collision

### Expected Behavior (Correct)

2.1 WHEN `CodeTable.codes` contains two distinct keys with the same code THEN the REQ-CODE-4 property SHALL fail for any sampled Supported_Character `c` that is either colliding key or its lowercase form, because the number of entries in `CodeTable.codes` whose code equals `codeFor(c)` is not exactly 1

2.2 WHEN the REQ-CODE-4 property checks a sampled Supported_Character `c` THEN it SHALL assert that `codeFor(c)` is non-null and that exactly one entry of `CodeTable.codes` has that code, counted over all entries of the table, not over a sampled partner key

2.3 WHEN `E` is temporarily changed from `.` to `..` in `lib/src/code_table.dart` and `cd packages/morse_core && dart test` is run with seed 1003 THEN the REQ-CODE-4 property SHALL fail, and its failure report SHALL name the falsifying character and the seed through `onFalsify: report(1003)`

2.4 WHEN the mutation check in 2.3 is complete THEN the mutation SHALL be reverted, and `lib/src/code_table.dart` SHALL be byte-for-byte identical to its state before the fix

2.5 WHEN the REQ-CODE-4 property fails THEN its failure reason SHALL name the sampled character, its code, and the number of entries that share that code

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the REQ-CODE-4 property runs against the current, correct code table THEN the system SHALL CONTINUE TO pass

3.2 WHEN the REQ-CODE-4 property is defined THEN its test name SHALL CONTINUE TO start with `REQ-CODE-4`

3.3 WHEN the REQ-CODE-4 property runs THEN it SHALL CONTINUE TO use one `forAll` with `maxExamples: 200`, `seed: 1003` and `onFalsify: report(1003)`, following the existing `kiri_check` usage in `properties_test.dart`

3.4 WHEN the REQ-CODE-4 property draws its input THEN it SHALL CONTINUE TO use an existing generator, `supportedChar()` from `test/support/arbitraries.dart`, without changing that file and without enumerating every key in place of sampling

3.5 WHEN the fix is applied THEN `lib/src/code_table.dart`, every other file under `lib/`, `pubspec.yaml` and `pubspec.lock` SHALL CONTINUE TO be unchanged

3.6 WHEN `cd packages/morse_core && dart test` is run after the fix THEN every other test (Properties 2 and 3, `code_table_test.dart` and `errors_test.dart`) SHALL CONTINUE TO pass with the same names, seeds and results, and no test is skipped

3.7 WHEN `cd packages/morse_core && dart analyze` is run after the fix THEN it SHALL CONTINUE TO report zero errors and zero warnings, and no file in `packages/morse_core` imports Flutter
