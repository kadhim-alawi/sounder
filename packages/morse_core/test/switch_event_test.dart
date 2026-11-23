import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

import 'support/timing_oracles.dart';

// The reference Calibration of REQ-BATCH-5.
const _cal = (
  ditLength: 100000,
  dahLength: 300000,
  symbolGap: 250000,
  letterGap: 700000,
);

Calibration _calibration() => Calibration(
  ditLength: _cal.ditLength,
  dahLength: _cal.dahLength,
  symbolGap: _cal.symbolGap,
  letterGap: _cal.letterGap,
);

BatchDecoder _batch() => BatchDecoder(_calibration(), TimingConfig.defaults);

LiveDecoder _live() => LiveDecoder(_calibration(), TimingConfig.defaults);

const int _max = SwitchEvent.maxTimestamp; // 2^52
const int _min = SwitchEvent.minTimestamp; // -2^52

SwitchEvent _p(int t) => SwitchEvent.press(t);
SwitchEvent _r(int t) => SwitchEvent.release(t);

List<SwitchEvent> _events(List<EventRecord> records) => [
  for (final (isPress, t) in records) isPress ? _p(t) : _r(t),
];

/// The Ideal_Timing of `PARIS` for the reference Calibration, shifted so its
/// first press is at [start].
List<SwitchEvent> _paris(int start) =>
    _events(idealTiming('PARIS', _cal, 2.0, start));

/// Total span of the `PARIS` Ideal_Timing, first press to last release.
final int _parisSpan = _paris(0).last.timestamp;

/// Expects [decode] to throw one [TimingInputException] of [kind] at
/// [index], and returns it.
TimingInputException _throws(
  void Function() decode,
  TimingInputErrorKind kind,
  int? index,
) {
  try {
    decode();
  } on TimingInputException catch (e) {
    expect(e.kind, kind);
    expect(e.index, index);
    return e;
  }
  fail('expected a TimingInputException of kind ${kind.name}');
}

void _expectBatchError(
  List<SwitchEvent> events,
  TimingInputErrorKind kind,
  int index,
) => _throws(() => _batch().decode(events), kind, index);

/// A snapshot of the caller-visible fields of a list of events.
List<(SwitchEventKind, int)> _snapshot(List<SwitchEvent> events) => [
  for (final e in events) (e.kind, e.timestamp),
];

