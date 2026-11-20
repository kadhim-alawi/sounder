# morse-core-unique-codes-property Bugfix Design

## Overview

The REQ-CODE-4 property in `packages/morse_core/test/properties_test.dart` ("REQ-CODE-4 codes are unique") checks uniqueness by sampling 200 ordered pairs of distinct keys from the 43 keys of `CodeTable.codes`. A single collision is visible in only 2 of the 1,806 ordered pairs, so the property misses it about 80% of the time. A real mutation (`E` changed from `.` to `..`, the code of `I`) made 5 other tests fail while REQ-CODE-4 passed.

The fix is confined to that one test. The property will draw one Supported_Character `c` per case with the existing `supportedChar()` generator and assert that exactly one entry of `CodeTable.codes` has the code `codeFor(c)`. Each case scans the whole table, so any collision is caught as soon as either colliding character, or its lowercase form, is drawn. The test name prefix, `maxExamples: 200`, `seed: 1003` and `onFalsify: report(1003)` stay as they are. Production code, pubspec files and `test/support/arbitraries.dart` are not touched.

The morse-core design (Property 1) and tasks (task 4.3) already describe the per-character check and reference this spec. This design plans no further changes to them.

## Glossary

- **Bug_Condition (C)**: The code table `X` contains two distinct keys `a` and `b` with `X[a] == X[b]`, and the REQ-CODE-4 property passes anyway.
- **Property (P)**: For every table where a collision exists, the REQ-CODE-4 property fails under seed 1003 and reports the character, its code and the number of entries sharing that code.
- **Preservation**: For the correct ITU table, which has no collisions, REQ-CODE-4 passes, and every other test, `dart analyze` result and non-test file is unchanged.
- **Supported_Character**: One of the 43 uppercase keys of `CodeTable.codes` or a lowercase letter `a`-`z` (69 characters in total).
- **`CodeTable`**: The class in `packages/morse_core/lib/src/code_table.dart`. `codes` is the 43-entry const map `_codes`; `codeFor(c)` returns the code for a one-character string, folding `a`-`z` to `A`-`Z`, or null.
- **`supportedChar()`**: The generator in `packages/morse_core/test/support/arbitraries.dart`, `constantFrom<String>(_supportedChars)`, which draws one of the 69 Supported_Characters per case. It is built from the ITU fixture, not from `lib/`.
- **`report(seed)`**: The `onFalsify` helper in `arbitraries.dart`; it calls `printOnFailure('Falsifying example: $x, seed: $seed')`.
- **`property` / `forAll`**: The `kiri_check` API already used in `properties_test.dart`: `property(name, body)` defines a test, and `forAll(arbitrary, check, maxExamples:, seed:, onFalsify:)` runs it.

## Bug Details

### Bug Condition

The bug manifests when the code table contains a collision. The current property only fails if the sampler draws one of the two ordered pairs `(a, b)` or `(b, a)` among its 200 cases. With 1,806 ordered pairs, a collision is detected only by chance: the miss probability is (902/903)^200 ≈ 0.80.

**Formal Specification:**
```
FUNCTION isBugCondition(X)
  INPUT: X of type Map<String, String>   // the code table under test
  OUTPUT: boolean

  RETURN EXISTS a, b IN keys(X) WHERE a != b AND X[a] == X[b]
         AND REQ_CODE_4_property_passes(X, seed = 1003)
END FUNCTION
```

The first two lines define the collision tables. On the unfixed test, most collision tables satisfy the whole condition; the fix must make the condition false for every collision table.

### Examples

- `E` mutated to `..` (collides with `I`). Expected: REQ-CODE-4 fails. Actual on the unfixed test: REQ-CODE-4 passes; 5 other tests fail, so the suite does not attribute the failure to REQ-CODE-4.
- `T` mutated to `--` (collides with `M`). Expected: REQ-CODE-4 fails. Actual: passes about 80% of the time, depending on whether `(T, M)` or `(M, T)` is drawn.
- `(` mutated to `-.--.-` (collides with `)`). Expected: REQ-CODE-4 fails. Actual: same 80% miss rate. After the fix this is the worst case, because only `(` and `)` expose it (2 of 69 characters, no lowercase forms).
- Correct ITU table (no collision). Expected and actual: REQ-CODE-4 passes. This must stay true.

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- REQ-CODE-4 passes against the current, correct code table (3.1).
- The test name still starts with `REQ-CODE-4`; it stays `'REQ-CODE-4 codes are unique'` (3.2).
- The property still uses one `forAll` with `maxExamples: 200`, `seed: 1003` and `onFalsify: report(1003)` (3.3).
- The input still comes from an existing generator, `supportedChar()`, without changing `arbitraries.dart` and without enumerating keys in place of sampling (3.4).
- `lib/src/code_table.dart`, every other file under `lib/`, `pubspec.yaml` and `pubspec.lock` are unchanged (3.5).
- Properties 2 and 3, `code_table_test.dart` and `errors_test.dart` keep their names, seeds and results; nothing is skipped (3.6).
- `dart analyze` reports zero errors and zero warnings; no file imports Flutter (3.7).

