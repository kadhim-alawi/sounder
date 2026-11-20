import 'code_table.dart';
import 'morse_format_exception.dart';

/// Converts Plain_Text into Encoded_Text using the ITU-R M.1677-1 code table.
///
/// Letters are joined by one space (Letter_Gap) and words by `' / '`
/// (Word_Separator). Leading, trailing and repeated spaces are collapsed, and
/// lowercase `a`-`z` encode like `A`-`Z`. Pure and synchronous.
/// REQ-ENC-1, REQ-ENC-3, REQ-ENC-4, REQ-FMT-2, REQ-PURE-3.
final class MorseEncoder {
  /// Creates an encoder. It holds no state. REQ-ENC-1.
  const MorseEncoder();

  static const CodeTable _table = CodeTable();

  /// Encodes [text] into Encoded_Text.
  ///
  /// Returns the empty string for empty or all-space input. Throws a
  /// [MorseFormatException] with `requirementId` `'REQ-ERR-1'` for the first
  /// Unsupported_Character, carrying that character (both code units for a
  /// valid surrogate pair) and its UTF-16 index. No partial result is
  /// returned. REQ-ENC-1, REQ-ENC-2, REQ-ENC-3, REQ-ENC-4, REQ-ENC-5,
  /// REQ-ENC-6, REQ-ENC-7, REQ-ENC-10, REQ-ENC-11, REQ-FMT-2, REQ-ERR-1,
  /// REQ-ERR-9, REQ-ERR-10.
  String encode(String text) {
    final buffer = StringBuffer();
    var gapPending = false;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x20) {
        // Spaces before the first code never open a gap. REQ-ENC-6.
        if (buffer.isNotEmpty) gapPending = true;
        continue;
      }
      final code = _table.codeFor(text[i]);
      if (code == null) {
        throw MorseFormatException(
          requirementId: 'REQ-ERR-1',
          offending: _characterAt(text, i),
          position: i,
        );
      }
      if (buffer.isNotEmpty) buffer.write(gapPending ? ' / ' : ' ');
      buffer.write(code);
      gapPending = false;
    }
    return buffer.toString();
  }

  // The code point starting at [i]: both code units for a valid surrogate
  // pair, otherwise the single code unit. REQ-ERR-1.
  static String _characterAt(String text, int i) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < text.length) {
      final next = text.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) return text.substring(i, i + 2);
    }
    return text[i];
  }
}
