import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

void main() {
  // Decoder examples. REQ-TEST-2.
  group('MorseDecoder', () {
    const decoder = MorseDecoder();

    test('REQ-DEC-3 the code -..-. inside a word decodes to /', () {
      expect(decoder.decode('.- -..-. -... / ----.'), equals('A/B 9'));
    });

    test('REQ-DEC-4 REQ-TEST-2 empty input decodes to empty string', () {
      expect(decoder.decode(''), equals(''));
    });

    test('REQ-DEC-5 REQ-TEST-2 ... --- ... decodes to SOS', () {
      expect(decoder.decode('... --- ...'), equals('SOS'));
    });

    test('REQ-DEC-6 REQ-TEST-2 slash and brackets decode to "/ ()"', () {
      final result = decoder.decode('-..-. / -.--. -.--.-');
      expect(result, equals('/ ()'));
      expect(result.length, equals(4));
    });

    test('REQ-DEC-8 hello world decodes to HELLO WORLD', () {
      expect(
        decoder.decode('.... . .-.. .-.. --- / .-- --- .-. .-.. -..'),
        equals('HELLO WORLD'),
      );
    });

    test('REQ-DEC-9 digits and punctuation decode to "123 .,?-"', () {
      expect(
        decoder.decode('.---- ..--- ...-- / .-.-.- --..-- ..--.. -....-'),
        equals('123 .,?-'),
      );
    });
  });
}
