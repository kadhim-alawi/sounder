# Implementation Plan: morse-core

## Overview

This plan builds the pure Dart engine in `packages/morse_core` in the order the design sets: clean the scaffold, write the test support files, then `MorseFormatException`, `CodeTable`, `MorseEncoder` and `MorseDecoder`, then the purity and structure tests. Each class goes in its own `snake_case` file under `lib/src/` and is exported from `lib/morse_core.dart` in the same task that creates it, so the package compiles and its tests run after every step.

All work stays inside `packages/morse_core/`. No file imports Flutter. Every public declaration gets a `///` doc comment citing at least one REQ ID (REQ-PURE-7) when it is written. Every test name starts with the REQ IDs it covers (REQ-TEST-4). Every property test uses one `forAll` over a sampling generator, `maxExamples: 200`, the fixed seed `N*1000 + 3` for Property N (for example 6003 for Property 6, per D4), and `onFalsify: report(seed)` (REQ-TEST-6). No property enumerates its input space.

Commands: `cd packages/morse_core && dart test` and `cd packages/morse_core && dart analyze`. A task is done only when the tests it cites pass.

## Tasks

- [x] 1. Remove the scaffold and add the property-testing dependency
  - Delete `lib/src/morse_core_base.dart` (the `Awesome` class) and `test/morse_core_test.dart`
  - Rewrite `lib/morse_core.dart` as a library with a `///` library doc comment and no exports yet; later tasks add one export per class
  - Rewrite `example/morse_core_example.dart` to a minimal `main()` with no reference to `Awesome`; task 10.1 fills it in once the public API exists
  - Replace the `pubspec.yaml` description with one that describes only the code table, encoder, decoder and format error, for example "Pure Dart International Morse code table, encoder and decoder (ITU-R M.1677-1)."
  - Leave `dependencies` empty
  - Run `dart pub add dev:kiri_check`, confirm that `dart pub get` resolves against SDK `^3.13.5`, that `pubspec.yaml` lists `kiri_check: ^1.4.0` under `dev_dependencies`, and that `pubspec.lock` records 1.4.0
  - Confirm the `kiri_check` API used by this plan (`property`, `forAll` with `maxExamples`, `seed`, `onFalsify`, `constantFrom`, `integer`, `list`, `combine2`, `combine3`, `oneOf`, `.map`, `.filter`, `.flatMap`) with the Dart MCP server or the pub.dev API reference before writing any generator; do not guess signatures
  - Confirm `dart analyze` reports zero errors and zero warnings
  - _Requirements: REQ-PURE-1, REQ-PURE-6, REQ-PURE-8, REQ-TEST-1_

