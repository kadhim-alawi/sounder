import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

import 'support/timing_oracles.dart';

// The reference Calibration of REQ-BATCH-5. With the default Timing_Config:
// Debounce_Time 30,000, Press_Threshold 200,000, Letter_Gap_Threshold
// 475,000, Word_Gap_Threshold 1,400,000.
const _cal = (
  ditLength: 100000,
  dahLength: 300000,
  symbolGap: 250000,
  letterGap: 700000,
);

LiveDecoder _decoder() => LiveDecoder(
  Calibration(
    ditLength: _cal.ditLength,
    dahLength: _cal.dahLength,
    symbolGap: _cal.symbolGap,
    letterGap: _cal.letterGap,
  ),
  TimingConfig.defaults,
);

const _space = DecodedItem.wordSpace();
DecodedItem _l(String c) => DecodedItem.letter(c);

/// A copy of the observable state, for before/after comparison.
typedef _State = (
  List<DecodedItem> items,
  String partial,
  bool pressed,
  int? latest,
);

_State _snapshot(LiveDecoder d) => (
  List<DecodedItem>.of(d.items),
  d.partialSequence,
  d.isPressed,
  d.latestTimestamp,
);

void _expectState(LiveDecoder d, _State s) {
  expect(d.items, equals(s.$1));
  expect(d.partialSequence, s.$2);
  expect(d.isPressed, s.$3);
  expect(d.latestTimestamp, s.$4);
}

Matcher _timingError(TimingInputErrorKind kind, int? index) =>
    throwsA(
      isA<TimingInputException>()
          .having((e) => e.kind, 'kind', kind)
          .having((e) => e.index, 'index', index),
    );

/// Decoder holding items [E], Partial_Sequence `.`, not pressed, latest
/// timestamp 1,030,000, after four accepted events.
LiveDecoder _midLetterDecoder() {
  final d = _decoder()
    ..press(0)
    ..release(100000)
    ..advanceTo(800000)
    ..press(900000)
    ..release(1000000)
    ..advanceTo(1030000);
  expect(d.items, equals([_l('E')]));
  expect(d.partialSequence, '.');
  return d;
}

