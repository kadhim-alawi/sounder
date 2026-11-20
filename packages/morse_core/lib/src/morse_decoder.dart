import 'code_table.dart';
import 'morse_format_exception.dart';

/// Converts Encoded_Text into uppercase Plain_Text using the ITU-R M.1677-1
/// code table.
///
/// Strict: accepts exactly the REQ-FMT-1 format that `MorseEncoder` produces
/// and rejects everything else with a [MorseFormatException]. Pure and
/// synchronous. REQ-DEC-1, REQ-DEC-10, REQ-FMT-5, REQ-FMT-6, REQ-PURE-3.
final class MorseDecoder {
  /// Creates a decoder. It holds no state. REQ-DEC-1.
  const MorseDecoder();

  static const CodeTable _table = CodeTable();

  /// Decodes [morse] into uppercase Plain_Text.
  ///
  /// Returns the empty string for empty input. Throws a [MorseFormatException]
  /// with `requirementId` `'REQ-ERR-2'` for the first character other than
  /// `.`, `-`, space or `/`, carrying that character (both code units for a
  /// valid surrogate pair) and its UTF-16 index. This check runs before any
  /// structural check, so REQ-ERR-2 wins over every other error.
  ///
  /// Then checks structure and throws the structural error (REQ-ERR-3 to
  /// REQ-ERR-7) with the lowest position, breaking ties by the lower
  /// REQ-ERR number. No partial result is returned.
  ///
  /// Finally maps each Token to its uppercase character from the code table,
  /// and each Word_Separator to one space, so `-..-.` decodes to `/` while
  /// the standalone `/` Token decodes to a space. REQ-DEC-1, REQ-DEC-2,
  /// REQ-DEC-3, REQ-DEC-4, REQ-DEC-7, REQ-DEC-10, REQ-ERR-2, REQ-ERR-3,
  /// REQ-ERR-4, REQ-ERR-5, REQ-ERR-6, REQ-ERR-7, REQ-ERR-9, REQ-ERR-11,
  /// REQ-FMT-5, REQ-FMT-6.
  String decode(String morse) {
    if (morse.isEmpty) return '';
    _checkAlphabet(morse);
    return _decodeChecked(morse);
  }

  // Pass 1: throw REQ-ERR-2 at the first code unit outside `.`, `-`, space
  // and `/`. REQ-ERR-2, REQ-ERR-11.
  static void _checkAlphabet(String morse) {
    for (var i = 0; i < morse.length; i++) {
      final unit = morse.codeUnitAt(i);
      if (unit == 0x2E || unit == 0x2D || unit == 0x20 || unit == 0x2F) {
        continue;
      }
      throw MorseFormatException(
        requirementId: 'REQ-ERR-2',
        offending: _characterAt(morse, i),
        position: i,
      );
    }
  }

  // Runs pass 2, then pass 3. Pass 3 maps each token into a local buffer:
  // a `/` token (Word_Separator) becomes one space, any other token becomes
  // its character from the reverse table. The `!` is safe because pass 2
  // rejected every unknown token. The buffer is returned only after every
  // token is mapped, so no partial result escapes. REQ-DEC-1, REQ-DEC-2,
  // REQ-DEC-3, REQ-DEC-7, REQ-FMT-5, REQ-PURE-3.
  static String _decodeChecked(String morse) {
    final tokens = _checkStructure(morse);
    final buffer = StringBuffer();
    for (final token in tokens) {
      if (token.text == '/') {
        buffer.write(' ');
      } else {
        buffer.write(_table.characterFor(token.text)!);
      }
    }
    return buffer.toString();
  }

  // Pass 2: one walk over [morse] (already limited to `.`, `-`, space and
  // `/` by pass 1) that records tokens and collects every structural error
  // candidate, then throws the one with the smallest (position, errNumber).
  // Returns the tokens in order when no rule fires. REQ-ERR-3 to REQ-ERR-7,
  // REQ-ERR-9, REQ-ERR-11, REQ-DEC-10, REQ-FMT-6.
  static List<_Token> _checkStructure(String morse) {
    final last = morse.length - 1;
    final tokens = <_Token>[];
    final candidates = <_Candidate>[];
    var doubleSpaceSeen = false;

    var i = 0;
    while (i <= last) {
      if (morse.codeUnitAt(i) == 0x20) {
        // REQ-ERR-5: second space of the first run of two or more spaces.
        if (!doubleSpaceSeen && i > 0 && morse.codeUnitAt(i - 1) == 0x20) {
          doubleSpaceSeen = true;
          candidates.add(_Candidate(i, 5, ' '));
        }
        i++;
        continue;
      }
      final start = i;
      while (i <= last && morse.codeUnitAt(i) != 0x20) {
        i++;
      }
      final token = _Token(start, morse.substring(start, i));
      final text = token.text;
      if (text == '/') {
        // REQ-ERR-7: a `/` token right after a `/` token, one space between.
        if (tokens.isNotEmpty) {
          final previous = tokens.last;
          if (previous.text == '/' && previous.start + 2 == start) {
            candidates.add(_Candidate(start, 7, '/'));
          }
        }
      } else if (text.contains('/')) {
        // REQ-ERR-4: a token containing `/` that is not exactly `/`.
        candidates.add(_Candidate(start, 4, text));
      } else if (_table.characterFor(text) == null) {
        // REQ-ERR-3: a symbol-only token that is not a Morse_Code.
        candidates.add(_Candidate(start, 3, text));
      }
      tokens.add(token);
    }

    // REQ-ERR-6: leading space or `/` token at 0; trailing space or `/`
    // token at length - 1.
    // A string of only spaces has no tokens; the space checks cover it.
    final first = morse[0];
    if (first == ' ' ||
        (tokens.isNotEmpty &&
            tokens.first.start == 0 &&
            tokens.first.text == '/')) {
      candidates.add(_Candidate(0, 6, first));
    }
    final end = morse[last];
    if (end == ' ' ||
        (tokens.isNotEmpty &&
            tokens.last.start == last &&
            tokens.last.text == '/')) {
      candidates.add(_Candidate(last, 6, end));
    }

    if (candidates.isNotEmpty) {
      var chosen = candidates.first;
      for (final candidate in candidates.skip(1)) {
        if (candidate.position < chosen.position ||
            (candidate.position == chosen.position &&
                candidate.errNumber < chosen.errNumber)) {
          chosen = candidate;
        }
      }
      throw MorseFormatException(
        requirementId: 'REQ-ERR-${chosen.errNumber}',
        offending: chosen.offending,
        position: chosen.position,
      );
    }
    return tokens;
  }

  // The code point starting at [i]: both code units for a valid surrogate
  // pair, otherwise the single code unit. REQ-ERR-2.
  static String _characterAt(String text, int i) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < text.length) {
      final next = text.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) return text.substring(i, i + 2);
    }
    return text[i];
  }
}

// A maximal run of non-space characters and its start index. REQ-DEC-1.
final class _Token {
  const _Token(this.start, this.text);

  final int start;
  final String text;
}

// One structural error that pass 2 found: where, which REQ-ERR rule, and the
// offending space, `/` or Token. REQ-ERR-11.
final class _Candidate {
  const _Candidate(this.position, this.errNumber, this.offending);

  final int position;
  final int errNumber;
  final String offending;
}