- [x] 2. Write the test support files
  - [x] 2.1 Create the ITU fixture `test/support/itu_fixture.dart`
    - A `const Map<String, String>` of the 43 entries transcribed from ITU-R M.1677-1, Part I, sections 1.1.1 to 1.1.3, exactly as in the design's Data Models tables
    - Independent of `lib/`: it must not import `package:morse_core`
    - _Requirements: REQ-TEST-3, REQ-CODE-1, REQ-CODE-2, REQ-CODE-3_

  - [x] 2.2 Create the oracles `test/support/oracles.dart`
    - `isEncodedText(String)`: direct check of the REQ-FMT-1 grammar `"" | word (" / " word)*`, `word = code (" " code)*`, using the fixture codes, not `CodeTable`
    - `normalise(String)`: ASCII uppercase of `a`-`z` only, trim spaces, collapse space runs to one space
    - `asciiUpper(String)`: maps `a`-`z` to `A`-`Z` by code unit arithmetic, leaves every other code unit unchanged
    - _Requirements: REQ-FMT-1, REQ-FMT-3, REQ-ENC-11_

  - [x] 2.3 Create the generators `test/support/arbitraries.dart`
    - `supportedChar()`, `plainText()` (alphabet with repeated `' '` so leading, trailing and repeated spaces are common, `maxLength: 40`), `encodedText()` (built from fixture codes, never from `MorseEncoder`, including the empty string and words containing `-..-.`), `unsupportedChar()` (all Unicode code points filtered to unsupported non-space, lone surrogates `0xD800`-`0xDFFF`, and the hand-picked list: tab, newline, `ı`, `ß`, `é`, `!`, `:`), `decoderAlphabetString()`, `nearMiss()` (one insert, delete or replace via `combine3`), `invalidCodeUnit()`, and `injectedInvalid()` returning one `(m, i, c)` triple per case via `flatMap`, as specified in the design table
    - A `report(int seed)` helper returning the `onFalsify` callback that calls `printOnFailure('Falsifying example: $x, seed: $seed')`
    - _Requirements: REQ-TEST-1, REQ-TEST-5, REQ-TEST-6_

  - [x] 2.4 Create the requirement ID list `test/support/requirement_ids.dart`
    - A `const Set<String>` copy of every ID defined in `.kiro/specs/morse-core/requirements.md`: REQ-CODE-1 to 10, REQ-ENC-1 to 13, REQ-DEC-1 to 10, REQ-FMT-1 to 7, REQ-ERR-1 to 12, REQ-PURE-1 to 9, REQ-TEST-1 to 7
    - A comment states that it must be updated whenever `requirements.md` changes
    - _Requirements: REQ-PURE-7, REQ-TEST-7_

- [x] 3. Implement MorseFormatException
  - [x] 3.1 Create `lib/src/morse_format_exception.dart` and export it
    - `final class MorseFormatException extends FormatException` with required named fields `requirementId`, `offending`, `position` (D1, D2)
    - The constructor passes the built message, `null` as `source`, and `position` as `offset` to `super`; it never forwards the encoder or decoder input
    - Private top-level `_message`: Token errors quote the Token in double quotes; single-character errors use `U+XXXX` (uppercase hex, at least 4 digits; a surrogate pair renders as its combined code point; a lone surrogate renders as its code unit and is never written verbatim); `/` contains both `"/"` and `U+002F`; every message contains the position in decimal; wording matches the design's example table
    - `toString()` returns `message` only
    - Add `export 'src/morse_format_exception.dart';` to `lib/morse_core.dart`
    - `///` doc comments citing REQ IDs on the class, constructor and every public field and method
    - _Requirements: REQ-ERR-8, REQ-ERR-9, REQ-PURE-2, REQ-PURE-4, REQ-PURE-5, REQ-PURE-7_

  - [x] 3.2 Write unit tests for the exception in `test/errors_test.dart`
    - Construct exceptions directly and check the four example messages from the design table, the `U+1F600` form for a surrogate pair, the `U+D800` form for a lone surrogate, `offset == position`, `source == null`, and `toString() == message`
    - Test names start with `REQ-ERR-8`
    - _Requirements: REQ-ERR-8_