void main() {
  group('LiveDecoder', () {
    test('REQ-LIVE-2 a new decoder is empty and not pressed, and reading '
        'does not change it', () {
      final d = _decoder();
      for (var i = 0; i < 2; i++) {
        expect(d.items, isEmpty);
        expect(d.partialSequence, isEmpty);
        expect(d.isPressed, isFalse);
        expect(d.latestTimestamp, isNull);
      }
    });

    test('REQ-LIVE-3 press reports pressed and release reports not pressed '
        'before the call returns', () {
      final d = _decoder()..press(0);
      expect(d.isPressed, isTrue);
      d.release(100000);
      expect(d.isPressed, isFalse);
      d.press(400000);
      expect(d.isPressed, isTrue);
    });

    test('REQ-LIVE-4 REQ-LIVE-12 a dit is confirmed only once the '
        'Debounce_Time has passed after its release', () {
      final d = _decoder()
        ..press(0)
        ..release(100000)
        ..advanceTo(129999);
      expect(d.partialSequence, isEmpty);
      d.advanceTo(130000);
      expect(d.partialSequence, '.');
      expect(d.items, isEmpty);
      expect(d.isPressed, isFalse);
    });

    test('REQ-LIVE-12 press 0, release 100,000, advanceTo 130,000 holds a '
        'Partial_Sequence of a dit', () {
      final d = _decoder()
        ..press(0)
        ..release(100000)
        ..advanceTo(130000);
      expect(d.partialSequence, '.');
      expect(d.items, isEmpty);
      expect(d.isPressed, isFalse);
    });

    test('REQ-LIVE-13 advanceTo 800,000 after REQ-LIVE-12 completes the '
        'letter E', () {
      final d = _decoder()
        ..press(0)
        ..release(100000)
        ..advanceTo(130000)
        ..advanceTo(800000);
      expect(d.items, equals([_l('E')]));
      expect(d.partialSequence, isEmpty);
    });

    test('REQ-LIVE-5 a press less than the Debounce_Time after a release '
        'merges with the previous Press', () {
      final d = _decoder()
        ..press(0)
        ..release(150000)
        ..press(160000);
      expect(d.partialSequence, isEmpty);
      d
        ..release(300000)
        ..advanceTo(329999);
      expect(d.partialSequence, isEmpty);
      // One merged Press of 300,000 is a dah, not two dits.
      d.advanceTo(330000);
      expect(d.partialSequence, '-');
      d.advanceTo(2000000);
      expect(d.items, equals([_l('T')]));
    });

    test('REQ-LIVE-6 silence of the Letter_Gap_Threshold with no '
        'Pending_Press completes the letter', () {
      final d = _decoder()
        ..press(0)
        ..release(100000)
        ..advanceTo(574999);
      expect(d.partialSequence, '.');
      expect(d.items, isEmpty);
      d.advanceTo(575000);
      expect(d.items, equals([_l('E')]));
      expect(d.partialSequence, isEmpty);
    });

    test('REQ-LIVE-6 a press call after a between-letters Gap completes the '
        'letter before the new Symbol', () {
      final d = _decoder()
        ..press(0)
        ..release(100000)
        ..press(575000);
      expect(d.items, equals([_l('E')]));
      expect(d.partialSequence, isEmpty);
      d
        ..release(875000)
        ..advanceTo(905000);
      expect(d.partialSequence, '-');
      expect(d.items, equals([_l('E')]));
    });

    test('REQ-LIVE-6 a dah held across the Letter_Gap_Threshold stays in its '
        'letter, measured to the Pending_Press press timestamp', () {
      final d = _decoder()
        ..press(0)
        ..release(100000)
        ..advanceTo(130000)
        // Gap 300,000: inside the letter.
        ..press(400000)
        ..advanceTo(700000)
        ..release(700000)
        // 610,000 since the dit's release, but the dah is still pending.
        ..advanceTo(710000);
      expect(d.items, isEmpty);
      expect(d.partialSequence, '.');
      d.advanceTo(730000);
      expect(d.items, isEmpty);
      expect(d.partialSequence, '.-');
      d.advanceTo(730000 + 475000);
      expect(d.items, equals([_l('A')]));
      expect(d.partialSequence, isEmpty);
    });

    test('REQ-LIVE-7 a Word_Space is appended when the first Symbol of the '
        'next letter is confirmed after a word-length Gap', () {
      final d = _decoder()
        ..press(0)
        ..release(300000)
        ..advanceTo(5000000);
      // Silence alone completes T but adds no Word_Space.
      expect(d.items, equals([_l('T')]));
      d
        ..press(5000000)
        ..release(5100000);
      expect(d.items, equals([_l('T')]));
      d.advanceTo(5130000);
      expect(d.items, equals([_l('T'), _space]));
      expect(d.partialSequence, '.');
      d.advanceTo(9000000);
      expect(d.items, equals([_l('T'), _space, _l('E')]));
    });

    test('REQ-LIVE-7 a Gap one below the Word_Gap_Threshold adds no '
        'Word_Space and a Gap equal to it adds one', () {
      final below = _decoder()
        ..press(0)
        ..release(300000)
        ..press(300000 + 1399999)
        ..release(300000 + 1399999 + 100000)
        ..advanceTo(5000000);
      expect(below.items, equals([_l('T'), _l('E')]));

      final at = _decoder()
        ..press(0)
        ..release(300000)
        ..press(300000 + 1400000)
        ..release(300000 + 1400000 + 100000)
        ..advanceTo(5000000);
      expect(at.items, equals([_l('T'), _space, _l('E')]));
    });

    test('REQ-LIVE-7 no Word_Space before the first letter, however long '
        'the silence before it', () {
      final d = _decoder()
        ..advanceTo(0)
        ..advanceTo(10000000)
        ..press(10000000)
        ..release(10100000)
        ..advanceTo(20000000);
      expect(d.items, equals([_l('E')]));
    });

    test('REQ-LIVE-8 items are only appended to, never changed, and cannot '
        'be modified by the caller', () {
      final events = idealTiming('HI THERE', _cal, 2.0, 0);
      final d = _decoder();
      var previous = <DecodedItem>[];
      void check() {
        final now = List<DecodedItem>.of(d.items);
        expect(now.length, greaterThanOrEqualTo(previous.length));
        expect(now.sublist(0, previous.length), equals(previous));
        previous = now;
      }

      for (final (isPress, t) in events) {
        if (isPress) {
          d.press(t);
        } else {
          d.release(t);
        }
        check();
        d.advanceTo(t);
        check();
      }
      d.advanceTo(events.last.$2 + 475000);
      check();
      expect(
        d.items,
        equals([
          _l('H'),
          _l('I'),
          _space,
          _l('T'),
          _l('H'),
          _l('E'),
          _l('R'),
          _l('E'),
        ]),
      );
      expect(() => d.items.add(_space), throwsUnsupportedError);
      expect(() => d.items[0] = _l('X'), throwsUnsupportedError);
    });

    group('REQ-LIVE-9', () {
      test('REQ-LIVE-9 a press while pressed raises two presses in a row '
          'and changes nothing', () {
        final d = _midLetterDecoder()..press(1100000);
        final before = _snapshot(d);
        expect(
          () => d.press(1200000),
          _timingError(TimingInputErrorKind.twoPressesInARow, 5),
        );
        _expectState(d, before);
      });

      test('REQ-LIVE-9 a release before any press raises starts with a '
          'release and changes nothing', () {
        final d = _decoder();
        final before = _snapshot(d);
        expect(
          () => d.release(0),
          _timingError(TimingInputErrorKind.startsWithRelease, 0),
        );
        _expectState(d, before);
      });

      test('REQ-LIVE-9 a release while not pressed raises two releases in a '
          'row and changes nothing', () {
        final d = _midLetterDecoder();
        final before = _snapshot(d);
        expect(
          () => d.release(1100000),
          _timingError(TimingInputErrorKind.twoReleasesInARow, 4),
        );
        _expectState(d, before);
      });

      test('REQ-LIVE-9 a timestamp earlier than the latest raises decreasing '
          'timestamp for every call and changes nothing', () {
        final d = _midLetterDecoder();
        final before = _snapshot(d);
        expect(
          () => d.press(1029999),
          _timingError(TimingInputErrorKind.decreasingTimestamp, 4),
        );
        _expectState(d, before);
        expect(
          () => d.advanceTo(1029999),
          _timingError(TimingInputErrorKind.decreasingTimestamp, null),
        );
        _expectState(d, before);

        final held = _midLetterDecoder()..press(1100000);
        final heldBefore = _snapshot(held);
        expect(
          () => held.release(1099999),
          _timingError(TimingInputErrorKind.decreasingTimestamp, 5),
        );
        _expectState(held, heldBefore);
      });

      test('REQ-LIVE-9 REQ-EVENT-5 a timestamp outside the range raises '
          'timestamp out of range for every call and changes nothing', () {
        const above = SwitchEvent.maxTimestamp + 1;
        const below = SwitchEvent.minTimestamp - 1;

        final fresh = _decoder();
        final freshBefore = _snapshot(fresh);
        expect(
          () => fresh.press(below),
          _timingError(TimingInputErrorKind.timestampOutOfRange, 0),
        );
        expect(
          () => fresh.advanceTo(below),
          _timingError(TimingInputErrorKind.timestampOutOfRange, null),
        );
        _expectState(fresh, freshBefore);

        final d = _midLetterDecoder();
        final before = _snapshot(d);
        expect(
          () => d.press(above),
          _timingError(TimingInputErrorKind.timestampOutOfRange, 4),
        );
        expect(
          () => d.advanceTo(above),
          _timingError(TimingInputErrorKind.timestampOutOfRange, null),
        );
        _expectState(d, before);

        final held = _midLetterDecoder()..press(1100000);
        final heldBefore = _snapshot(held);
        expect(
          () => held.release(above),
          _timingError(TimingInputErrorKind.timestampOutOfRange, 5),
        );
        _expectState(held, heldBefore);
      });

      test('REQ-LIVE-9 the range limits themselves are accepted', () {
        final d = _decoder()
          ..press(SwitchEvent.minTimestamp)
          ..release(SwitchEvent.minTimestamp + 100000)
          ..advanceTo(SwitchEvent.maxTimestamp);
        expect(d.items, equals([_l('E')]));
        expect(d.latestTimestamp, SwitchEvent.maxTimestamp);
      });
    });

    test('REQ-LIVE-10 advanceTo while pressed records the timestamp and '
        'changes nothing else', () {
      final d = _decoder()
        ..press(0)
        ..release(100000)
        ..advanceTo(130000)
        // Gap 200,000: inside the letter.
        ..press(300000)
        ..advanceTo(5000000);
      expect(d.partialSequence, '.');
      expect(d.items, isEmpty);
      expect(d.isPressed, isTrue);
      expect(d.latestTimestamp, 5000000);
      expect(
        () => d.release(4999999),
        _timingError(TimingInputErrorKind.decreasingTimestamp, 3),
      );
    });

    test('REQ-LIVE-14 a Press shorter than the Debounce_Time is discarded '
        'with no Symbol', () {
      final d = _decoder()
        ..press(0)
        ..release(20000)
        ..advanceTo(50000);
      expect(d.partialSequence, isEmpty);
      expect(d.items, isEmpty);
      d.advanceTo(5000000);
      expect(d.items, isEmpty);
    });

    test('REQ-LIVE-14 later Gaps are measured from the last appended Press, '
        'not from a discarded one', () {
      // From the discarded Press's release (410,000) the Gap would be
      // 180,000 (inside the letter, giving I). From the dit's release
      // (100,000) it is 490,000, between letters.
      final d = _decoder()
        ..press(0)
        ..release(100000)
        ..advanceTo(130000)
        ..press(400000)
        ..release(410000)
        ..advanceTo(440000);
      expect(d.partialSequence, '.');
      expect(d.items, isEmpty);
      d
        ..press(590000)
        ..release(690000)
        ..advanceTo(2000000);
      expect(d.items, equals([_l('E'), _l('E')]));
    });
  });
}
