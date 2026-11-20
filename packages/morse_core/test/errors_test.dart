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

  // Decoder rejects non-conforming Encoded_Text. REQ-ERR-2 to REQ-ERR-9,
  // REQ-ERR-11.
  group('MorseDecoder errors', () {
    const decoder = MorseDecoder();

    // Calls decode, asserts it throws exactly one MorseFormatException with
    // the given kind, offending value and position, and returns no value.
    // Returns the error for further checks. REQ-ERR-9.
    MorseFormatException expectErr(
      String input,
      String requirementId,
      String offending,
      int position,
    ) {
      String? result;
      MorseFormatException? error;
      try {
        result = decoder.decode(input);
      } on MorseFormatException catch (e) {
        error = e;
      }
      expect(result, isNull, reason: 'no value may be returned');
      expect(error, isNotNull, reason: 'a MorseFormatException is expected');
      expect(error!.requirementId, requirementId);
      expect(error.offending, offending);
      expect(error.offending.codeUnits, offending.codeUnits);
      expect(error.position, position);
      return error;
    }

    test('REQ-ERR-2 REQ-ERR-9 letter inside valid input at its index', () {
      expectErr('... a ---', 'REQ-ERR-2', 'a', 4);
    });

    test('REQ-ERR-2 REQ-ERR-9 surrogate pair carries both code units '
        'at the high surrogate index', () {
      expectErr('.- \uD83D\uDE00 -', 'REQ-ERR-2', '\uD83D\uDE00', 3);
    });

    test('REQ-ERR-3 REQ-ERR-9 unknown Token ...... at 4', () {
      expectErr('... ...... ...', 'REQ-ERR-3', '......', 4);
    });

    test('REQ-ERR-4 REQ-ERR-9 Token /. at its start', () {
      expectErr('... /.', 'REQ-ERR-4', '/.', 4);
    });

    test('REQ-ERR-4 REQ-ERR-9 Token -/ at its start', () {
      expectErr('-/', 'REQ-ERR-4', '-/', 0);
    });

    test('REQ-ERR-4 REQ-ERR-9 Token // at its start', () {
      expectErr('.- // -', 'REQ-ERR-4', '//', 3);
    });

    test('REQ-ERR-5 REQ-ERR-9 double space at the second space, 4', () {
      expectErr('...  ---', 'REQ-ERR-5', ' ', 4);
    });

    test('REQ-ERR-6 REQ-ERR-9 leading space at 0', () {
      expectErr(' ...', 'REQ-ERR-6', ' ', 0);
    });

    test('REQ-ERR-6 REQ-ERR-9 trailing / Token at 4', () {
      expectErr('... /', 'REQ-ERR-6', '/', 4);
    });

    test('REQ-ERR-6 REQ-ERR-9 lone / Token at 0', () {
      expectErr('/', 'REQ-ERR-6', '/', 0);
    });

    test('REQ-ERR-7 REQ-ERR-9 empty word gives second / at 6', () {
      expectErr('... / / ...', 'REQ-ERR-7', '/', 6);
    });

    test('REQ-ERR-11 REQ-ERR-9 tie at 6 picks REQ-ERR-6 over REQ-ERR-7', () {
      expectErr('... / /', 'REQ-ERR-6', '/', 6);
    });

    test('REQ-ERR-8 exact decoder messages; source null; toString is the '
        'message and omits the input', () {
      final cases = <(String, String, String, String, int)>[
        (
          '... ...... ...',
          'REQ-ERR-3',
          '......',
          'Unknown Morse code "......" at position 4.',
          4,
        ),
        (
          '...  ---',
          'REQ-ERR-5',
          ' ',
          'Extra space U+0020 at position 4; '
              'letters are separated by one space.',
          4,
        ),
        (
          '... /',
          'REQ-ERR-6',
          '/',
          'Word separator "/" (U+002F) at end, position 4.',
          4,
        ),
      ];
      for (final (input, id, offending, message, position) in cases) {
        final e = expectErr(input, id, offending, position);
        expect(e.message, message);
        expect(e.source, isNull);
        expect(e.offset, position);
        expect(e.toString(), e.message);
        expect(e.toString(), isNot(contains(input)));
      }
    });
  });
}