- [x] 4. Implement CodeTable
  - [x] 4.1 Create `lib/src/code_table.dart` and export it
    - `final class CodeTable` with a `const` constructor
    - `codes` returns a `static const Map<String, String>` of the 43 ITU entries
    - `characters` returns a `static final` `Map.unmodifiable` reverse map derived from `codes`
    - `codeFor(String)`: null unless length is 1; folds `0x61`-`0x7A` by subtracting `0x20`; never calls `toUpperCase()`; never throws
    - `characterFor(String)`: plain lookup in `characters`; never throws
    - Add the export to `lib/morse_core.dart`
    - `///` doc comments citing REQ IDs on every public member
    - _Requirements: REQ-CODE-1, REQ-CODE-2, REQ-CODE-3, REQ-CODE-4, REQ-CODE-5, REQ-CODE-6, REQ-CODE-7, REQ-CODE-8, REQ-CODE-9, REQ-CODE-10, REQ-PURE-3, REQ-PURE-4, REQ-PURE-5, REQ-PURE-7_

  - [x] 4.2 Write unit tests for CodeTable in `test/code_table_test.dart`
    - REQ-CODE-1: exactly 43 keys, the expected key set, no lowercase, space or other keys
    - REQ-CODE-2: `A` `.-`, `E` `.`, `T` `-`, `1` `.----`, `0` `-----`
    - REQ-CODE-3: the seven punctuation codes
    - REQ-CODE-6: 43 reverse entries
    - REQ-CODE-9: `codeFor('')`, `codeFor(' ')`, `codeFor('AB')`, `codeFor('ı')`, `codeFor('!')`, `characterFor('')`, `characterFor('.......')`, `characterFor('. -')`, `characterFor('/')` all return null without throwing
    - REQ-CODE-10: `[]=`, `remove`, `clear` and `addAll` on `codes` and `characters` throw `UnsupportedError` and length stays 43
    - REQ-TEST-3: compare against the ITU fixture with separate failure messages for wrong count, missing character, extra character and differing code
    - _Requirements: REQ-CODE-1, REQ-CODE-2, REQ-CODE-3, REQ-CODE-6, REQ-CODE-9, REQ-CODE-10, REQ-TEST-2, REQ-TEST-3_

  - [x] 4.3 Write property test for unique codes in `test/properties_test.dart`
    - **Property 1: Codes are unique**
    - Use `supportedChar()`; assert exactly one entry of `CodeTable.codes` has the code `codeFor(c)`; seed 1003
    - Test name starts with `REQ-CODE-4`
    - Changed by bugfix spec `morse-core-unique-codes-property`: the earlier pairwise check missed a real E/I collision
    - **Validates: Requirements 1.4**

  - [x] 4.4 Write property test for table round trip and code shape in `test/properties_test.dart`
    - **Property 2: Table round trip and code shape**
    - Use `supportedChar()`; check non-null, `^[.-]{1,6}$`, and `characterFor(codeFor(c)) == asciiUpper(c)`; seed 2003
    - Test name starts with `REQ-CODE-5 REQ-CODE-7 REQ-CODE-8`
    - **Validates: Requirements 1.5, 1.7, 1.8**

  - [x] 4.5 Write property test for invalid lookups in `test/properties_test.dart`
    - **Property 3: Invalid lookups return null without throwing**
    - Sample strings that are not a single Supported_Character (empty, multi-character, `unsupportedChar()`, space) and strings that are not keys of `characters` (`decoderAlphabetString()` filtered); seed 3003
    - Test name starts with `REQ-CODE-9`
    - **Validates: Requirements 1.9**

