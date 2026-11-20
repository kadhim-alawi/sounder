import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

void main() {
  // Exception value and message format. REQ-ERR-8.
  group('MorseFormatException', () {
    MorseFormatException make(String id, String offending, int position) =>
        MorseFormatException(
          requirementId: id,
          offending: offending,
          position: position,
        );

    test('REQ-ERR-8 unsupported character message uses U+XXXX', () {
      final e = make('REQ-ERR-1', 'é', 1);
      expect(e.message, 'Unsupported character U+00E9 at position 1.');
    });

    test('REQ-ERR-8 unknown Morse code message quotes the Token', () {
      final e = make('REQ-ERR-3', '......', 4);
      expect(e.message, 'Unknown Morse code "......" at position 4.');
    });

    test('REQ-ERR-8 extra space message', () {
      final e = make('REQ-ERR-5', ' ', 4);
      expect(
        e.message,
        'Extra space U+0020 at position 4; letters are separated by one space.',
      );
    });

    test('REQ-ERR-8 trailing word separator message', () {
      final e = make('REQ-ERR-6', '/', 4);
      expect(e.message, 'Word separator "/" (U+002F) at end, position 4.');
    });

    test('REQ-ERR-8 surrogate pair renders as its combined code point', () {
      final e = make('REQ-ERR-1', '😀', 3);
      expect(e.message, contains('U+1F600'));
      expect(e.message, contains('3'));
    });

    test('REQ-ERR-8 lone surrogate renders as U+D800, never verbatim', () {
      final e = make('REQ-ERR-1', '\uD800', 0);
      expect(e.message, contains('U+D800'));
      expect(e.message.codeUnits, isNot(contains(0xD800)));
    });

    test('REQ-ERR-8 offset equals position, source is null, '
        'toString equals message', () {
      final e = make('REQ-ERR-3', '......', 4);
      expect(e.offset, e.position);
      expect(e.offset, 4);
      expect(e.source, isNull);
      expect(e.toString(), e.message);
      expect(e.requirementId, 'REQ-ERR-3');
      expect(e.offending, '......');
      expect(e, isA<FormatException>());
    });
  });

  // Encoder rejects the first Unsupported_Character. REQ-ERR-1, REQ-ERR-9.
  group('MorseEncoder errors', () {
    const encoder = MorseEncoder();

    // Calls encode and asserts it throws exactly one REQ-ERR-1 error with the
    // given offending value and position, and returns no value. REQ-ERR-9.
    void expectErr1(String input, String offending, int position) {
      String? result;
      MorseFormatException? error;
      try {
        result = encoder.encode(input);
      } on MorseFormatException catch (e) {
        error = e;
      }
      expect(result, isNull, reason: 'no value may be returned');
      expect(error, isNotNull, reason: 'a MorseFormatException is expected');
      expect(error!.requirementId, 'REQ-ERR-1');
      expect(error.offending, offending);
      expect(error.offending.codeUnits, offending.codeUnits);
      expect(error.position, position);
    }

    test('REQ-ERR-1 REQ-ERR-9 accented letter é at position 1', () {
      expectErr1('hé', '\u00E9', 1);
    });

    test('REQ-ERR-1 REQ-ERR-9 tab is unsupported', () {
      expectErr1('a\tb', '\t', 1);
    });

    test('REQ-ERR-1 REQ-ERR-9 dotless ı is not folded to I', () {
      expectErr1('\u0131', '\u0131', 0);
    });

    test('REQ-ERR-1 REQ-ERR-9 surrogate pair 😀 carries both code units '
        'at the high surrogate index', () {
      expectErr1('ok \uD83D\uDE00', '\uD83D\uDE00', 3);
    });

    test('REQ-ERR-1 REQ-ERR-9 lone surrogate carries one code unit', () {
      expectErr1('a\uD800b', '\uD800', 1);
    });
  });
}
