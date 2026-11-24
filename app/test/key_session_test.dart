import 'package:flutter_test/flutter_test.dart';
import 'package:morse_core/morse_core.dart';
import 'package:sounder/compose/key_session.dart';

const _e = DecodedItem.letter('E');
const _t = DecodedItem.letter('T');

/// Keys one press from [start] to [end] and advances to [settleAt].
void _key(KeySession session, int start, int end, int settleAt) {
  expect(session.press(start), isTrue);
  expect(session.release(end), isTrue);
  session.advanceTo(settleAt);
}

void main() {
  group('KeySession default Calibration', () {
    test('REQ-KEY-6: the default Calibration constants have the K2 values', () {
      expect(defaultDitLength, 100000);
      expect(defaultDahLength, 300000);
      expect(defaultSymbolGap, 250000);
      expect(defaultLetterGap, 700000);
      expect(TimingConfig.defaults.debounceTime, 30000);
      expect(TimingConfig.defaults.wordGapFactor, 2.0);
    });

    // Press_Threshold = ceil((100,000 + 300,000) / 2) = 200,000.
    test('REQ-KEY-6: a press below 200,000 µs is a dit and at 200,000 µs is '
        'a dah', () {
      final dit = KeySession();
      _key(dit, 0, 199999, 199999 + 475000);
      expect(dit.sentence, [_e]);

      final dah = KeySession();
      _key(dah, 0, 200000, 200000 + 475000);
      expect(dah.sentence, [_t]);
    });

    // Letter_Gap_Threshold = ceil((250,000 + 700,000) / 2) = 475,000.
    test('REQ-KEY-6: a letter completes exactly 475,000 µs after the last '
        'release', () {
      final session = KeySession();
      _key(session, 0, 100000, 100000 + 474999);
      expect(session.sentence, isEmpty);
      expect(session.partialSequence, '.');

      session.advanceTo(100000 + 475000);
      expect(session.sentence, [_e]);
      expect(session.partialSequence, isEmpty);
    });

    // Debounce_Time = 30,000 from TimingConfig.defaults.
    test('REQ-KEY-6: a press shorter than 30,000 µs is discarded as bounce',
        () {
      final bounce = KeySession();
      _key(bounce, 0, 29999, 29999 + 30000);
      expect(bounce.partialSequence, isEmpty);

      final kept = KeySession();
      _key(kept, 0, 30000, 30000 + 30000);
      expect(kept.partialSequence, '.');
    });

    // Word_Gap_Threshold = 2.0 × 700,000 = 1,400,000.
    test('REQ-KEY-6: a gap of 1,400,000 µs between presses adds a Word_Space',
        () {
      final word = KeySession();
      _key(word, 0, 100000, 600000);
      _key(word, 100000 + 1400000, 1600000, 1600000 + 475000);
      expect(word.sentence, [_e, const DecodedItem.wordSpace(), _e]);

      final letter = KeySession();
      _key(letter, 0, 100000, 600000);
      _key(letter, 100000 + 1399999, 1599999, 1599999 + 475000);
      expect(letter.sentence, [_e, _e]);
    });

    test('REQ-KEY-6: press at 0, release at 100,000 and advanceTo 800,000 '
        'gives E', () {
      final session = KeySession();
      expect(session.press(0), isTrue);
      expect(session.isPressed, isTrue);
      expect(session.release(100000), isTrue);
      expect(session.isPressed, isFalse);
      session.advanceTo(800000);

      expect(session.sentence, [_e]);
      expect(session.partialSequence, isEmpty);
    });
  });

  group('KeySession rejected calls', () {
    test('REQ-KEY-7: a second press while held returns false and changes '
        'nothing', () {
      final session = KeySession();
      _key(session, 0, 100000, 600000);
      expect(session.sentence, [_e]);

      expect(session.press(700000), isTrue);
      final sentenceBefore = session.sentence;
      final partialBefore = session.partialSequence;

      expect(session.press(750000), isFalse);
      expect(session.sentence, sentenceBefore);
      expect(session.partialSequence, partialBefore);
      expect(session.isPressed, isTrue);
    });

    test('REQ-KEY-7: after a rejected press the session accepts the next '
        'valid call', () {
      final session = KeySession();
      expect(session.press(0), isTrue);
      expect(session.press(50000), isFalse);

      expect(session.release(100000), isTrue);
      expect(session.isPressed, isFalse);
      session.advanceTo(800000);
      expect(session.sentence, [_e]);
    });

    test('REQ-KEY-7: a release with no press returns false and changes '
        'nothing', () {
      final session = KeySession();
      expect(session.release(0), isFalse);
      expect(session.sentence, isEmpty);
      expect(session.partialSequence, isEmpty);
      expect(session.isPressed, isFalse);

      _key(session, 10000, 110000, 810000);
      expect(session.sentence, [_e]);
    });
  });
}
