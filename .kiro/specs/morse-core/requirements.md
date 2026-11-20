# Requirements Document

## Introduction

`morse_core` is the pure Dart engine of Sounder, located in `packages/morse_core`. This spec covers only the Morse code table, text-to-Morse encoding, and Morse-to-text decoding. Press timing, dit/dah classification and calibration belong to later specs (for example `adaptive-timing`).

The package encodes text made of A-Z, 0-9 and the punctuation `. , ? / - ( )` into International Morse code as defined by ITU-R M.1677-1, and decodes that format back into uppercase text. Unsupported input is rejected with an error that names the offending character or token and its position. Nothing is silently dropped.

The package contains no Flutter imports, performs no I/O, and exposes pure functions. Every acceptance criterion below has an ID (`REQ-CODE-n`, `REQ-ENC-n`, `REQ-DEC-n`, `REQ-FMT-n`, `REQ-ERR-n`, `REQ-PURE-n`, `REQ-TEST-n`). Tests and doc comments cite these IDs.

### Decisions and assumptions

These points were not fixed by the request. Each is a recorded decision, flagged for review.

- **A1. Word separator in plain text.** Only the space character (U+0020) separates words. Tabs, newlines and other whitespace are unsupported characters and are rejected.
- **A2. Leading, trailing and repeated spaces on encode.** The Encoder ignores leading and trailing spaces and treats any run of one or more spaces as a single word gap. This is what makes the round-trip property "uppercase with runs of spaces collapsed" hold; the comparison also trims leading and trailing spaces.
- **A3. Empty input.** Encoding the empty string, or a string of only spaces, returns the empty string. Decoding the empty string returns the empty string.
- **A4. Decoder is strict.** The Decoder accepts only the exact format the Encoder produces: letters separated by exactly one space, words separated by exactly ` / `, no leading or trailing spaces. Any deviation is an error. Lenient parsing can be added later as a separate requirement if needed.
- **A5. Slash character vs word separator.** The `/` character encodes as `-..-.`, which is made of dots and dashes only. The word separator is the standalone token `/` surrounded by single spaces. Because the Decoder splits on spaces first, the two never collide.
- **A6. Error position.** Positions are zero-based offsets into the input string, counted in UTF-16 code units (Dart `String` indexing). For a bad Morse token, the position is the offset of the token's first character.
- **A7. Digits and punctuation codes.** The table uses the ITU-R M.1677-1 codes only. Non-ITU variants (for example `-.--.` as a closing bracket in some American usage, or `!`) are out of scope.

## Glossary

- **Morse_Core**: The pure Dart package `packages/morse_core`.
- **Code_Table**: The Morse_Core component that maps each Supported_Character to exactly one Morse_Code.
- **Encoder**: The Morse_Core component that converts Plain_Text into Encoded_Text.
- **Decoder**: The Morse_Core component that converts Encoded_Text into Plain_Text.
- **Supported_Character**: One of the 43 characters `A`-`Z`, `0`-`9`, `.`, `,`, `?`, `/`, `-`, `(`, `)`, or a lowercase letter `a`-`z`, which counts as its uppercase form.
- **Unsupported_Character**: Any character in Plain_Text that is neither a Supported_Character nor the space character U+0020.
- **Plain_Text**: A Dart string given to the Encoder or produced by the Decoder.
- **Normalised_Text**: Plain_Text converted to uppercase, with leading and trailing spaces removed and every run of spaces replaced by one space.
- **Morse_Code**: A non-empty sequence of Symbols that represents one Supported_Character.
- **Symbol**: A dot `.` (dit) or a dash `-` (dah).
- **Letter_Gap**: Exactly one space character between two Morse_Codes in the same word.
- **Word_Separator**: The three-character sequence space, `/`, space (` / `) between two words in Encoded_Text.
- **Token**: A maximal run of non-space characters in Encoded_Text.
- **Encoded_Text**: A string of Morse_Codes joined by Letter_Gaps and Word_Separators, as defined in Requirement 4.
- **Morse_Format_Error**: The error value that the Encoder or Decoder raises for invalid input. It carries the offending character or Token, its zero-based position, and a human-readable message.
- **ITU_Table**: The character-to-code mapping in Recommendation ITU-R M.1677-1, Part I, section 1.1.

