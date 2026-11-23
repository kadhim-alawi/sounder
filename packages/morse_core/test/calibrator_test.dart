import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

const _table = CodeTable();

// Reference keying durations from REQ-CAL-16, in Microseconds.
const _dit = 100000;
const _dah = 300000;
const _symbolGap = 250000;
const _letterGap = 700000;

/// The expected Symbols of [word], concatenated (REQ-CAL-2).
String _symbols(String word) =>
    word.split('').map((c) => _table.codeFor(c)!).join();

/// For each Gap of [word], true when it lies between letters (REQ-CAL-2).
List<bool> _gapIsBetween(String word) {
  final between = <bool>[];
  var first = true;
  for (final c in word.split('')) {
    final code = _table.codeFor(c)!;
    for (var k = 0; k < code.length; k++) {
      if (!first) between.add(k == 0);
      first = false;
    }
  }
  return between;
}

/// Press durations for an ideal keying of [word].
List<int> _pressDurations(String word, {int dit = _dit, int dah = _dah}) =>
    _symbols(word).split('').map((s) => s == '.' ? dit : dah).toList();

/// Gap durations for an ideal keying of [word].
List<int> _gapDurations(
  String word, {
  int symbolGap = _symbolGap,
  int letterGap = _letterGap,
}) => _gapIsBetween(word).map((b) => b ? letterGap : symbolGap).toList();

/// Builds an Event_Sequence from Press and Gap durations, starting at [start].
List<SwitchEvent> _events(List<int> presses, List<int> gaps, {int start = 0}) {
  final events = <SwitchEvent>[];
  var t = start;
  for (var i = 0; i < presses.length; i++) {
    if (i > 0) t += gaps[i - 1];
    events.add(SwitchEvent.press(t));
    t += presses[i];
    events.add(SwitchEvent.release(t));
  }
  return events;
}

/// The ideal keying of [word] with the reference durations.
List<SwitchEvent> _ideal(String word, {int start = 0}) =>
    _events(_pressDurations(word), _gapDurations(word), start: start);

final _reference = Calibration(
  ditLength: _dit,
  dahLength: _dah,
  symbolGap: _symbolGap,
  letterGap: _letterGap,
);

Matcher _rejectedWith(RejectionReason reason) => isA<CalibrationResult>()
    .having((r) => r.isAccepted, 'isAccepted', isFalse)
    .having((r) => r.calibration, 'calibration', isNull)
    .having((r) => r.rejection?.reason, 'reason', reason);

Matcher _acceptedWith(Calibration calibration) => isA<CalibrationResult>()
    .having((r) => r.isAccepted, 'isAccepted', isTrue)
    .having((r) => r.rejection, 'rejection', isNull)
    .having((r) => r.calibration, 'calibration', calibration);

String _message(CalibrationResult result) => result.rejection!.message;