**Scope:**
Only the body and the preceding comment of the REQ-CODE-4 `property(...)` block in `properties_test.dart` change. Everything else is unaffected, including:
- Properties 2 (seed 2003) and 3 (seed 3003) in the same file, and the file's imports and `const CodeTable table`.
- `test/support/*.dart`, `test/code_table_test.dart`, `test/errors_test.dart`.
- All of `lib/`, `pubspec.yaml`, `pubspec.lock`.

## Hypothesized Root Cause

1. **Pair sampling dilutes the signal**: The uniqueness check compares one sampled pair per case. A collision lives in 2 of 1,806 ordered pairs, so 200 cases cover about 11% of the pair space and miss the collision about 80% of the time.
   - `combine2(constantFrom(keys), constantFrom(keys)).filter((pair) => pair.$1 != pair.$2)` draws pairs uniformly; nothing biases it toward colliding pairs.
   - The check `codes[a] != codes[b]` only sees the two sampled entries, never the rest of the table.

2. **The generator is built from `lib/`**: `keys` comes from `table.codes.keys`, not the ITU fixture. This does not cause the miss, but it differs from the convention in `arbitraries.dart` that generators are built from the fixture. Using `supportedChar()` restores that convention.

3. **No per-requirement mutation check**: The property was never run against a collision table, so its low detection rate went unnoticed until the `E` mutation run.

## Correctness Properties

Property 1: Bug Condition - A code collision fails REQ-CODE-4

_For any_ code table where the bug condition holds (two distinct keys share a code), the fixed REQ-CODE-4 property SHALL fail for every sampled Supported_Character `c` that is either colliding key or its lowercase form, because the number of entries of `CodeTable.codes` whose code equals `codeFor(c)` is not exactly 1. Under seed 1003 with the `E` to `..` mutation, the property SHALL fail and its failure output SHALL name the character, its code, the count of sharing entries, and the seed via `report(1003)`.

**Validates: Requirements 2.1, 2.2, 2.3, 2.5**

Property 2: Preservation - Correct table and the rest of the suite are unchanged

_For any_ code table where the bug condition does NOT hold (the correct ITU table), the fixed REQ-CODE-4 property SHALL pass, and the rest of the suite SHALL produce the same results as before the fix, with the same test names, seeds, generator, `kiri_check` settings, unchanged `lib/` and pubspec files, and a clean `dart analyze`.

**Validates: Requirements 2.4, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**

## Fix Implementation

### Changes Required

**File**: `packages/morse_core/test/properties_test.dart`

**Block**: the first `property('REQ-CODE-4 codes are unique', ...)` in `main()`

**Specific Changes**:
1. **Update the property comment** to the new statement, matching the morse-core design:
   ```dart
   // Feature: morse-core, Property 1: for any Supported_Character c, exactly
   // one entry of CodeTable.codes has the code codeFor(c). Changed by bugfix
   // spec morse-core-unique-codes-property.
   ```

2. **Replace the pair generator with `supportedChar()`**: remove `final keys = table.codes.keys.toList();` and the `combine2(...).filter(...)` arbitrary. `supportedChar()` is already imported through `support/arbitraries.dart`.

3. **Replace the check with a whole-table count**:
   ```dart
   property('REQ-CODE-4 codes are unique', () {
     forAll(
       supportedChar(),
       (c) {
         final code = table.codeFor(c);
         expect(code, isNotNull, reason: 'codeFor($c) is null');
         final sharing = table.codes.entries
             .where((entry) => entry.value == code)
             .map((entry) => entry.key)
             .toList();
         expect(sharing.length, equals(1),
             reason: 'codeFor($c) is "$code", shared by '
                 '${sharing.length} entries: ${sharing.join(' ')}');
       },
       maxExamples: 200,
       seed: 1003,
       onFalsify: report(1003),
     );
   });
   ```
   This follows the shape of Property 2 in the same file: a single-argument callback, `expect(..., reason: ...)`, and the same named arguments to `forAll`. The reason names the character, its code and the count (2.5); listing the sharing keys adds context at no cost.

4. **Keep everything else as is**: test name, `maxExamples: 200`, `seed: 1003`, `onFalsify: report(1003)`, imports, Properties 2 and 3.

5. **No other files change.** `lib/src/code_table.dart` is edited only temporarily during the mutation check and is restored byte-for-byte.

### Mutation verification procedure