## Requirements

### Requirement 1: Code table

**User Story:** As a Sounder developer, I want one authoritative Morse code table, so that encoding and decoding agree with the international standard and with each other.

#### Acceptance Criteria

1. REQ-CODE-1: THE Code_Table SHALL contain exactly one entry for each of the 26 uppercase letters `A`-`Z`, the 10 digits `0`-`9`, and the 7 punctuation characters `.`, `,`, `?`, `/`, `-`, `(`, `)`, for a total of exactly 43 entries, with no entry keyed by a lowercase letter, a space, or any other character.
2. REQ-CODE-2: THE Code_Table SHALL map each of the 43 Supported_Characters to the Morse_Code given for that character in the ITU_Table, including `A` to `.-`, `E` to `.`, `T` to `-`, `1` to `.----`, and `0` to `-----`.
3. REQ-CODE-3: THE Code_Table SHALL map `.` to `.-.-.-`, `,` to `--..--`, `?` to `..--..`, `/` to `-..-.`, `-` to `-....-`, `(` to `-.--.`, and `)` to `-.--.-`.
4. REQ-CODE-4: THE Code_Table SHALL assign a distinct Morse_Code to every one of its 43 entries, so that no two entries share the same Morse_Code (unique codes property).
5. REQ-CODE-5: THE Code_Table SHALL contain only Morse_Codes made of 1 to 6 Symbols, with no space, `/`, or any character other than `.` and `-`.
6. REQ-CODE-6: THE Code_Table SHALL provide a reverse lookup that contains exactly 43 entries, one for each Morse_Code in the table, and maps each Morse_Code to its uppercase Supported_Character.
7. REQ-CODE-7: FOR ALL 43 entries in the Code_Table, looking up the Morse_Code of a character and then reverse-looking up that Morse_Code SHALL return the same uppercase character (table round-trip property).
8. REQ-CODE-8: WHEN a lowercase letter `a`-`z` is looked up in the Code_Table, THE Code_Table SHALL return the same Morse_Code as for the matching uppercase letter.
9. REQ-CODE-9: IF a lookup receives a value that is not a Supported_Character (such as the empty string, a space, a string longer than one character, or a character outside the 43 entries), or a reverse lookup receives a string that is not one of the 43 Morse_Codes (such as the empty string, a sequence of 7 or more Symbols, or a string that contains a space or `/`), THEN THE Code_Table SHALL report that no entry exists, return no character or Morse_Code, and raise no error.
10. REQ-CODE-10: IF a caller attempts to add, remove, or change an entry in the Code_Table or its reverse lookup, THEN THE Code_Table SHALL reject the attempt with an error and keep all 43 entries unchanged.

### Requirement 2: Encode text to Morse

**User Story:** As a Sounder developer, I want to turn text into Morse code, so that the app can show users the code for a letter or phrase.

#### Acceptance Criteria

