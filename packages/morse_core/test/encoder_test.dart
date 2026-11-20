import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

void main() {
  // Encoder examples. REQ-TEST-2.
  group('MorseEncoder', () {
    const encoder = MorseEncoder();

    test('REQ-ENC-7 empty and all-space input encode to empty string', () {
      expect(encoder.encode(''), equals(''));
      expect(encoder.encode('   '), equals(''));
    });

    test('REQ-ENC-8 SOS encodes to ... --- ...', () {
      expect(encoder.encode('SOS'), equals('... --- ...'));
    });

    test('REQ-ENC-9 hello world encodes with a word separator', () {
      expect(
        encoder.encode('hello world'),
        equals('.... . .-.. .-.. --- / .-- --- .-. .-.. -..'),
      );
    });

    test('REQ-ENC-12 leading, trailing and repeated spaces collapse', () {
      expect(
        encoder.encode('  Hi   there '),
        equals('.... .. / - .... . .-. .'),
      );
    });

    test('REQ-ENC-13 slash and digit encode as characters', () {
      expect(encoder.encode('a/b 9'), equals('.- -..-. -... / ----.'));
    });

    test('REQ-FMT-7 " e  t " encodes to ". / -" of length 5', () {
      final result = encoder.encode(' e  t ');
      expect(result, equals('. / -'));
      expect(result.length, equals(5));
    });
  });
}