void main() {
  group('REQ-EVENT-3 BatchDecoder rules', () {
    test('REQ-EVENT-3 timestamp out of range is reported at its index', () {
      _expectBatchError(
        [_p(1000000), _r(1100000), _p(_max + 1), _r(_max + 2)],
        TimingInputErrorKind.timestampOutOfRange,
        2,
      );
    });

    test('REQ-EVENT-3 a sequence that starts with a release is index 0', () {
      _expectBatchError(
        [_r(1000000), _p(1100000), _r(1200000)],
        TimingInputErrorKind.startsWithRelease,
        0,
      );
    });

    test('REQ-EVENT-3 two presses in a row are reported at the second', () {
      _expectBatchError(
        [_p(1000000), _r(1100000), _p(1400000), _p(1500000), _r(1600000)],
        TimingInputErrorKind.twoPressesInARow,
        3,
      );
    });

    test('REQ-EVENT-3 two releases in a row are reported at the second', () {
      _expectBatchError(
        [_p(1000000), _r(1100000), _r(1200000)],
        TimingInputErrorKind.twoReleasesInARow,
        2,
      );
    });

    test('REQ-EVENT-3 a decreasing timestamp is reported at the lower '
        'event', () {
      _expectBatchError(
        [_p(1000000), _r(1100000), _p(1050000), _r(1300000)],
        TimingInputErrorKind.decreasingTimestamp,
        2,
      );
    });

    test('REQ-EVENT-3 a sequence that ends with a press is reported at the '
        'last index', () {
      _expectBatchError(
        [_p(1000000), _r(1100000), _p(1400000)],
        TimingInputErrorKind.endsWithPress,
        2,
      );
      _expectBatchError([_p(1000000)], TimingInputErrorKind.endsWithPress, 0);
    });

    test('REQ-EVENT-3 REQ-EVENT-5 at one index, out of range wins over two '
        'presses in a row', () {
      _expectBatchError(
        [_p(1000000), _p(_max + 1), _r(_max + 2)],
        TimingInputErrorKind.timestampOutOfRange,
        1,
      );
    });

    test('REQ-EVENT-3 REQ-EVENT-5 at index 0, out of range wins over starts '
        'with release', () {
      _expectBatchError(
        [_r(_min - 1), _p(1000000), _r(1100000)],
        TimingInputErrorKind.timestampOutOfRange,
        0,
      );
    });

    test('REQ-EVENT-3 at one index, two presses in a row wins over a '
        'decreasing timestamp', () {
      _expectBatchError(
        [_p(1000000), _p(900000), _r(1100000)],
        TimingInputErrorKind.twoPressesInARow,
        1,
      );
    });

    test('REQ-EVENT-3 at one index, two releases in a row wins over a '
        'decreasing timestamp', () {
      _expectBatchError(
        [_p(1000000), _r(1100000), _r(1050000)],
        TimingInputErrorKind.twoReleasesInARow,
        2,
      );
    });

    test('REQ-EVENT-3 the lowest index wins over a higher-precedence kind '
        'later', () {
      _expectBatchError(
        [_p(1000000), _r(900000), _p(_max + 1), _p(1500000)],
        TimingInputErrorKind.decreasingTimestamp,
        1,
      );
    });

    test('REQ-EVENT-3 ends with press is not reported when an earlier rule '
        'breaks', () {
      _expectBatchError(
        [_p(1000000), _r(1100000), _p(1050000)],
        TimingInputErrorKind.decreasingTimestamp,
        2,
      );
    });

    test('REQ-EVENT-3 raw events are checked before debounce', () {
      // The second Press would be dropped as bounce (10,000 < 30,000), but
      // its release is earlier than its press, so the raw check fires first
      // with the event rule, not the Debouncer's Press rule.
      _expectBatchError(
        [_p(1000000), _r(1100000), _p(1500000), _r(1490000)],
        TimingInputErrorKind.decreasingTimestamp,
        3,
      );
      // A 5,000 bounce that debounce would merge is still two presses in a
      // row when its release is missing.
      _expectBatchError(
        [_p(1000000), _p(1005000), _r(1100000)],
        TimingInputErrorKind.twoPressesInARow,
        1,
      );
    });
  });

  group('REQ-EVENT-4 messages', () {
    test('REQ-EVENT-4 every error kind has its own phrase', () {
      final phrases = TimingInputErrorKind.values.map((k) => k.phrase);
      expect(phrases.every((p) => p.isNotEmpty), isTrue);
      expect(phrases.toSet().length, TimingInputErrorKind.values.length);
    });

    test('REQ-EVENT-4 a message has the phrase and the event index and no '
        'timestamp', () {
      final cases = <(List<SwitchEvent>, TimingInputErrorKind, int)>[
        (
          [_p(1000000), _r(1100000), _p(1400000), _p(1500000)],
          TimingInputErrorKind.twoPressesInARow,
          3,
        ),
        ([_r(2000000), _p(2100000)], TimingInputErrorKind.startsWithRelease, 0),
        (
          [_p(1000000), _r(1100000), _p(1050000), _r(1300000)],
          TimingInputErrorKind.decreasingTimestamp,
          2,
        ),
        (
          [_p(1000000), _r(1100000), _p(_max + 1)],
          TimingInputErrorKind.timestampOutOfRange,
          2,
        ),
      ];
      for (final (events, kind, index) in cases) {
        final e = _throws(() => _batch().decode(events), kind, index);
        expect(e.message, contains(kind.phrase));
        expect(e.message, contains(RegExp('(^|\\D)$index(\\D|\$)')));
        expect(e.toString(), e.message);
        for (final event in events) {
          expect(
            e.message,
            isNot(contains('${event.timestamp}')),
            reason: 'message leaks a timestamp',
          );
        }
      }
    });

    test('REQ-EVENT-4 the exact message for two presses in a row', () {
      final e = _throws(
        () => _batch().decode([
          _p(1000000),
          _r(1100000),
          _p(1400000),
          _p(1500000),
        ]),
        TimingInputErrorKind.twoPressesInARow,
        3,
      );
      expect(e.message, 'Event 3: two presses in a row.');
    });
  });

  group('REQ-EVENT-5 timestamp range', () {
    test('REQ-EVENT-5 the range constants are plus and minus 2^52', () {
      expect(SwitchEvent.maxTimestamp, 4503599627370496);
      expect(SwitchEvent.minTimestamp, -4503599627370496);
    });

    test('REQ-EVENT-5 BatchDecoder rejects 2^52 + 1 and -(2^52 + 1)', () {
      _expectBatchError(
        [_p(_max - 100000), _r(_max + 1)],
        TimingInputErrorKind.timestampOutOfRange,
        1,
      );
      _expectBatchError(
        [_p(_min - 1), _r(_min + 100000)],
        TimingInputErrorKind.timestampOutOfRange,
        0,
      );
    });

    test('REQ-EVENT-5 BatchDecoder accepts exactly 2^52 and -2^52', () {
      expect(
        _batch().decode([_p(_min), _r(_min + 100000)]),
        equals([const DecodedItem.letter('E')]),
      );
      expect(
        _batch().decode([_p(_max - 300000), _r(_max)]),
        equals([const DecodedItem.letter('T')]),
      );
    });

    test('REQ-EVENT-5 REQ-CAL-11 Calibrator returns invalidEvents with the '
        'index for 2^52 + 1 and -(2^52 + 1)', () {
      final high = _paris(_max - _parisSpan + 1); // last release 2^52 + 1
      final highResult = Calibrator().calibrate(high);
      expect(highResult.isAccepted, isFalse);
      expect(highResult.rejection!.reason, RejectionReason.invalidEvents);
      final lastIndex = high.length - 1;
      expect(highResult.rejection!.message, contains('$lastIndex'));
      expect(
        highResult.rejection!.message,
        contains(TimingInputErrorKind.timestampOutOfRange.phrase),
      );

      final low = _paris(_min - 1);
      final lowResult = Calibrator().calibrate(low);
      expect(lowResult.rejection!.reason, RejectionReason.invalidEvents);
      expect(
        lowResult.rejection!.message,
        'Event 0 is invalid: '
        '${TimingInputErrorKind.timestampOutOfRange.phrase}.',
      );
    });

    test('REQ-EVENT-5 Calibrator accepts sequences reaching exactly 2^52 '
        'and -2^52', () {
      for (final start in [_min, _max - _parisSpan]) {
        final result = Calibrator().calibrate(_paris(start));
        expect(result.isAccepted, isTrue, reason: 'start $start');
        expect(result.calibration, equals(_calibration()));
      }
    });

    test('REQ-EVENT-5 REQ-LIVE-9 LiveDecoder rejects 2^52 + 1 and '
        '-(2^52 + 1) and keeps its state', () {
      final live = _live()
        ..press(0)
        ..release(100000)
        ..advanceTo(130000);
      expect(live.partialSequence, '.');

      void expectUnchanged(void Function() call, int? index) {
        final items = List<DecodedItem>.of(live.items);
        final partial = live.partialSequence;
        final pressed = live.isPressed;
        final latest = live.latestTimestamp;
        _throws(call, TimingInputErrorKind.timestampOutOfRange, index);
        expect(live.items, equals(items));
        expect(live.partialSequence, partial);
        expect(live.isPressed, pressed);
        expect(live.latestTimestamp, latest);
      }

      expectUnchanged(() => live.press(_max + 1), 2);
      expectUnchanged(() => live.advanceTo(_max + 1), null);
      expectUnchanged(() => live.press(_min - 1), 2);
      live.press(200000);
      expectUnchanged(() => live.release(_max + 1), 3);
      expectUnchanged(() => live.advanceTo(_min - 1), null);
    });

    test('REQ-EVENT-5 LiveDecoder accepts exactly -2^52 and 2^52', () {
      final low = _live()
        ..press(_min)
        ..release(_min + 100000)
        ..advanceTo(_min + 800000);
      expect(low.items, equals([const DecodedItem.letter('E')]));

      final high = _live()
        ..press(_max - 900000)
        ..release(_max - 800000)
        ..advanceTo(_max);
      expect(high.items, equals([const DecodedItem.letter('E')]));
      expect(high.latestTimestamp, _max);
    });
  });

  group('REQ-EVENT-6 input unchanged', () {
    test('REQ-EVENT-6 BatchDecoder leaves the list unchanged on success', () {
      final events = _events(idealTiming('SOS', _cal, 2.0, 1000000));
      final before = _snapshot(events);
      final copy = List<SwitchEvent>.of(events);
      expect(_batch().decode(events), hasLength(3));
      expect(_snapshot(events), equals(before));
      expect(events, equals(copy));
    });

    test('REQ-EVENT-6 BatchDecoder leaves the list unchanged on error', () {
      final events = [_p(1000000), _r(1100000), _p(1050000), _r(1300000)];
      final before = _snapshot(events);
      _expectBatchError(events, TimingInputErrorKind.decreasingTimestamp, 2);
      expect(_snapshot(events), equals(before));
    });

    test('REQ-EVENT-6 BatchDecoder leaves the list unchanged when debounce '
        'drops and merges Presses', () {
      final events = [
        _p(1000000),
        _r(1002000),
        _p(1004000),
        _r(1100000),
        _p(1500000),
        _r(1510000),
      ];
      final before = _snapshot(events);
      expect(_batch().decode(events), equals([const DecodedItem.letter('E')]));
      expect(_snapshot(events), equals(before));
    });

    test('REQ-EVENT-6 Calibrator leaves the list unchanged on acceptance', () {
      final events = _paris(1000000);
      final before = _snapshot(events);
      expect(Calibrator().calibrate(events).isAccepted, isTrue);
      expect(_snapshot(events), equals(before));
    });

    test('REQ-EVENT-6 Calibrator leaves the list unchanged on rejection', () {
      final invalid = [..._paris(1000000), _p(_max)];
      final invalidBefore = _snapshot(invalid);
      expect(
        Calibrator().calibrate(invalid).rejection!.reason,
        RejectionReason.invalidEvents,
      );
      expect(_snapshot(invalid), equals(invalidBefore));

      final short = _paris(1000000).sublist(0, 26);
      final shortBefore = _snapshot(short);
      expect(
        Calibrator().calibrate(short).rejection!.reason,
        RejectionReason.wrongPressCount,
      );
      expect(_snapshot(short), equals(shortBefore));

      final unsuitable = _paris(1000000);
      final unsuitableBefore = _snapshot(unsuitable);
      expect(
        Calibrator().calibrate(unsuitable, word: '').rejection!.reason,
        RejectionReason.unsuitableWord,
      );
      expect(_snapshot(unsuitable), equals(unsuitableBefore));
    });
  });
}