1. REQ-ENC-1: WHEN the Encoder receives Plain_Text made only of Supported_Characters and spaces (U+0020), THE Encoder SHALL return Encoded_Text that contains exactly one Morse_Code from the Code_Table for each Supported_Character in the Plain_Text, in the same order as the characters appear in the Plain_Text. Plain_Text that contains an Unsupported_Character is covered by REQ-ERR-1.
2. REQ-ENC-2: THE Encoder SHALL encode each lowercase letter `a`-`z` to the same Morse_Code as the matching uppercase letter `A`-`Z`.
3. REQ-ENC-3: THE Encoder SHALL join the Morse_Codes of consecutive Supported_Characters within one word with exactly one Letter_Gap, where a word is a maximal run of Supported_Characters with no space in it.
4. REQ-ENC-4: THE Encoder SHALL place exactly one Word_Separator between the last Morse_Code of one word and the first Morse_Code of the next word, so that Encoded_Text for Plain_Text with N words (N ≥ 1) contains exactly N − 1 Word_Separators.
5. REQ-ENC-5: WHEN Plain_Text contains a run of one or more spaces between two words, THE Encoder SHALL emit exactly one Word_Separator for that run, whatever the run's length.
6. REQ-ENC-6: WHEN Plain_Text starts or ends with one or more spaces, THE Encoder SHALL return Encoded_Text whose first and last characters are Symbols, with no leading or trailing space and no leading or trailing Word_Separator.
7. REQ-ENC-7: WHEN Plain_Text is the empty string or contains only spaces (one or more U+0020 characters), THE Encoder SHALL return the empty string.
8. REQ-ENC-8: WHEN the Encoder receives `SOS`, THE Encoder SHALL return `... --- ...`.
9. REQ-ENC-9: WHEN the Encoder receives `hello world`, THE Encoder SHALL return `.... . .-.. .-.. --- / .-- --- .-. .-.. -..`.
10. REQ-ENC-10: FOR ALL Plain_Text made of Supported_Characters and spaces, THE Encoder SHALL return Encoded_Text that contains only the characters `.`, `-`, space and `/`, in which every `/` character is the middle character of a Word_Separator (closed output property).
11. REQ-ENC-11: FOR ALL Plain_Text made of Supported_Characters and spaces, THE Encoder SHALL return the same Encoded_Text for the Plain_Text as for its uppercase form (case-insensitivity property).
12. REQ-ENC-12: WHEN the Encoder receives `  Hi   there `, with two leading spaces, three spaces between the words and one trailing space, THE Encoder SHALL return `.... .. / - .... . .-. .`.
13. REQ-ENC-13: WHEN the Encoder receives `a/b 9`, THE Encoder SHALL return `.- -..-. -... / ----.`, in which the `/` character is encoded as the Morse_Code `-..-.` within the first word and not as a Word_Separator.

### Requirement 3: Decode Morse to text

**User Story:** As a Sounder developer, I want to turn Morse code back into text, so that the composer can show and speak what the user keyed.

#### Acceptance Criteria

1. REQ-DEC-1: WHEN the Decoder receives a non-empty string that conforms to the Encoded_Text definition in REQ-FMT-1 and in which every Token other than a Word_Separator's `/` is a Morse_Code in the Code_Table, THE Decoder SHALL return Plain_Text that contains exactly one uppercase Supported_Character per Morse_Code, taken from the Code_Table reverse lookup, in the same left-to-right order as the Morse_Codes in the input.
2. REQ-DEC-2: WHEN the Decoder receives Encoded_Text that contains one or more Word_Separators, THE Decoder SHALL emit exactly one space character (U+0020) in the Plain_Text for each Word_Separator, placed between the characters decoded from the word before it and the word after it, and SHALL emit no `/` character for the `/` inside a Word_Separator.
3. REQ-DEC-3: WHEN the Decoder receives Encoded_Text that contains the Token `-..-.`, THE Decoder SHALL emit the character `/` in the Plain_Text at the position of that Token. A standalone `/` Token that is part of a Word_Separator is decoded only as defined in REQ-DEC-2.
4. REQ-DEC-4: WHEN the Decoder receives the empty string, THE Decoder SHALL return the empty string and raise no Morse_Format_Error.
5. REQ-DEC-5: WHEN the Decoder receives `... --- ...`, THE Decoder SHALL return `SOS`.
6. REQ-DEC-6: WHEN the Decoder receives `-..-. / -.--. -.--.-`, THE Decoder SHALL return `/ ()`, a 4-character string.
7. REQ-DEC-7: FOR ALL Encoded_Text accepted by the Decoder (the empty string, or any input that meets the conditions of REQ-DEC-1), THE Decoder SHALL return Plain_Text made only of uppercase Supported_Characters and single spaces, with no leading or trailing space, whose length equals the number of Morse_Codes plus the number of Word_Separators in the input (closed output property).
8. REQ-DEC-8: WHEN the Decoder receives `.... . .-.. .-.. --- / .-- --- .-. .-.. -..`, THE Decoder SHALL return `HELLO WORLD`.
9. REQ-DEC-9: WHEN the Decoder receives `.---- ..--- ...-- / .-.-.- --..-- ..--.. -....-`, THE Decoder SHALL return `123 .,?-`.
10. REQ-DEC-10: IF the Decoder receives a non-empty string that does not meet the conditions of REQ-DEC-1, THEN THE Decoder SHALL raise a Morse_Format_Error and return no Plain_Text, with the error contents defined by REQ-ERR-2 to REQ-ERR-9 for the cases those requirements cover.

