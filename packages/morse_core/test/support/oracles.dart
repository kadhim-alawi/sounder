/// Independent test oracles for the morse-core property tests.
///
/// These helpers deliberately do not import `package:morse_core`. They check
/// the engine against the ITU fixture and the requirement text, so a bug in
/// `lib/` cannot make its own tests pass.
library;

import 'itu_fixture.dart';

/// The 43 Morse_Codes from the ITU fixture. REQ-FMT-1.
final Set<String> _fixtureCodes = Set<String>.unmodifiable(ituFixture.values);

/// Whether [s] conforms to the Encoded_Text grammar of REQ-FMT-1:
///
/// ```
/// encoded = "" | word *( " / " word )
/// word    = code *( " " code )
/// code    = one of the 43 values in the ITU fixture
/// ```
///
/// No fixture code contains a space or `/`, so splitting on `" / "` and then
/// on `" "` is the exact inverse of joining. Any leading, trailing or doubled
/// space, empty word, stray `/` or other character leaves a piece that is not
/// a fixture code, and the check fails. REQ-FMT-1.
bool isEncodedText(String s) {
  if (s.isEmpty) return true;
  for (final word in s.split(' / ')) {
    for (final code in word.split(' ')) {
      if (!_fixtureCodes.contains(code)) return false;
    }
  }
  return true;
}

/// Maps `a`-`z` to `A`-`Z` by code unit arithmetic and leaves every other
/// code unit unchanged. Never calls `toUpperCase()`, which would fold
/// characters such as `ı` and `ß`. REQ-ENC-11.
String asciiUpper(String s) {
  final units = s.codeUnits;
  final out = List<int>.filled(units.length, 0);
  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    out[i] = (u >= 0x61 && u <= 0x7A) ? u - 0x20 : u;
  }
  return String.fromCharCodes(out);
}

/// The Normalised_Text of [s]: [asciiUpper], then leading and trailing
/// spaces (U+0020 only) removed and every run of spaces replaced by one
/// space. Other whitespace is left untouched. REQ-FMT-3.
String normalise(String s) {
  final words = asciiUpper(s).split(' ').where((w) => w.isNotEmpty);
  return words.join(' ');
}
