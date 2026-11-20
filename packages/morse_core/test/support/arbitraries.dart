/// kiri_check generators for the morse-core property tests.
///
/// Every generator is built from the ITU fixture, never from `lib/`. This file
/// does not import `package:morse_core`, so a bug in `CodeTable` or
/// `MorseEncoder` cannot shape the inputs used to test them.
///
/// Each generator samples one value per case; none enumerates its input
/// space, so every property runs exactly `maxExamples` cases. REQ-TEST-1,
/// REQ-TEST-5.
library;

import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'itu_fixture.dart';

/// The 43 uppercase Supported_Characters, in fixture order. REQ-CODE-1.
final List<String> _tableKeys = List<String>.unmodifiable(ituFixture.keys);

/// The 26 lowercase letters `a`-`z`, which count as Supported_Characters.
final List<String> _lowercase = List<String>.unmodifiable(
  List<String>.generate(26, (i) => String.fromCharCode(0x61 + i)),
);

/// Every Supported_Character: 43 table keys plus `a`-`z`.
final List<String> _supportedChars =
    List<String>.unmodifiable(<String>[..._tableKeys, ..._lowercase]);

final Set<String> _supportedSet = Set<String>.unmodifiable(_supportedChars);

/// Characters used to build Plain_Text. The space is repeated so that about
/// one character in four is a space, which makes leading, trailing and
/// repeated spaces common.
final List<String> _plainAlphabet = List<String>.unmodifiable(<String>[
  ..._supportedChars,
  ...List<String>.filled(23, ' '),
]);

/// Table keys used to build Encoded_Text. `/` is repeated so that words
/// containing its code `-..-.` appear often. REQ-DEC-3, REQ-FMT-4.
final List<String> _encodedKeys = List<String>.unmodifiable(<String>[
  ..._tableKeys,
  ...List<String>.filled(4, '/'),
]);

/// The decoder alphabet: dot, dash, space and slash.
const List<String> _decoderAlphabet = <String>['.', '-', ' ', '/'];

/// Hand-picked Unsupported_Characters: tab, newline, dotless i, sharp s,
/// e-acute, `!`, `:`, and a supplementary-plane emoji (a surrogate pair).
/// REQ-ERR-1.
const List<String> _handPickedUnsupported = <String>[
  '\t',
  '\n',
  '\u0131',
  '\u00DF',
  '\u00E9',
  '!',
  ':',
  '\u{1F600}',
];

/// One Supported_Character: an uppercase table key or a lowercase letter.
/// REQ-CODE-7, REQ-CODE-8.
Arbitrary<String> supportedChar() => constantFrom<String>(_supportedChars);

/// Plain_Text of up to 40 Supported_Characters and spaces, with frequent
/// leading, trailing and repeated spaces and mixed case. REQ-FMT-3.
Arbitrary<String> plainText() =>
    list<String>(constantFrom<String>(_plainAlphabet), maxLength: 40)
        .map((chars) => chars.join());

/// Joins words of table keys into Encoded_Text using fixture codes:
/// codes with `' '`, words with `' / '`.
String _joinWords(List<List<String>> words) => words
    .map((word) => word.map((key) => ituFixture[key]!).join(' '))
    .join(' / ');

Arbitrary<List<List<String>>> _words({required int minWords}) =>
    list<List<String>>(
      list<String>(constantFrom<String>(_encodedKeys),
          minLength: 1, maxLength: 6),
      minLength: minWords,
      maxLength: 6,
    );

/// Encoded_Text built from fixture codes, independently of `MorseEncoder`:
/// 0 to 6 words of 1 to 6 codes each. Includes the empty string and words
/// containing `-..-.`. REQ-FMT-1, REQ-FMT-4.
Arbitrary<String> encodedText() => _words(minWords: 0).map(_joinWords);

/// Non-empty Encoded_Text, built directly rather than by filtering.
Arbitrary<String> _nonEmptyEncodedText() =>
    _words(minWords: 1).map(_joinWords);

/// One Unsupported_Character as a Dart string: any Unicode scalar or
/// surrogate code point that is neither a Supported_Character nor U+0020
/// (code points above U+FFFF become a surrogate pair), a lone surrogate
/// U+D800-U+DFFF, or a hand-picked case. REQ-ERR-1, REQ-ERR-10.
Arbitrary<String> unsupportedChar() => oneOf(<Arbitrary<dynamic>>[
      integer(min: 0, max: 0x10FFFF)
          .map(String.fromCharCode)
          .filter((s) => s != ' ' && !_supportedSet.contains(s)),
      integer(min: 0xD800, max: 0xDFFF).map(String.fromCharCode),
      constantFrom<String>(_handPickedUnsupported),
    ]).cast<String>();