### Requirement 4: Encoded text format

**User Story:** As a Sounder developer, I want one precise definition of the encoded format, so that the Encoder output and the Decoder input match exactly.

#### Acceptance Criteria

1. REQ-FMT-1: THE Morse_Core SHALL define Encoded_Text as either the empty string or a sequence of one or more words joined by Word_Separators, where each word is a sequence of one or more Morse_Codes that appear in the Code_Table joined by Letter_Gaps. Encoded_Text contains no characters other than `.`, `-`, space and `/`, no leading or trailing space, no two consecutive Word_Separators, and no space run other than a single Letter_Gap or the two spaces of one Word_Separator.
2. REQ-FMT-2: FOR ALL Plain_Text made of Supported_Characters and spaces, including the empty string, strings of only spaces, strings with leading, trailing or repeated spaces, and strings with lowercase letters, THE Encoder SHALL return a string that conforms to the Encoded_Text definition in REQ-FMT-1.
3. REQ-FMT-3: FOR ALL Plain_Text made of Supported_Characters and spaces, including the empty string, strings of only spaces, strings with leading, trailing or repeated spaces, and strings with lowercase letters, THE Decoder SHALL return, when given the Encoder output for that Plain_Text, a string equal character for character to the Normalised_Text of that Plain_Text, without raising a Morse_Format_Error (text round-trip property).
4. REQ-FMT-4: FOR ALL Encoded_Text that conforms to REQ-FMT-1, including the empty string and Encoded_Text that contains the Morse_Code `-..-.` for `/`, THE Encoder SHALL return, when given the Decoder output for that Encoded_Text, a string equal character for character to the original Encoded_Text, without raising a Morse_Format_Error (code round-trip property).
5. REQ-FMT-5: WHEN the Decoder receives a string that conforms to the Encoded_Text definition in REQ-FMT-1, THE Decoder SHALL return Plain_Text without raising a Morse_Format_Error.
6. REQ-FMT-6: IF the Decoder receives a string that does not conform to the Encoded_Text definition in REQ-FMT-1, THEN THE Decoder SHALL raise a Morse_Format_Error and return no partial result.
7. REQ-FMT-7: WHEN the Encoder receives ` e  t `, THE Encoder SHALL return `. / -`, a string of exactly five characters.

### Requirement 5: Errors for invalid input

**User Story:** As a Sounder developer, I want invalid input rejected with a precise error, so that no character is silently lost and I can tell the user exactly what went wrong.

#### Acceptance Criteria