- [x] 5. Checkpoint: code table complete
  - Run `cd packages/morse_core && dart test` and `dart analyze`: zero failures, zero skipped tests, zero analyzer errors and warnings.
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Implement MorseEncoder
  - [x] 6.1 Create `lib/src/morse_encoder.dart` and export it
    - `final class MorseEncoder` with a `const` constructor and `String encode(String text)`
    - One left-to-right pass over code units with a local `StringBuffer`, `gapPending`, and the design's rules: spaces only set `gapPending` when the buffer is non-empty; write `' / '` or `' '` before each code after the first
    - On the first unsupported code unit, throw `MorseFormatException(requirementId: 'REQ-ERR-1', position: i, offending: ...)`, where `offending` is both code units for a valid surrogate pair and the single code unit otherwise; no partial result escapes
    - Add the export to `lib/morse_core.dart`; `///` doc comments citing REQ IDs
    - _Requirements: REQ-ENC-1, REQ-ENC-2, REQ-ENC-3, REQ-ENC-4, REQ-ENC-5, REQ-ENC-6, REQ-ENC-7, REQ-ENC-10, REQ-ENC-11, REQ-FMT-2, REQ-ERR-1, REQ-ERR-9, REQ-ERR-10, REQ-PURE-3, REQ-PURE-4, REQ-PURE-5, REQ-PURE-7_

  - [x] 6.2 Write unit tests for the encoder in `test/encoder_test.dart`
    - REQ-ENC-7: `''` and `'   '` give `''`
    - REQ-ENC-8: `SOS` gives `... --- ...`
    - REQ-ENC-9: `hello world` gives `.... . .-.. .-.. --- / .-- --- .-. .-.. -..`
    - REQ-ENC-12: `  Hi   there ` gives `.... .. / - .... . .-. .`
    - REQ-ENC-13: `a/b 9` gives `.- -..-. -... / ----.`
    - REQ-FMT-7: ` e  t ` gives `. / -` (length 5)
    - _Requirements: REQ-ENC-7, REQ-ENC-8, REQ-ENC-9, REQ-ENC-12, REQ-ENC-13, REQ-FMT-7, REQ-TEST-2_

  - [x] 6.3 Write unit tests for encoder errors in `test/errors_test.dart`
    - REQ-ERR-1: `hé` (U+00E9 at 1), a tab, `ı`, `😀` (offending holds both code units, position is the high surrogate index), a lone surrogate; each asserts `requirementId == 'REQ-ERR-1'`, the exact `offending` and `position`, and that no value is returned
    - _Requirements: REQ-ERR-1, REQ-ERR-9, REQ-TEST-2_

  - [x] 6.4 Write property test for the encoder reference model in `test/properties_test.dart`
    - **Property 4: Encoder matches the reference model**
    - Use `plainText()`; compare `encode(s)` with the reference built from `normalise(s)` and fixture codes, and check `encode(s) == encode(asciiUpper(s))`; seed 4003
    - Test name starts with `REQ-ENC-1 REQ-ENC-2 REQ-ENC-3 REQ-ENC-4 REQ-ENC-5 REQ-ENC-6 REQ-ENC-7 REQ-ENC-11`
    - **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.11**

  - [x] 6.5 Write property test for encoder output format in `test/properties_test.dart`
    - **Property 5: Encoder output conforms to the format**
    - Use `plainText()`; assert `isEncodedText(encode(s))`; seed 5003
    - Test name starts with `REQ-ENC-6 REQ-ENC-10 REQ-FMT-2`
    - **Validates: Requirements 2.6, 2.10, 4.2**

  - [x] 6.6 Write property test for the first unsupported character in `test/properties_test.dart`
    - **Property 10: Encoder reports the first unsupported character**
    - Combine `plainText()`, `unsupportedChar()` and an arbitrary suffix with `combine3`; assert one `MorseFormatException` with `requirementId == 'REQ-ERR-1'`, `position == p.length`, `offending == u`; seed 10003
    - Test name starts with `REQ-ERR-1 REQ-ERR-9 REQ-ERR-10`
    - **Validates: Requirements 5.1, 5.9, 5.10**