/// A string of up to 30 characters over `.`, `-`, space and `/`. Most such
/// strings are not Encoded_Text. REQ-DEC-10, REQ-FMT-6.
Arbitrary<String> decoderAlphabetString() =>
    list<String>(constantFrom<String>(_decoderAlphabet), maxLength: 30)
        .map((chars) => chars.join());

final Set<String> _fixtureCodes = Set<String>.unmodifiable(ituFixture.values);

/// A string that is not a single Supported_Character: the empty string, a
/// space, one Unsupported_Character, or a string of 2 to 8 characters mixing
/// Supported_Characters, spaces and Unsupported_Characters. REQ-CODE-9.
Arbitrary<String> notSupportedCharString() => oneOf(<Arbitrary<dynamic>>[
      constantFrom<String>(const <String>['', ' ']),
      unsupportedChar(),
      list<String>(
        oneOf(<Arbitrary<dynamic>>[
          supportedChar(),
          constantFrom<String>(const <String>[' ']),
          unsupportedChar(),
        ]).cast<String>(),
        minLength: 2,
        maxLength: 8,
      ).map((chars) => chars.join()),
    ]).cast<String>();

/// A string over `.`, `-`, space and `/` that is not one of the 43 fixture
/// Morse_Codes, so it has no reverse-lookup entry. REQ-CODE-9.
Arbitrary<String> notCodeString() =>
    decoderAlphabetString().filter((s) => !_fixtureCodes.contains(s));

/// One edit applied by [nearMiss]: insert a decoder-alphabet character,
/// delete one character, or replace one character.
typedef _Edit = ({String kind, String char});

final List<_Edit> _edits = List<_Edit>.unmodifiable(<_Edit>[
  for (final c in _decoderAlphabet) (kind: 'insert', char: c),
  (kind: 'delete', char: ''),
  for (final c in _decoderAlphabet) (kind: 'replace', char: c),
]);

String _applyEdit(String m, int rawIndex, _Edit edit) {
  // Deleting or replacing in an empty string is impossible; insert instead.
  final kind = m.isEmpty ? 'insert' : edit.kind;
  final char = edit.char.isEmpty ? '.' : edit.char;
  switch (kind) {
    case 'insert':
      final i = rawIndex % (m.length + 1);
      return m.substring(0, i) + char + m.substring(i);
    case 'delete':
      final i = rawIndex % m.length;
      return m.substring(0, i) + m.substring(i + 1);
    default:
      final i = rawIndex % m.length;
      return m.substring(0, i) + char + m.substring(i + 1);
  }
}

/// Encoded_Text with one random insert, delete or replace, using only
/// `.`, `-`, space and `/`. The result may or may not still be Encoded_Text.
/// REQ-DEC-10, REQ-FMT-5, REQ-FMT-6.
Arbitrary<String> nearMiss() => combine3<String, int, _Edit>(
      encodedText(),
      integer(min: 0, max: 1 << 16),
      constantFrom<_Edit>(_edits),
    ).map((r) => _applyEdit(r.$1, r.$2, r.$3));

/// One non-surrogate UTF-16 code unit other than `.`, `-`, space and `/`,
/// as a one-code-unit string. REQ-ERR-2, REQ-ERR-12.
Arbitrary<String> invalidCodeUnit() => integer(min: 0, max: 0xFFFF)
    .filter(
      (u) =>
          u != 0x2E &&
          u != 0x2D &&
          u != 0x20 &&
          u != 0x2F &&
          (u < 0xD800 || u > 0xDFFF),
    )
    .map(String.fromCharCode);

/// One `(m, i, c)` triple per case: non-empty Encoded_Text `m`, an index
/// `0 <= i < m.length`, and an invalid code unit `c` to put at `i`.
/// REQ-ERR-2, REQ-ERR-11, REQ-ERR-12.
Arbitrary<(String, int, String)> injectedInvalid() =>
    _nonEmptyEncodedText().flatMap(
      (m) => combine2<int, String>(
        integer(min: 0, max: m.length - 1),
        invalidCodeUnit(),
      ).map((r) => (m, r.$1, r.$2)),
    );

/// Returns an `onFalsify` callback that records the shrunk counterexample and
/// the seed, so a failure can be reproduced with the same seed. REQ-TEST-6.
void Function(Object?) report(int seed) =>
    (x) => printOnFailure('Falsifying example: $x, seed: $seed');