1. REQ-ERR-1: IF Plain_Text contains one or more Unsupported_Characters, THEN THE Encoder SHALL raise a Morse_Format_Error that carries the Unsupported_Character with the lowest position and that position, counted in UTF-16 code units. A supplementary-plane character (a valid surrogate pair) counts as one Unsupported_Character: the error carries both code units, and the position is the index of the high surrogate. A lone surrogate counts as one Unsupported_Character made of that single code unit.
2. REQ-ERR-2: IF Encoded_Text contains one or more characters other than `.`, `-`, space (U+0020) or `/`, THEN THE Decoder SHALL raise a Morse_Format_Error that carries the first such character (lowest position) and its zero-based position in UTF-16 code units. Surrogate pairs and lone surrogates follow the same rule as in REQ-ERR-1.
3. REQ-ERR-3: IF Encoded_Text contains a Token made only of Symbols that is not a Morse_Code in the Code_Table, THEN THE Decoder SHALL raise a Morse_Format_Error that carries that Token verbatim and the zero-based position of its first character. Example: decoding `... ...... ...` raises an error with Token `......` at position 4.
4. REQ-ERR-4: IF Encoded_Text contains a Token that includes at least one `/` and is not exactly the one-character Token `/` (for example `/.`, `-/`, `//`), THEN THE Decoder SHALL raise a Morse_Format_Error that carries that Token verbatim and the zero-based position of its first character.
5. REQ-ERR-5: IF Encoded_Text contains a run of two or more consecutive spaces anywhere, THEN THE Decoder SHALL raise a Morse_Format_Error that carries the space character and the zero-based position of the second space in the first such run. Example: decoding `...  ---` raises an error at position 4.
6. REQ-ERR-6: IF Encoded_Text begins with a space or with the Token `/`, or ends with a space or with the Token `/`, THEN THE Decoder SHALL raise a Morse_Format_Error that carries that space or `/`. The position is 0 for an offending first character and the input length minus 1 for an offending last character. Examples: ` ...` raises at position 0; `... /` raises with `/` at position 4.
7. REQ-ERR-7: IF Encoded_Text contains two `/` Tokens separated by exactly one space (an empty word, ` / / `), THEN THE Decoder SHALL raise a Morse_Format_Error that carries `/` and the zero-based position of the second `/`. Example: decoding `... / / ...` raises an error at position 6.
8. REQ-ERR-8: WHEN the Encoder or the Decoder raises a Morse_Format_Error, THE Morse_Format_Error SHALL carry a position in the range 0 to the input length minus 1, and SHALL include an English message that contains that position as a decimal integer. If the error carries a Token, the message SHALL contain the Token verbatim. If the error carries a single character, the message SHALL contain the character's Unicode code point in `U+XXXX` notation (four or more uppercase hexadecimal digits).
9. REQ-ERR-9: IF the Encoder or the Decoder receives input that meets any condition in REQ-ERR-1 to REQ-ERR-7, THEN the Encoder or Decoder SHALL raise exactly one Morse_Format_Error and SHALL NOT return any value, including partial Encoded_Text or partial Plain_Text.
10. REQ-ERR-10: FOR ALL Plain_Text that contains at least one Unsupported_Character, THE Encoder SHALL raise a Morse_Format_Error whose position equals the index of the first Unsupported_Character in that Plain_Text (error property).
11. REQ-ERR-11: IF Encoded_Text meets more than one condition in REQ-ERR-2 to REQ-ERR-7, THEN THE Decoder SHALL raise the REQ-ERR-2 error whenever REQ-ERR-2 applies. Otherwise the Decoder SHALL raise the error with the lowest position. If two conditions give the same position, the Decoder SHALL raise the one with the lower REQ-ERR number. Example: `... / /` raises the REQ-ERR-6 error at position 6, not the REQ-ERR-7 error.
12. REQ-ERR-12: FOR ALL non-empty Encoded_Text produced by the Encoder, every index i in that Encoded_Text, and every non-surrogate UTF-16 code unit c other than `.`, `-`, space and `/`, decoding the Encoded_Text with the character at index i replaced by c SHALL raise a Morse_Format_Error that carries c at position i (decoder error property).

### Requirement 6: Package purity and structure

**User Story:** As a Sounder developer, I want the engine to stay pure Dart, so that it runs in tests, on the web build, and in any future host without Flutter.

#### Acceptance Criteria

