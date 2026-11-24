import 'package:flutter_test/flutter_test.dart';
import 'package:morse_core/morse_core.dart';
import 'package:sounder/compose/sentence_text.dart';

const _unknown = DecodedItem.unknownLetter('........-');
const _space = DecodedItem.wordSpace();

List<DecodedItem> _letters(String word) =>
    [for (final c in word.split('')) DecodedItem.letter(c)];

void main() {
  group('sentenceText and speakText', () {
    final hiThere = [
      ..._letters('HI'),
      _unknown,
      _space,
      ..._letters('THERE'),
    ];

    test('REQ-KEY-11: the HI□ THERE example shows the Placeholder', () {
      expect(placeholder, '\u25A1');
      expect(sentenceText(hiThere), 'HI\u25A1 THERE');
    });

    test('REQ-SPEAK-1: the HI□ THERE example speaks HI THERE', () {
      expect(speakText(hiThere), 'HI THERE');
    });

    test(
        'REQ-SPEAK-2: speakText of only Placeholders and Word_Spaces is '
        'empty', () {
      expect(speakText([_unknown, _space, _unknown, _space, _space]), '');
    });

    test('REQ-SPEAK-2: speakText of an empty Sentence is empty', () {
      expect(speakText(const []), '');
    });
  });

  group('partialGlyphs', () {
    test('REQ-KEY-10: a dot shows as a middle dot (U+00B7)', () {
      expect(partialGlyphs('.'), '\u00B7');
    });

    test('REQ-KEY-10: a dash shows as an en dash (U+2013)', () {
      expect(partialGlyphs('-'), '\u2013');
    });

    test('REQ-KEY-10: a mixed Partial_Sequence keeps its keyed order', () {
      expect(partialGlyphs('.-..-'), '\u00B7\u2013\u00B7\u00B7\u2013');
    });

    test('REQ-KEY-10: the empty Partial_Sequence shows as an empty string', () {
      expect(partialGlyphs(''), '');
    });
  });
}