void main() {
  final calibrator = Calibrator();

  group('Calibrator', () {
    test('REQ-CAL-1 the default Calibration_Word is PARIS', () {
      expect(Calibrator.defaultWord, 'PARIS');
      final events = _ideal('PARIS');
      expect(calibrator.calibrate(events), _acceptedWith(_reference));
      // A keying of another word is judged against PARIS when no word is
      // given: SOS has 9 Presses, PARIS expects 14.
      expect(
        calibrator.calibrate(_ideal('SOS')),
        _rejectedWith(RejectionReason.wrongPressCount),
      );
    });

    test('REQ-CAL-16 PARIS keyed with the reference durations from 0 gives '
        'the reference Calibration', () {
      final result = calibrator.calibrate(_ideal('PARIS'), word: 'PARIS');
      expect(result.isAccepted, isTrue);
      final c = result.calibration!;
      expect(c.ditLength, 100000);
      expect(c.dahLength, 300000);
      expect(c.symbolGap, 250000);
      expect(c.letterGap, 700000);
    });

    group('REQ-CAL-3 unsuitable words', () {
      // Each word breaks exactly one rule, so its message names that rule.
      const singleRule = {
        'empty': '',
        'more than 16 characters': 'PARISPARISPARISPA',
        'contains a space': 'PA RIS',
        'character not in the Code_Table': 'PA#RIS',
        'fewer than two characters': 'A',
        'no dit': 'TM',
        'no dah': 'EI',
        'no character with two or more Symbols': 'ET',
      };

      String messageFor(String word) =>
          _message(calibrator.calibrate(_ideal('PARIS'), word: word));

      for (final entry in singleRule.entries) {
        test('REQ-CAL-3 ${entry.key} gives unsuitableWord', () {
          expect(
            calibrator.calibrate(_ideal('PARIS'), word: entry.value),
            _rejectedWith(RejectionReason.unsuitableWord),
          );
        });
      }

      test('REQ-CAL-3 a space and an unknown character share one rule', () {
        expect(messageFor('PA RIS'), messageFor('PA#RIS'));
      });

      test('REQ-CAL-3 each rule has its own message', () {
        final messages = {
          for (final w in singleRule.values)
            if (w != 'PA#RIS') messageFor(w),
        };
        expect(messages.length, singleRule.length - 1);
      });

      test('REQ-CAL-3 the message names the first failed rule in order', () {
        // 17 characters with an unknown character: length rule first.
        expect(
          messageFor('PARISPARISPARIS#A'),
          messageFor('PARISPARISPARISPA'),
        );
        // A space in a two-character word with no dah: space rule first.
        expect(messageFor('E '), messageFor('PA RIS'));
        // One character, no dah, no long code: fewer-than-two rule first.
        expect(messageFor('E'), messageFor('A'));
        // No dit and no long code: no-dit rule first.
        expect(messageFor('TT'), messageFor('TM'));
        // No dah and no long code: no-dah rule first.
        expect(messageFor('EE'), messageFor('EI'));
      });

      test('REQ-CAL-3 REQ-CAL-12 an invalid Event_Sequence with an empty word '
          'gives unsuitableWord', () {
        const invalid = [SwitchEvent.release(0), SwitchEvent.release(5)];
        expect(
          calibrator.calibrate(invalid, word: ''),
          _rejectedWith(RejectionReason.unsuitableWord),
        );
        expect(
          calibrator.calibrate(const [], word: 'S#S'),
          _rejectedWith(RejectionReason.unsuitableWord),
        );
      });
    });

    test('REQ-CAL-21 the listed words give unsuitableWord', () {
      for (final word in ['E', 'EEE', 'TM', 'ET', 'SO S', 'S#S']) {
        expect(
          calibrator.calibrate(_ideal('PARIS'), word: word),
          _rejectedWith(RejectionReason.unsuitableWord),
          reason: 'word "$word"',
        );
      }
    });

    group('REQ-CAL-4 the PARIS plan', () {
      test('REQ-CAL-4 14 Presses are accepted; 13 and 15 are not', () {
        final presses = _pressDurations('PARIS');
        final gaps = _gapDurations('PARIS');
        expect(presses.length, 14);
        expect(calibrator.calibrate(_events(presses, gaps)).isAccepted, isTrue);

        expect(
          calibrator.calibrate(
            _events(presses.sublist(0, 13), gaps.sublist(0, 12)),
          ),
          _rejectedWith(RejectionReason.wrongPressCount),
        );
        expect(
          calibrator.calibrate(
            _events([...presses, _dit], [...gaps, _symbolGap]),
          ),
          _rejectedWith(RejectionReason.wrongPressCount),
        );
      });

      test('REQ-CAL-4 dahs are expected at Presses 1, 2, 5 and 7', () {
        const dahIndexes = {1, 2, 5, 7};
        final presses = [
          for (var i = 0; i < 14; i++) dahIndexes.contains(i) ? _dah : _dit,
        ];
        final gaps = _gapDurations('PARIS');
        expect(
          calibrator.calibrate(_events(presses, gaps)),
          _acceptedWith(_reference),
        );
        // Moving one dah to Press 3 makes an expected dit long.
        final moved = List<int>.of(presses)
          ..[2] = _dit
          ..[3] = _dah;
        expect(
          calibrator.calibrate(_events(moved, gaps)),
          _rejectedWith(RejectionReason.pressesOverlap),
        );
      });

      test('REQ-CAL-4 Gaps 3, 5, 8 and 10 are between letters', () {
        const betweenIndexes = {3, 5, 8, 10};
        final gaps = [
          for (var j = 0; j < 13; j++)
            betweenIndexes.contains(j) ? _letterGap : _symbolGap,
        ];
        final presses = _pressDurations('PARIS');
        expect(
          calibrator.calibrate(_events(presses, gaps)),
          _acceptedWith(_reference),
        );
        // Moving one letter pause from Gap 3 to Gap 2 breaks the plan.
        final moved = List<int>.of(gaps)
          ..[2] = _letterGap
          ..[3] = _symbolGap;
        expect(
          calibrator.calibrate(_events(presses, moved)),
          _rejectedWith(RejectionReason.gapsOverlap),
        );
      });
    });

    group('REQ-CAL-5 debounce before measuring', () {
      // PARIS with a 10,000 Press inside Gap 0 (dit ends at 100,000, next
      // Press starts at 350,000). Its Gaps of 100,000 and 140,000 do not merge.
      List<SwitchEvent> withBounce() {
        final events = _ideal('PARIS');
        return [
          ...events.sublist(0, 2),
          const SwitchEvent.press(200000),
          const SwitchEvent.release(210000),
          ...events.sublist(2),
        ];
      }

      test('REQ-CAL-5 the default Timing_Config removes one bounce Press', () {
        expect(calibrator.calibrate(withBounce()), _acceptedWith(_reference));
      });

      test('REQ-CAL-5 the given Timing_Config sets the Debounce_Time', () {
        final short = Calibrator(TimingConfig(debounceTime: 5000));
        expect(short.config.debounceTime, 5000);
        expect(
          short.calibrate(withBounce()),
          _rejectedWith(RejectionReason.wrongPressCount),
        );
        expect(Calibrator().config.debounceTime, 30000);
      });
    });

    group('REQ-CAL-8 wrong Press count', () {
      test('REQ-CAL-8 13 Presses for PARIS: the message has 14 and 13', () {
        final presses = _pressDurations('PARIS').sublist(0, 13);
        final gaps = _gapDurations('PARIS').sublist(0, 12);
        final result = calibrator.calibrate(_events(presses, gaps));
        expect(result, _rejectedWith(RejectionReason.wrongPressCount));
        expect(_message(result), contains('14'));
        expect(_message(result), contains('13'));
      });

      test('REQ-CAL-8 debounce leaving zero Presses is a wrong count', () {
        const events = [SwitchEvent.press(0), SwitchEvent.release(10000)];
        final result = calibrator.calibrate(events);
        expect(result, _rejectedWith(RejectionReason.wrongPressCount));
        expect(_message(result), contains('14'));
        expect(_message(result), contains('0'));
      });
    });

    test(
      'REQ-CAL-9 a dit as long as the shortest dah gives pressesOverlap',
      () {
        final presses = _pressDurations('PARIS')..[0] = _dah;
        final result = calibrator.calibrate(
          _events(presses, _gapDurations('PARIS')),
        );
        expect(result, _rejectedWith(RejectionReason.pressesOverlap));
        expect(
          _message(result).toLowerCase(),
          contains('short and long presses could not be told apart'),
        );
      },
    );

    test('REQ-CAL-10 an inside-letter Gap as long as the shortest letter Gap '
        'gives gapsOverlap', () {
      final gaps = _gapDurations('PARIS')..[0] = _letterGap;
      final result = calibrator.calibrate(
        _events(_pressDurations('PARIS'), gaps),
      );
      expect(result, _rejectedWith(RejectionReason.gapsOverlap));
      expect(
        _message(result).toLowerCase(),
        contains(
          'pauses inside letters and pauses between letters could not be '
          'told apart',
        ),
      );
    });

    group('REQ-CAL-11 invalid Event_Sequences', () {
      test('REQ-CAL-11 two presses in a row at event 3 gives invalidEvents '
          'with the index and the rule', () {
        final events = List<SwitchEvent>.of(_ideal('PARIS'))
          ..[3] = SwitchEvent.press(_ideal('PARIS')[3].timestamp);
        // events[2] is a press, so the break is at index 3.
        final result = calibrator.calibrate(events);
        expect(result, _rejectedWith(RejectionReason.invalidEvents));
        expect(_message(result), contains('Event 3 '));
        expect(
          _message(result),
          contains(TimingInputErrorKind.twoPressesInARow.phrase),
        );
      });

      test('REQ-CAL-11 a sequence starting with a release reports event 0', () {
        const events = [SwitchEvent.release(0), SwitchEvent.press(10)];
        final result = calibrator.calibrate(events);
        expect(result, _rejectedWith(RejectionReason.invalidEvents));
        expect(_message(result), contains('0'));
        expect(
          _message(result),
          contains(TimingInputErrorKind.startsWithRelease.phrase),
        );
      });

      test('REQ-CAL-11 REQ-EVENT-5 a timestamp out of range gives '
          'invalidEvents instead of an error', () {
        final events = [
          const SwitchEvent.press(0),
          const SwitchEvent.release(SwitchEvent.maxTimestamp + 1),
        ];
        final result = calibrator.calibrate(events);
        expect(result, _rejectedWith(RejectionReason.invalidEvents));
        expect(_message(result), contains('1'));
        expect(
          _message(result),
          contains(TimingInputErrorKind.timestampOutOfRange.phrase),
        );
      });

      test('REQ-CAL-11 a sequence ending with a press gives invalidEvents', () {
        final events = [..._ideal('PARIS'), const SwitchEvent.press(9000000)];
        final result = calibrator.calibrate(events);
        expect(result, _rejectedWith(RejectionReason.invalidEvents));
        expect(_message(result), contains('28'));
      });
    });

    group('REQ-CAL-12 rejection order', () {
      final zero = Calibrator(TimingConfig(debounceTime: 0));

      test('REQ-CAL-12 invalidEvents comes before wrongPressCount', () {
        const events = [SwitchEvent.press(0), SwitchEvent.press(10)];
        expect(
          calibrator.calibrate(events),
          _rejectedWith(RejectionReason.invalidEvents),
        );
      });

      test('REQ-CAL-12 wrongPressCount comes before pressesOverlap', () {
        final presses = _pressDurations('PARIS').sublist(0, 13)..[0] = _dah;
        final gaps = _gapDurations('PARIS').sublist(0, 12);
        expect(
          calibrator.calibrate(_events(presses, gaps)),
          _rejectedWith(RejectionReason.wrongPressCount),
        );
      });

      test('REQ-CAL-12 pressesOverlap comes before gapsOverlap', () {
        final presses = _pressDurations('PARIS')..[0] = _dah;
        final gaps = _gapDurations('PARIS')..[0] = _letterGap;
        expect(
          calibrator.calibrate(_events(presses, gaps)),
          _rejectedWith(RejectionReason.pressesOverlap),
        );
      });

      test('REQ-CAL-12 gapsOverlap comes before zeroDuration', () {
        final presses = _pressDurations('PARIS', dit: 0);
        final gaps = _gapDurations('PARIS')..[0] = _letterGap;
        expect(
          zero.calibrate(_events(presses, gaps)),
          _rejectedWith(RejectionReason.gapsOverlap),
        );
      });

      test('REQ-CAL-12 zeroDuration comes before durationTooLong', () {
        // AT: one dit, two dahs, one inside Gap, one letter Gap.
        final events = _events([0, _dah, _dah], [_symbolGap, (1 << 40) + 1]);
        expect(
          zero.calibrate(events, word: 'AT'),
          _rejectedWith(RejectionReason.zeroDuration),
        );
      });
    });

    group('REQ-CAL-13 rejection messages', () {
      // Every timestamp is at least 1,000,000 and differs from every index.
      const start = 5000000;
      final zero = Calibrator(TimingConfig(debounceTime: 0));
      final cases = <String, CalibrationResult>{
        'unsuitableWord': calibrator.calibrate(
          _ideal('PARIS', start: start),
          word: 'S#S',
        ),
        'invalidEvents': calibrator.calibrate([
          const SwitchEvent.press(start),
          const SwitchEvent.press(start + 1234567),
        ]),
        'wrongPressCount': calibrator.calibrate(_ideal('SOS', start: start)),
        'pressesOverlap': calibrator.calibrate(
          _events(
            _pressDurations('PARIS')..[0] = _dah,
            _gapDurations('PARIS'),
            start: start,
          ),
        ),
        'gapsOverlap': calibrator.calibrate(
          _events(
            _pressDurations('PARIS'),
            _gapDurations('PARIS')..[0] = _letterGap,
            start: start,
          ),
        ),
        'zeroDuration': zero.calibrate(
          _events(
            _pressDurations('PARIS', dit: 0),
            _gapDurations('PARIS'),
            start: start,
          ),
        ),
        'durationTooLong': calibrator.calibrate(
          _events(
            [_dit, _dah, _dah],
            [_symbolGap, (1 << 40) + 1],
            start: start,
          ),
          word: 'AT',
        ),
      };

      test('REQ-CAL-13 every reason produces a non-empty English message', () {
        expect(cases.length, RejectionReason.values.length);
        for (final entry in cases.entries) {
          final rejection = entry.value.rejection;
          expect(rejection, isNotNull, reason: entry.key);
          expect(rejection!.reason.name, entry.key);
          expect(rejection.message.trim(), isNotEmpty);
          expect(rejection.toString(), rejection.message);
        }
      });

      test('REQ-CAL-13 messages hold no timestamp, duration or Symbol, and '
          'numbers only where allowed', () {
        // Numbers each message may contain.
        const allowed = {
          'invalidEvents': {'1'},
          'wrongPressCount': {'14', '9'},
        };
        for (final entry in cases.entries) {
          final message = entry.value.rejection!.message;
          final numbers = RegExp(r'\d+')
              .allMatches(message)
              .map((m) => m.group(0)!)
              .toSet();
          expect(
            numbers,
            equals(allowed[entry.key] ?? <String>{}),
            reason: '${entry.key}: $message',
          );
          expect(
            RegExp(r'[.\-]{2,}').hasMatch(message),
            isFalse,
            reason: '${entry.key}: $message',
          );
          expect(message.contains('-'), isFalse, reason: entry.key);
        }
      });
    });

    test('REQ-CAL-20 letter case of the word does not change the result', () {
      final events = _ideal('PARIS');
      final upper = calibrator.calibrate(events, word: 'PARIS');
      expect(upper, _acceptedWith(_reference));
      expect(
        calibrator.calibrate(events, word: 'paris'),
        _acceptedWith(_reference),
      );
      expect(
        calibrator.calibrate(events, word: 'PaRiS'),
        _acceptedWith(_reference),
      );

      final sos = _ideal('SOS');
      expect(
        calibrator.calibrate(sos, word: 'sos'),
        _acceptedWith(calibrator.calibrate(sos, word: 'SOS').calibration!),
      );
    });

    group('REQ-CAL-30 zero durations', () {
      final zero = Calibrator(TimingConfig(debounceTime: 0));

      test('REQ-CAL-30 a zero-length dit with Debounce_Time 0 gives '
          'zeroDuration', () {
        final events = _events([0, _dah, _dah], [_symbolGap, _letterGap]);
        final result = zero.calibrate(events, word: 'AT');
        expect(result, _rejectedWith(RejectionReason.zeroDuration));
        expect(
          _message(result).toLowerCase(),
          contains('too short to measure'),
        );
      });

      test('REQ-CAL-30 zero-length inside-letter Gaps give zeroDuration', () {
        final events = _events(
          _pressDurations('PARIS'),
          _gapDurations('PARIS', symbolGap: 0),
        );
        expect(
          zero.calibrate(events),
          _rejectedWith(RejectionReason.zeroDuration),
        );
      });
    });

    group('REQ-CAL-31 exactly one result, never an error', () {
      test('REQ-CAL-31 a median above 2^40 gives durationTooLong', () {
        final events = _events(
          [_dit, _dah, _dah],
          [_symbolGap, (1 << 40) + 1],
          start: SwitchEvent.minTimestamp,
        );
        final result = calibrator.calibrate(events, word: 'AT');
        expect(result, _rejectedWith(RejectionReason.durationTooLong));
        expect(_message(result).toLowerCase(), contains('too long to measure'));
      });

      test('REQ-CAL-31 a median of exactly 2^40 is accepted', () {
        final events = _events(
          [_dit, _dah, _dah],
          [_symbolGap, 1 << 40],
          start: SwitchEvent.minTimestamp,
        );
        expect(
          calibrator.calibrate(events, word: 'AT'),
          _acceptedWith(
            Calibration(
              ditLength: _dit,
              dahLength: _dah,
              symbolGap: _symbolGap,
              letterGap: 1 << 40,
            ),
          ),
        );
      });

      test(
        'REQ-CAL-31 varied inputs each return one result without throwing',
        () {
          final inputs = <(List<SwitchEvent>, String)>[
            (const [], 'PARIS'),
            (const [], ''),
            (const [SwitchEvent.release(0)], 'PARIS'),
            (const [SwitchEvent.press(0)], 'PARIS'),
            (_ideal('PARIS'), 'PARIS'),
            (_ideal('PARIS'), 'ß'),
            (_ideal('SOS'), 'SOS'),
            (_ideal('PARIS', start: SwitchEvent.minTimestamp), 'PARIS'),
          ];
          for (final (events, word) in inputs) {
            final result = calibrator.calibrate(events, word: word);
            expect(
              (result.calibration == null) != (result.rejection == null),
              isTrue,
            );
          }
        },
      );
    });
  });
}