1. REQ-PURE-1: THE Morse_Core SHALL list zero packages under `dependencies` in its `pubspec.yaml`, and every file under `lib/` SHALL import only `dart:core`, `dart:collection`, `dart:convert`, `dart:math`, `dart:typed_data`, `dart:async` or other files of Morse_Core. No file under `lib/` SHALL import any `package:flutter` library, `dart:ui`, `dart:io`, `dart:html`, `dart:js_interop`, `dart:ffi`, `dart:isolate` or `dart:mirrors`. Packages under `dev_dependencies` are limited to test and lint tooling, and no file under `lib/` imports them.
2. REQ-PURE-2: WHEN the Encoder or the Decoder is called twice with equal input, THE Morse_Core SHALL return equal output on both calls, or throw a Morse_Format_Error with the same error kind and the same character position on both calls.
3. REQ-PURE-3: THE Encoder, THE Decoder and THE Code_Table SHALL NOT read or write files, network, clock, random number sources or environment variables. They SHALL NOT read or write any top-level variable or static field that is not `final` or `const`. The Code_Table's mapping SHALL be unmodifiable, so any attempt to add, remove or replace an entry throws an error and leaves the mapping unchanged.
4. REQ-PURE-4: THE Morse_Core SHALL place each public class in its own file under `lib/src/`. The file name SHALL be the class name converted to `snake_case.dart` (for example, `CodeTable` goes in `code_table.dart`), and each file SHALL declare exactly one public class.
5. REQ-PURE-5: THE Morse_Core SHALL export every public class from `lib/morse_core.dart`, so that a consumer can use the whole public API with that single import and without importing any file under `lib/src/`.
6. REQ-PURE-6: THE Morse_Core SHALL contain no identifier `Awesome` and no file named `morse_core_base.dart` or `morse_core_test.dart`. Its public API SHALL consist of the Code_Table, Encoder, Decoder and Morse_Format_Error. The `pubspec.yaml` description and any file under `example/` SHALL describe or use only that public API.
7. REQ-PURE-7: THE Morse_Core SHALL put a `///` doc comment on every public class and on every public constructor, method, getter, setter and field. Each doc comment SHALL cite at least one requirement ID in the form `REQ-<AREA>-<n>`, and every cited ID SHALL exist in the morse-core requirements document.
8. REQ-PURE-8: WHEN `dart analyze` runs in `packages/morse_core`, THE Morse_Core SHALL produce zero errors and zero warnings.
9. REQ-PURE-9: WHEN `dart test` runs in `packages/morse_core`, THE Morse_Core SHALL pass every test, and at least one test SHALL cite each of REQ-PURE-1 through REQ-PURE-7.

### Requirement 7: Tests

**User Story:** As a Sounder developer, I want the engine invariants checked by property-based tests and the examples checked by unit tests, so that the code table and format stay correct as the engine grows.

#### Acceptance Criteria

1. REQ-TEST-1: THE Morse_Core SHALL include, in `packages/morse_core/test/`, at least one property-based test for each of REQ-CODE-4, REQ-CODE-7, REQ-ENC-10, REQ-DEC-7, REQ-FMT-2, REQ-FMT-3, REQ-FMT-4 and REQ-ERR-10. Each property SHALL run at least 100 generated cases per `dart test` run. The tests SHALL use a maintained Dart property-based testing package whose name and version are confirmed against pub.dev during design and pinned in `pubspec.yaml`.
2. REQ-TEST-2: THE Morse_Core SHALL include, in `packages/morse_core/test/`, at least one example-based unit test with a fixed input and an exact expected output for each of REQ-CODE-1, REQ-CODE-2, REQ-CODE-3, REQ-ENC-7, REQ-ENC-8, REQ-ENC-9, REQ-DEC-4, REQ-DEC-5, REQ-DEC-6, REQ-ERR-1, REQ-ERR-2, REQ-ERR-3, REQ-ERR-4, REQ-ERR-5, REQ-ERR-6, REQ-ERR-7 and REQ-ERR-8.
3. REQ-TEST-3: THE Morse_Core SHALL include a unit test that compares the Code_Table against a fixture transcribed from the ITU_Table. The test SHALL fail if the Code_Table holds a number of entries other than 43, if any fixture character is missing from the Code_Table, if any Code_Table character is absent from the fixture, or if any character's dit-dah sequence differs from the fixture.
4. REQ-TEST-4: THE Morse_Core SHALL begin each test name with every requirement ID the test covers, in the form `REQ-<AREA>-<n>`. Every requirement ID listed in REQ-TEST-1, REQ-TEST-2 and REQ-TEST-3 SHALL appear in the name of at least one test.
5. REQ-TEST-5: WHEN `dart test` runs in `packages/morse_core`, THE Morse_Core test suite SHALL report zero failures, zero errors and zero skipped tests, and SHALL finish within 60 seconds.
6. REQ-TEST-6: IF a property-based test fails, THEN THE Morse_Core test suite SHALL report the failing generated input, and the reported seed or input SHALL reproduce the same failure when the test runs again.
7. REQ-TEST-7: THE Morse_Core test suite SHALL run through the Dart SDK alone, without importing Flutter, without network access, and without reading or writing files outside `packages/morse_core/`.
