/// The Morse_Format_Error raised by `MorseEncoder` and `MorseDecoder` for
/// invalid input.
///
/// It extends `FormatException`, so callers can catch it either as
/// `on MorseFormatException` or `on FormatException`. It never stores the
/// encoder or decoder input: [source] is always null and [toString] returns
/// [message] only, so logging the exception cannot leak what the user typed.
/// REQ-ERR-8, REQ-ERR-9.
final class MorseFormatException extends FormatException {
  /// Creates the error for one offending character or Token at [position].
  ///
  /// Passes the built message, `null` as the inherited `source`, and
  /// [position] as the inherited `offset`. This constructor must never
  /// forward the encoder or decoder input to `source`. REQ-ERR-8, REQ-ERR-9.
  MorseFormatException({
    required this.requirementId,
    required this.offending,
    required this.position,
  }) : super(_message(requirementId, offending, position), null, position);

  /// The requirement that defines this error kind, for example `'REQ-ERR-3'`.
  ///
  /// Two errors of the same kind carry the same value. REQ-PURE-2.
  final String requirementId;

  /// The offending character or Token, verbatim.
  ///
  /// A character is one code point: one code unit, a valid surrogate pair
  /// (two code units), or a lone surrogate (one code unit). A Token is the
  /// whole run of non-space characters. REQ-ERR-1, REQ-ERR-2, REQ-ERR-3,
  /// REQ-ERR-4, REQ-ERR-5, REQ-ERR-6, REQ-ERR-7.
  final String offending;

  /// Zero-based position in the input, counted in UTF-16 code units.
  ///
  /// Always in the range 0 to the input length minus 1, and equal to the
  /// inherited `offset`. REQ-ERR-8.
  final int position;

  /// Returns [message] only; never includes the input string. REQ-ERR-8.
  @override
  String toString() => message;
}

// Builds the English message for an error. Every message contains the
// position in decimal. Token errors quote the Token; single-character errors
// use U+XXXX; a lone surrogate is never written verbatim. REQ-ERR-8.
String _message(String requirementId, String offending, int position) {
  switch (requirementId) {
    case 'REQ-ERR-1':
      return 'Unsupported character ${_codePoint(offending)} '
          'at position $position.';
    case 'REQ-ERR-2':
      return 'Invalid character ${_codePoint(offending)} at position '
          '$position; Morse code uses only dots, dashes, spaces and '
          '"/" (U+002F).';
    case 'REQ-ERR-3':
      return 'Unknown Morse code "$offending" at position $position.';
    case 'REQ-ERR-4':
      return 'Invalid token "$offending" at position $position; '
          '"/" (U+002F) must stand alone as a word separator.';
    case 'REQ-ERR-5':
      return 'Extra space ${_codePoint(offending)} at position $position; '
          'letters are separated by one space.';
    case 'REQ-ERR-6':
      final where = position == 0 ? 'start' : 'end';
      if (offending == '/') {
        return 'Word separator ${_describe(offending)} at $where, '
            'position $position.';
      }
      final kind = position == 0 ? 'Leading' : 'Trailing';
      return '$kind space ${_codePoint(offending)} at $where, '
          'position $position.';
    case 'REQ-ERR-7':
      return 'Empty word: word separator ${_describe(offending)} '
          'repeated at position $position.';
    default:
      return 'Morse format error: ${_describe(offending)} '
          'at position $position.';
  }
}

// Describes an offending value for the default and separator messages:
// `"/" (U+002F)` for the slash, U+XXXX for any other single code point,
// and the quoted Token otherwise. REQ-ERR-8.
String _describe(String offending) {
  if (offending == '/') return '"/" (U+002F)';
  if (_isSingleCodePoint(offending)) return _codePoint(offending);
  return '"$offending"';
}

// True if [s] is one code unit or one valid surrogate pair.
bool _isSingleCodePoint(String s) =>
    s.length == 1 ||
    (s.length == 2 &&
        _isHighSurrogate(s.codeUnitAt(0)) &&
        _isLowSurrogate(s.codeUnitAt(1)));

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

// Formats the first code point of [s] as U+XXXX: uppercase hex, at least four
// digits. A valid surrogate pair gives its combined code point; a lone
// surrogate gives its own code unit. REQ-ERR-8.
String _codePoint(String s) {
  if (s.isEmpty) return 'U+0000';
  final first = s.codeUnitAt(0);
  var value = first;
  if (s.length >= 2 && _isHighSurrogate(first)) {
    final second = s.codeUnitAt(1);
    if (_isLowSurrogate(second)) {
      value = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00);
    }
  }
  return 'U+${value.toRadixString(16).toUpperCase().padLeft(4, '0')}';
}