Run from `packages/morse_core`:
1. Record a baseline: `Get-FileHash lib/src/code_table.dart -Algorithm SHA256`.
2. Change `'E': '.',` to `'E': '..',` in `lib/src/code_table.dart`. The map stays a valid const map because keys are still distinct.
3. Run `dart test`. Confirm the REQ-CODE-4 test is among the failures and its output contains `Falsifying example: <c>, seed: 1003` with `c` in `E`, `e`, `I`, `i`, and the reason `codeFor(<c>) is "..", shared by 2 entries: E I`. Other tests (for example the ITU fixture comparison and Property 2 round trip) are expected to fail too.
4. Revert the edit, preferably with `git checkout -- lib/src/code_table.dart` if the file is committed and was clean before step 2; otherwise restore the original line by hand.
5. Re-run `Get-FileHash` and confirm the hash equals the baseline. Also confirm `git status` shows no change to `lib/`, `pubspec.yaml` or `pubspec.lock`.

If seed 1003 happens not to draw any of `E`, `e`, `I`, `i` in 200 cases (probability about 7 × 10^-6 for a random seed), the property will pass under the mutation. Requirement 3.3 fixes the seed, so the seed must not be changed to force a failure. In that case stop and report the result to the user.

## Testing Strategy

### Validation Approach

First confirm on the unfixed test that the `E` collision goes undetected under seed 1003. Then apply the fix, confirm the same mutation is detected, revert the mutation, and confirm the full suite and analyzer are unchanged.

### Exploratory Bug Condition Checking

**Goal**: Show the miss on the unfixed test before changing it, which confirms root cause 1.

**Test Plan**: With the unfixed `properties_test.dart`, apply the `E` to `..` mutation (procedure steps 1-2) and run `dart test test/properties_test.dart`. Revert and check the hash afterwards.

**Test Cases**:
1. **E/I collision, unfixed test**: REQ-CODE-4 passes while other tests fail (the original run saw 5 failures), reproducing the reported miss. Running the full `dart test` is also acceptable here.
2. **Pair-space arithmetic**: 2 exposing ordered pairs out of 1,806 gives a miss chance of (902/903)^200 ≈ 0.80, consistent with the observed pass.

**Expected Counterexamples**:
- None from REQ-CODE-4 itself, which is the defect: the uniqueness property passes on a table with a duplicate code.
- Cause: the colliding pair `(E, I)` or `(I, E)` is not among the 200 sampled pairs.

### Fix Checking

**Goal**: For collision tables, the fixed property fails.

**Pseudocode:**
```
FOR ALL X WHERE EXISTS a != b IN keys(X) WITH X[a] == X[b] DO
  FOR ALL c IN supportedChars WHERE asciiUpper(c) IN {a, b} DO
    ASSERT count({k IN keys(X) | X[k] == codeFor_X(c)}) == 2   // != 1, so the case fails
  END FOR
  ASSERT REQ_CODE_4_property_fails(X, seed = 1003)   // checked by the mutation run for X = E->'..'
END FOR
```

### Preservation Checking

**Goal**: For the correct table, the fixed property passes and nothing else changes.

**Pseudocode:**
```
FOR ALL c IN supportedChars DO   // sampled 200 times under seed 1003
  ASSERT codeFor(c) != null
  ASSERT count({k IN keys(codes) | codes[k] == codeFor(c)}) == 1
END FOR
ASSERT results(other tests, after fix) == results(other tests, before fix)
```

**Testing Approach**: The REQ-CODE-4 check is itself the property-based test. Preservation of the rest of the suite is checked by running the full suite before and after the change and comparing test names and outcomes.

**Test Plan**: Before editing, run `dart test` on the correct table and note the passing test names. After the fix and the reverted mutation, run it again and compare.

**Test Cases**:
1. **Correct table passes**: REQ-CODE-4 passes with seed 1003 on the unmodified table.
2. **Other tests unchanged**: Properties 2 and 3, `code_table_test.dart` and `errors_test.dart` pass with the same names and seeds; no skips.
3. **Files unchanged**: `code_table.dart` hash equals the baseline; `git status` shows only `test/properties_test.dart` modified under `packages/morse_core`.
4. **Analyzer clean**: `dart analyze` reports no errors or warnings.

### Unit Tests

- No new unit tests. The REQ-CODE-1 to REQ-CODE-3 fixture tests in `code_table_test.dart` stay as they are and must keep passing.
- The `expect(code, isNotNull, ...)` assertion inside the property covers the null case of `codeFor(c)` for every sampled character.

### Property-Based Tests

- REQ-CODE-4 (fixed): `forAll(supportedChar(), ...)`, 200 cases, seed 1003, asserting exactly one table entry per sampled character's code.
- Mutation run of REQ-CODE-4 against `E` to `..`, confirming failure under seed 1003 with the expected reason and `report(1003)` output.
- Properties 2 (seed 2003) and 3 (seed 3003) run unchanged as regression checks.

### Integration Tests

- Full suite: `cd packages/morse_core && dart test`, all tests pass after the mutation is reverted.
- Static check: `cd packages/morse_core && dart analyze`, zero errors and zero warnings.
- Byte-identity check of `lib/src/code_table.dart` against the SHA-256 baseline recorded before the mutation.
