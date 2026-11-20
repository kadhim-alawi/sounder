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
}
