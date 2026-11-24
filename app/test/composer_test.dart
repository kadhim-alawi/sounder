import 'package:flutter_test/flutter_test.dart';
import 'package:morse_core/morse_core.dart';
import 'package:sounder/compose/composer.dart';

const _h = DecodedItem.letter('H');
const _i = DecodedItem.letter('I');
const _unknown = DecodedItem.unknownLetter('........-');
const _space = DecodedItem.wordSpace();

Composer _composerWith(List<DecodedItem> items) {
  final composer = Composer();
  items.forEach(composer.append);
  return composer;
}

void main() {
  group('Composer', () {
    test('REQ-COMPOSE-2: append adds each item at the end, in order', () {
      final composer = Composer();
      expect(composer.sentence, isEmpty);

      composer.append(_h);
      expect(composer.sentence, [_h]);

      composer.append(_i);
      expect(composer.sentence, [_h, _i]);

      composer.append(_space);
      composer.append(_unknown);
      expect(composer.sentence, [_h, _i, _space, _unknown]);
    });

    test('REQ-COMPOSE-2: append leaves a previously returned Sentence unchanged',
        () {
      final composer = _composerWith([_h, _i]);
      final before = composer.sentence;

      composer.append(_space);

      expect(before, [_h, _i]);
      expect(composer.sentence, [_h, _i, _space]);
    });

    test('REQ-COMPOSE-3: undo removes only the last Letter_Item', () {
      final composer = _composerWith([_h, _space, _i]);
      composer.undo();
      expect(composer.sentence, [_h, _space]);
    });

    test('REQ-COMPOSE-3: undo removes only the last Unknown_Letter_Item', () {
      final composer = _composerWith([_h, _i, _unknown]);
      composer.undo();
      expect(composer.sentence, [_h, _i]);
    });

    test('REQ-COMPOSE-3: undo removes only the last Word_Space', () {
      final composer = _composerWith([_h, _i, _space]);
      composer.undo();
      expect(composer.sentence, [_h, _i]);
    });

    test('REQ-COMPOSE-3: undo on an empty Sentence raises nothing', () {
      final composer = Composer();
      expect(composer.undo, returnsNormally);
      expect(composer.sentence, isEmpty);
    });

    test('REQ-COMPOSE-3: undo past the start leaves the Sentence empty', () {
      final composer = _composerWith([_h]);
      composer.undo();
      expect(composer.undo, returnsNormally);
      expect(composer.sentence, isEmpty);
    });

    test('REQ-COMPOSE-4: clear makes the Sentence empty', () {
      final composer = _composerWith([_h, _i, _space, _unknown]);
      composer.clear();
      expect(composer.sentence, isEmpty);
    });

    test('REQ-COMPOSE-4: clear on an empty Sentence raises nothing', () {
      final composer = Composer();
      expect(composer.clear, returnsNormally);
      expect(composer.sentence, isEmpty);
    });

    test('REQ-COMPOSE-4: append after clear starts a new Sentence', () {
      final composer = _composerWith([_h, _i]);
      composer.clear();
      composer.append(_i);
      expect(composer.sentence, [_i]);
    });

    test(
        'REQ-COMPOSE-5: the returned Sentence is unmodifiable and mutating it '
        'leaves the Composer unchanged', () {
      final composer = _composerWith([_h, _i]);
      final sentence = composer.sentence;

      expect(() => sentence.add(_space), throwsUnsupportedError);
      expect(() => sentence.removeLast(), throwsUnsupportedError);
      expect(() => sentence.clear(), throwsUnsupportedError);
      expect(() => sentence[0] = _unknown, throwsUnsupportedError);

      expect(composer.sentence, [_h, _i]);
    });
  });
}