- [x] 7. Checkpoint: encoder complete
  - Run `cd packages/morse_core && dart test` and `dart analyze`: zero failures, zero skipped tests, zero analyzer errors and warnings.
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 8. Implement MorseDecoder
  - [ ] 8.1 Create `lib/src/morse_decoder.dart` with the empty-input case and pass 1, and export it
    - `final class MorseDecoder` with a `const` constructor and `String decode(String morse)`
    - Return `''` for empty input
    - Pass 1: throw `REQ-ERR-2` at the first code unit outside `{0x2E, 0x2D, 0x20, 0x2F}`, keeping a valid surrogate pair whole as `offending`
    - Add the export to `lib/morse_core.dart`; `///` doc comments citing REQ IDs
    - _Requirements: REQ-DEC-4, REQ-ERR-2, REQ-ERR-11, REQ-PURE-4, REQ-PURE-5, REQ-PURE-7_

  - [ ] 8.2 Add pass 2: structural candidates and selection
    - One walk recording tokens as `(start, text)`; a private `_Candidate(position, errNumber, offending)`
    - Rules exactly as the design table: REQ-ERR-3 unknown symbol token, REQ-ERR-4 token containing `/` other than `/`, REQ-ERR-5 second space of the first double-space run, REQ-ERR-6 leading or trailing space or `/` token (position 0 or length − 1), REQ-ERR-7 second `/` of `/ /`
    - Throw the candidate with the smallest `(position, errNumber)`
    - _Requirements: REQ-ERR-3, REQ-ERR-4, REQ-ERR-5, REQ-ERR-6, REQ-ERR-7, REQ-ERR-9, REQ-ERR-11, REQ-DEC-10, REQ-FMT-6_

  - [ ] 8.3 Add pass 3: token mapping
    - Write `' '` for a `/` token and `characterFor(token)!` otherwise, into a local `StringBuffer` returned only at the end
    - _Requirements: REQ-DEC-1, REQ-DEC-2, REQ-DEC-3, REQ-DEC-7, REQ-FMT-5, REQ-PURE-3_

  - [ ] 8.4 Write unit tests for the decoder in `test/decoder_test.dart`
    - REQ-DEC-3: a word containing `-..-.` decodes to `/`
    - REQ-DEC-4: `''` gives `''`
    - REQ-DEC-5: `... --- ...` gives `SOS`
    - REQ-DEC-6: `-..-. / -.--. -.--.-` gives `/ ()` (length 4)
    - REQ-DEC-8: `.... . .-.. .-.. --- / .-- --- .-. .-.. -..` gives `HELLO WORLD`
    - REQ-DEC-9: `.---- ..--- ...-- / .-.-.- --..-- ..--.. -....-` gives `123 .,?-`
    - _Requirements: REQ-DEC-3, REQ-DEC-4, REQ-DEC-5, REQ-DEC-6, REQ-DEC-8, REQ-DEC-9, REQ-TEST-2_

  - [ ] 8.5 Write unit tests for decoder errors in `test/errors_test.dart`
    - REQ-ERR-2: a letter and a surrogate pair inside otherwise valid input, at the exact index
    - REQ-ERR-3: `... ...... ...` gives Token `......` at 4
    - REQ-ERR-4: `/.`, `-/`, `//` at the token start
    - REQ-ERR-5: `...  ---` at 4
    - REQ-ERR-6: ` ...` at 0, `... /` with `/` at 4, `/` alone
    - REQ-ERR-7: `... / / ...` at 6
    - REQ-ERR-8: exact messages for `... ...... ...`, `...  ---` and `... /` from the design table; `e.source == null`; `e.toString()` equals `e.message` and does not contain the input
    - REQ-ERR-11: `... / /` gives REQ-ERR-6 at 6, not REQ-ERR-7
    - _Requirements: REQ-ERR-2, REQ-ERR-3, REQ-ERR-4, REQ-ERR-5, REQ-ERR-6, REQ-ERR-7, REQ-ERR-8, REQ-ERR-9, REQ-ERR-11, REQ-TEST-2_

  - [ ] 8.6 Write property test for the text round trip in `test/properties_test.dart`
    - **Property 6: Text round trip**
    - Use `plainText()`; assert `decode(encode(s)) == normalise(s)`; seed 6003
    - Test name starts with `REQ-FMT-3`
    - **Validates: Requirements 4.3**

  - [ ] 8.7 Write property test for the code round trip in `test/properties_test.dart`
    - **Property 7: Code round trip**
    - Use `encodedText()`; assert `encode(decode(m)) == m` with no error; seed 7003
    - Test name starts with `REQ-DEC-1 REQ-DEC-2 REQ-DEC-3 REQ-FMT-4 REQ-FMT-5`
    - **Validates: Requirements 3.1, 3.2, 3.3, 4.4, 4.5**

  - [ ] 8.8 Write property test for closed decoder output in `test/properties_test.dart`
    - **Property 8: Decoder output is closed**
    - Use a variant of `encodedText()` that also yields `k` (codes) and `w` (Word_Separators); assert only uppercase Supported_Characters and single spaces, no leading or trailing space, length `k + w`; seed 8003
    - Test name starts with `REQ-DEC-7`
    - **Validates: Requirements 3.7**

  - [ ] 8.9 Write property test for exact acceptance in `test/properties_test.dart`
    - **Property 9: Decoder accepts exactly the conforming strings**
    - Use `oneOf(decoderAlphabetString(), nearMiss())`; assert `decode(s)` succeeds iff `isEncodedText(s)`; on success `encode(r) == s`; on failure exactly one `MorseFormatException` with `requirementId` in `REQ-ERR-3` to `REQ-ERR-7`; seed 9003
    - Test name starts with `REQ-DEC-10 REQ-FMT-5 REQ-FMT-6 REQ-ERR-9`
    - **Validates: Requirements 3.10, 4.5, 4.6, 5.9**

  - [ ] 8.10 Write property test for injected invalid characters in `test/properties_test.dart`
    - **Property 11: Decoder reports an injected invalid character**
    - Use `injectedInvalid()`, one `(m, i, c)` triple per case, 200 cases; do not loop over every index or code unit; assert `requirementId == 'REQ-ERR-2'`, `position == i`, `offending == c`; seed 11003
    - Test name starts with `REQ-ERR-2 REQ-ERR-11 REQ-ERR-12`
    - **Validates: Requirements 5.2, 5.11, 5.12**

  - [ ] 8.11 Write property test for well-formed errors in `test/properties_test.dart`
    - **Property 12: Every error is well formed**
    - Use `oneOf` of arbitrary Unicode strings, `decoderAlphabetString()` and `nearMiss()`; run both `encode` and `decode`; for every thrown exception check position range, `offset == position`, position in the message, quoted Token or `U+XXXX` form, `source == null`, `toString() == message`; seed 12003
    - Test name starts with `REQ-ERR-8`
    - **Validates: Requirements 5.8**

  - [ ] 8.12 Write property test for determinism in `test/properties_test.dart`
    - **Property 13: Determinism**
    - Use the same mixed string generator; call `encode` twice and `decode` twice; results are equal or both throw with the same `requirementId` and `position`; seed 13003
    - Test name starts with `REQ-PURE-2`
    - **Validates: Requirements 6.2**

- [ ] 9. Checkpoint: decoder complete
  - Run `cd packages/morse_core && dart test` and `dart analyze`: zero failures, zero skipped tests, zero analyzer errors and warnings.
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 10. Finish the public surface and add purity and structure tests
  - [ ] 10.1 Complete the example and library doc
    - Rewrite `example/morse_core_example.dart` to import only `package:morse_core/morse_core.dart` and use `CodeTable`, `MorseEncoder`, `MorseDecoder` and `MorseFormatException` (look up a code, encode and decode `hello world`, catch an error and print only its message)
    - Finish the `lib/morse_core.dart` library doc comment, citing REQ-PURE-5
    - _Requirements: REQ-PURE-5, REQ-PURE-6, REQ-PURE-7_

  - [ ] 10.2 Write purity tests for dependencies, I/O and file structure in `test/purity_test.dart`
    - `dart:io` is used only in this test, and it reads only files under `packages/morse_core/`
    - REQ-PURE-1: `pubspec.yaml` has no `dependencies` entries; every `import` in `lib/` is an allowed `dart:` library or a relative path; none is on the forbidden list; no `lib/` file imports `kiri_check`, `test` or `lints`
    - REQ-PURE-3: no `lib/` file imports I/O, clock or random libraries; no top-level or `static` variable without `final` or `const`; mutating `codes` and `characters` throws
    - REQ-PURE-4: each `lib/src/` file declares exactly one public class whose `snake_case` name equals the file name
    - REQ-PURE-5: the test imports only `package:morse_core/morse_core.dart`, uses all four classes, and checks that every public class in `lib/src/` is exported
    - _Requirements: REQ-PURE-1, REQ-PURE-3, REQ-PURE-4, REQ-PURE-5, REQ-TEST-7_

  - [ ] 10.3 Write purity tests for scaffold removal and doc comments in `test/purity_test.dart`
    - REQ-PURE-6: no `Awesome` identifier in the package; no `morse_core_base.dart` or `morse_core_test.dart`; the `pubspec.yaml` description and `example/` refer only to the four classes
    - REQ-PURE-7: every public declaration in `lib/` has a preceding `///` comment containing `REQ-<AREA>-<n>`, and every cited ID is in `test/support/requirement_ids.dart`
    - _Requirements: REQ-PURE-6, REQ-PURE-7_

  - [ ] 10.4 Write the test-name meta-test in `test/purity_test.dart`
    - REQ-TEST-4: scan `test/*.dart` for `test('` and `property('` names; assert each begins with REQ IDs and that every ID listed in REQ-TEST-1, REQ-TEST-2 and REQ-TEST-3 begins at least one test name
    - REQ-TEST-5: assert no `skip:` appears in any test file
    - REQ-PURE-9: assert that each of REQ-PURE-1 to REQ-PURE-7 appears in at least one test name
    - _Requirements: REQ-TEST-4, REQ-TEST-5, REQ-PURE-9_

- [ ] 11. Final checkpoint: full suite and analyzer
  - Run `cd packages/morse_core && dart test`: zero failures, zero errors, zero skipped tests, finished within 60 seconds.
  - Run `cd packages/morse_core && dart analyze`: zero errors and zero warnings.
  - Confirm `pubspec.lock` still records `kiri_check` 1.4.0 and `dependencies` is empty.
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- No test sub-task is marked optional. REQ-TEST-1 to REQ-TEST-4 and REQ-PURE-9 make the unit tests, the property tests and the ITU fixture comparison requirements in their own right, so skipping them would leave requirements unmet.
- Each class task adds its own export to `lib/morse_core.dart`, so the package compiles and is testable after every step.
- `example/morse_core_example.dart` is reduced to a minimal `main()` in task 1 and completed in task 10.1, once all four classes exist.
- `test/support/requirement_ids.dart` is a copy of the IDs in `requirements.md`. Update it if `requirements.md` changes.
- Property seeds follow `N*1000 + 3` for Property N. To explore new cases, change a seed locally (D4).

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1"] },
    { "id": 1, "tasks": ["2.1", "2.4"] },
    { "id": 2, "tasks": ["2.2", "2.3"] },
    { "id": 3, "tasks": ["3.1"] },
    { "id": 4, "tasks": ["3.2", "4.1"] },
    { "id": 5, "tasks": ["4.2", "4.3"] },
    { "id": 6, "tasks": ["4.4"] },
    { "id": 7, "tasks": ["4.5"] },
    { "id": 8, "tasks": ["5"] },
    { "id": 9, "tasks": ["6.1"] },
    { "id": 10, "tasks": ["6.2", "6.3", "6.4"] },
    { "id": 11, "tasks": ["6.5"] },
    { "id": 12, "tasks": ["6.6"] },
    { "id": 13, "tasks": ["7"] },
    { "id": 14, "tasks": ["8.1"] },
    { "id": 15, "tasks": ["8.2"] },
    { "id": 16, "tasks": ["8.3"] },
    { "id": 17, "tasks": ["8.4", "8.5", "8.6"] },
    { "id": 18, "tasks": ["8.7"] },
    { "id": 19, "tasks": ["8.8"] },
    { "id": 20, "tasks": ["8.9"] },
    { "id": 21, "tasks": ["8.10"] },
    { "id": 22, "tasks": ["8.11"] },
    { "id": 23, "tasks": ["8.12"] },
    { "id": 24, "tasks": ["9"] },
    { "id": 25, "tasks": ["10.1", "10.2"] },
    { "id": 26, "tasks": ["10.3"] },
    { "id": 27, "tasks": ["10.4"] },
    { "id": 28, "tasks": ["11"] }
  ]
}
```
