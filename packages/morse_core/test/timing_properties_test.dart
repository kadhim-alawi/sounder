/// Property-based tests for adaptive-timing, one `property(...)` per
/// correctness property in the design. Each uses a single `forAll` with
/// `maxExamples: 200`, the fixed seed `(100 + N) * 1000 + 3` for Property N,
/// and `onFalsify: report(seed)`. REQ-PBT-1, REQ-PBT-4.
library;

import 'package:kiri_check/kiri_check.dart';
import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

import 'support/arbitraries.dart' show report;
import 'support/itu_fixture.dart';
import 'support/timing_arbitraries.dart';
import 'support/timing_oracles.dart';

/// Engine Presses as plain records, for comparison with the oracles.
List<(int, int)> _records(List<Press> presses) => <(int, int)>[
  for (final p in presses) (p.pressedAt, p.releasedAt),
];

/// The error kind a Timing_Config input should raise, or null when it is
/// valid. Written from REQ-DEBOUNCE-3: the Debounce_Time is named whenever it
/// is invalid.
TimingInputErrorKind? _expectedConfigError(ConfigInput c) {
  if (c.debounceTime < 0) return TimingInputErrorKind.invalidDebounceTime;
  final f = c.wordGapFactor;
  final valid = !f.isNaN && f.isFinite && f > 1.0 && f <= maxWordGapFactor;
  return valid ? null : TimingInputErrorKind.invalidWordGapFactor;
}

bool _inCalibrationRange(int v) => v > 0 && v <= maxCalibrationValue;

/// The error kind a Calibration input should raise, or null when it is
/// valid. Written from REQ-CAL-14: the first invalid field in the order
/// Dit_Length, Dah_Length, Symbol_Gap, Letter_Gap.
TimingInputErrorKind? _expectedCalibrationError(CalibrationInput c) {
  if (!_inCalibrationRange(c.ditLength)) {
    return TimingInputErrorKind.invalidDitLength;
  }
  if (!_inCalibrationRange(c.dahLength) || c.dahLength <= c.ditLength) {
    return TimingInputErrorKind.invalidDahLength;
  }
  if (!_inCalibrationRange(c.symbolGap)) {
    return TimingInputErrorKind.invalidSymbolGap;
  }
  if (!_inCalibrationRange(c.letterGap) || c.letterGap <= c.symbolGap) {
    return TimingInputErrorKind.invalidLetterGap;
  }
  return null;
}

/// Runs [build] and returns the kind of the [TimingInputException] it
/// throws, or null when it returns normally. Any other throwable fails.
TimingInputErrorKind? _errorKindOf(void Function() build) {
  try {
    build();
    return null;
  } on TimingInputException catch (e) {
    return e.kind;
  }
}

/// Runs [call] and returns the kind and index of the [TimingInputException]
/// it throws, or null when it returns normally. REQ-LIVE-9.
(TimingInputErrorKind, int?)? _errorOf(void Function() call) {
  try {
    call();
    return null;
  } on TimingInputException catch (e) {
    return (e.kind, e.index);
  }
}

/// The REQ-CAL-3 word-length limit, the one number a fixed rejection
/// message may contain.
const int _maxCalibrationWordLength = 16;

/// Checks one engine message [text] (a message or a `toString()`) against
/// Property 18. It contains [phrase] when one is given; its digit runs are
/// exactly [allowedNumbers], in order; it contains no input timestamp from
/// [timestamps] and no `.`/`-` run of two or more. With [phrase] removed and
/// digit runs replaced by `#`, it equals the frame first seen for [key], so
/// the text depends only on the error kind or Rejection_Reason (and rule)
/// and on the allowed numbers, never on other input. REQ-EVENT-4,
/// REQ-CAL-13, REQ-ENGINE-5.
void _expectPrivate(
  String text, {
  required String key,
  required String? phrase,
  required List<int> allowedNumbers,
  required List<int> timestamps,
  required Map<String, String> frames,
  required String reason,
}) {
  final why = '$reason: "$text"';
  expect(text, isNotEmpty, reason: why);
  if (phrase != null) expect(text, contains(phrase), reason: why);
  final digits = RegExp(r'\d+');
  expect(
    <String>[for (final m in digits.allMatches(text)) m.group(0)!],
    equals(<String>[for (final n in allowedNumbers) '$n']),
    reason: why,
  );
  for (final t in timestamps) {
    expect(text.contains('${t.abs()}'), isFalse, reason: '$why leaks $t');
  }
  expect(RegExp(r'[.\-]{2,}').hasMatch(text), isFalse, reason: why);
  final frame = (phrase == null ? text : text.replaceAll(phrase, '<phrase>'))
      .replaceAll(digits, '#');
  expect(frame, equals(frames.putIfAbsent(key, () => frame)), reason: why);
}

/// Checks that [item]'s `toString()` is the same as for any other item of
/// its kind, so it reveals no character or Symbol (T12). REQ-ENGINE-5.
void _expectItemPrivate(DecodedItem item, String reason) {
  final blank = switch (item.kind) {
    DecodedItemKind.letter => const DecodedItem.letter('Q'),
    DecodedItemKind.unknownLetter => const DecodedItem.unknownLetter('......'),
    DecodedItemKind.wordSpace => const DecodedItem.wordSpace(),
  };
  final text = item.toString();
  expect(
    text,
    equals(blank.toString()),
    reason:
        '$reason: ${item.kind.name} "${item.character}" '
        '"${item.symbols}" gives "$text"',
  );
  expect(RegExp(r'[.\-]').hasMatch(text), isFalse, reason: reason);
}

void main() {
  // Feature: adaptive-timing, Property 1: Debouncer matches merge-then-drop and leaves no bounce
  property('REQ-DEBOUNCE-4 REQ-DEBOUNCE-5 REQ-DEBOUNCE-6 REQ-DEBOUNCE-7 '
      'REQ-DEBOUNCE-10 REQ-PBT-8 Debouncer matches merge-then-drop and '
      'leaves no bounce', () {
    var counted = 0, withShort = 0, withZeroD = 0;
    forAll(
      pressList(),
      (c) {
        counted++;
        if (hasShortDuration(c)) withShort++;
        final d = c.debounceTime;
        if (d == 0) withZeroD++;

        final input = <Press>[for (final (a, b) in c.presses) Press(a, b)];
        final before = List<Press>.of(input);
        final output = Debouncer(TimingConfig(debounceTime: d)).debounce(input);
        final out = _records(output);

        // REQ-DEBOUNCE-4, REQ-DEBOUNCE-5: equals the reference model.
        expect(out, equals(referenceDebounce(c.presses, d)));

        // REQ-DEBOUNCE-6: the caller's list is unchanged.
        expect(input, equals(before));

        // REQ-DEBOUNCE-7: no more Presses than the input; every Press and
        // Gap lasts at least d. REQ-DEBOUNCE-6: time ordered.
        expect(out.length, lessThanOrEqualTo(c.presses.length));
        for (var i = 0; i < out.length; i++) {
          expect(
            out[i].$2 - out[i].$1,
            greaterThanOrEqualTo(d),
            reason: 'Press $i shorter than d = $d',
          );
          if (i > 0) {
            expect(
              out[i].$1 - out[i - 1].$2,
              greaterThanOrEqualTo(d),
              reason: 'Gap before Press $i shorter than d = $d',
            );
          }
        }

        // REQ-DEBOUNCE-6: every output timestamp is an input timestamp.
        final pressedAts = {for (final p in c.presses) p.$1};
        final releasedAts = {for (final p in c.presses) p.$2};
        for (final p in out) {
          expect(pressedAts, contains(p.$1));
          expect(releasedAts, contains(p.$2));
        }

        // REQ-DEBOUNCE-6: an unmerged input Press lasting at least d is kept
        // unchanged.
        final p = c.presses;
        for (var i = 0; i < p.length; i++) {
          final mergesBefore = i > 0 && p[i].$1 - p[i - 1].$2 < d;
          final mergesAfter = i + 1 < p.length && p[i + 1].$1 - p[i].$2 < d;
          if (!mergesBefore && !mergesAfter && p[i].$2 - p[i].$1 >= d) {
            expect(out, contains(p[i]), reason: 'unmerged Press $i lost');
          }
        }

        // REQ-DEBOUNCE-10: with d = 0 the output equals the input.
        if (d == 0) expect(out, equals(c.presses));
      },
      maxExamples: 200,
      seed: 101003,
      onFalsify: report(101003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        expect(withShort / counted, greaterThanOrEqualTo(0.10)); // REQ-PBT-8
        expect(withZeroD, greaterThan(0), reason: 'no d = 0 case');
      },
    );
  });

  // Feature: adaptive-timing, Property 2: Debounce is idempotent
  property('REQ-DEBOUNCE-8 REQ-PBT-8 debounce is idempotent', () {
    var counted = 0, withShort = 0;
    forAll(
      pressList(),
      (c) {
        counted++;
        if (hasShortDuration(c)) withShort++;
        final debouncer = Debouncer(TimingConfig(debounceTime: c.debounceTime));
        final input = <Press>[for (final (a, b) in c.presses) Press(a, b)];
        final once = debouncer.debounce(input);
        final twice = debouncer.debounce(once);

        // REQ-DEBOUNCE-8: a second debounce returns an equal list.
        expect(_records(twice), equals(_records(once)));
      },
      maxExamples: 200,
      seed: 102003,
      onFalsify: report(102003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        expect(withShort / counted, greaterThanOrEqualTo(0.10)); // REQ-PBT-8
      },
    );
  });

  // Feature: adaptive-timing, Property 3: Bounce never becomes a Symbol
  property('REQ-DEBOUNCE-9 REQ-BATCH-1 REQ-PBT-8 bounce never becomes a '
      'Symbol', () {
    var counted = 0, withShort = 0, withDrop = 0, zeroD = 0, maxD = 0;
    var negativeStart = 0;
    forAll(
      decodeInput(),
      (input) {
        final k = input.calibration;
        final c = input.config;
        final d = c.debounceTime;
        counted++;
        if (eventsHaveShortDuration(input.events, d)) withShort++;
        final m = k.ditLength < k.symbolGap ? k.ditLength : k.symbolGap;
        if (d == 0) zeroD++;
        if (d == m) maxD++;
        if (input.events.isNotEmpty && input.events.first.$2 < 0) {
          negativeStart++;
        }

        // The case meets the REQ-TIMING-9 precondition.
        expect(d, inInclusiveRange(0, m));

        final events = <SwitchEvent>[
          for (final (isPress, t) in input.events)
            isPress ? SwitchEvent.press(t) : SwitchEvent.release(t),
        ];
        final decoder = BatchDecoder(
          Calibration(
            ditLength: k.ditLength,
            dahLength: k.dahLength,
            symbolGap: k.symbolGap,
            letterGap: k.letterGap,
          ),
          TimingConfig(debounceTime: d, wordGapFactor: c.wordGapFactor),
        );
        final output = decoder.decode(events);

        // The Symbols of the output, read in order.
        final actual = StringBuffer();
        for (final item in output) {
          switch (item.kind) {
            case DecodedItemKind.letter:
              actual.write(ituFixture[item.character]);
            case DecodedItemKind.unknownLetter:
              actual.write(item.symbols);
            case DecodedItemKind.wordSpace:
              break;
          }
        }

        // One Symbol per Press of the reference debounce, classified against
        // the exact Press_Threshold.
        final paired = pairEvents(input.events);
        final kept = referenceDebounce(paired, d);
        if (kept.length < paired.length) withDrop++;
        final threshold = exactThresholds(k, c.wordGapFactor).pressThreshold;
        final expected = <String>[
          for (final (a, b) in kept) b - a < threshold ? '.' : '-',
        ].join();

        final reason =
            'Calibration($k), d = $d, factor ${c.wordGapFactor}, '
            '${paired.length} Presses, ${kept.length} kept';
        // REQ-DEBOUNCE-9: exactly one Symbol per debounced Press, so none
        // from a Press shorter than d after merging. REQ-BATCH-1.
        expect(actual.length, equals(kept.length), reason: reason);
        expect(actual.toString(), equals(expected), reason: reason);
        for (final (a, b) in kept) {
          expect(b - a, greaterThanOrEqualTo(d), reason: reason);
        }
      },
      maxExamples: 200,
      seed: 103003,
      onFalsify: report(103003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        expect(withShort / counted, greaterThanOrEqualTo(0.10)); // REQ-PBT-8
        expect(withDrop, greaterThan(0), reason: 'no case drops a Press');
        expect(zeroD, greaterThan(0), reason: 'no d = 0 case');
        expect(maxD, greaterThan(0), reason: 'no d = min(dit, sg) case');
        expect(negativeStart, greaterThan(0), reason: 'no negative start');
      },
    );
  });

  // Feature: adaptive-timing, Property 4: Calibration round trip
  property('REQ-CAL-15 REQ-CAL-2 REQ-CAL-6 REQ-CAL-20 calibrating from the '
      'Ideal_Timing returns the original Calibration', () {
    var counted = 0, zeroD = 0, maxD = 0, mixedCase = 0;
    var negativeStart = 0, largeCalibration = 0;
    forAll(
      roundTripInput(),
      (input) {
        final k = input.calibration;
        final c = input.config;
        final word = input.word;
        counted++;
        final m = k.ditLength < k.symbolGap ? k.ditLength : k.symbolGap;
        if (c.debounceTime == 0) zeroD++;
        if (c.debounceTime == m) maxD++;
        if (word != word.toUpperCase() && word != word.toLowerCase()) {
          mixedCase++;
        }
        if (input.start < 0) negativeStart++;
        if (k.letterGap > 10000000 || k.dahLength > 10000000) {
          largeCalibration++;
        }

        // The case meets the REQ-CAL-15 preconditions.
        expect(word.length, inInclusiveRange(2, 16));
        expect(c.debounceTime, inInclusiveRange(0, m));

        final events = <SwitchEvent>[
          for (final (isPress, t) in idealTiming(
            word,
            k,
            c.wordGapFactor,
            input.start,
          ))
            isPress ? SwitchEvent.press(t) : SwitchEvent.release(t),
        ];
        expect(events.first.timestamp, equals(input.start));
        expect(
          events.last.timestamp,
          lessThanOrEqualTo(SwitchEvent.maxTimestamp),
        );

        final calibrator = Calibrator(
          TimingConfig(
            debounceTime: c.debounceTime,
            wordGapFactor: c.wordGapFactor,
          ),
        );
        final original = Calibration(
          ditLength: k.ditLength,
          dahLength: k.dahLength,
          symbolGap: k.symbolGap,
          letterGap: k.letterGap,
        );
        final reason =
            'word "$word", Calibration($k), debounceTime ${c.debounceTime}, '
            'start ${input.start}';

        // REQ-CAL-15, REQ-CAL-2, REQ-CAL-6: accepted with the same values.
        final result = calibrator.calibrate(events, word: word);
        expect(
          result.rejection?.reason,
          isNull,
          reason: '$reason: ${result.rejection}',
        );
        expect(result.calibration, equals(original), reason: reason);

        // REQ-CAL-20: the word in all upper and all lower case gives the
        // same result.
        for (final variant in <String>[
          word.toUpperCase(),
          word.toLowerCase(),
        ]) {
          final other = calibrator.calibrate(events, word: variant);
          expect(
            other.calibration,
            equals(original),
            reason: '$reason, as "$variant"',
          );
        }
      },
      maxExamples: 200,
      seed: 104003,
      onFalsify: report(104003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        // The generator must reach both Debounce_Time ends, mixed-case
        // words, negative starts and large values.
        expect(zeroD, greaterThan(0), reason: 'no d = 0 case');
        expect(maxD, greaterThan(0), reason: 'no d = min(dit, sg) case');
        expect(mixedCase, greaterThan(0), reason: 'no mixed-case word');
        expect(negativeStart, greaterThan(0), reason: 'no negative start');
        expect(largeCalibration, greaterThan(0), reason: 'no large values');
      },
    );
  });

  // Feature: adaptive-timing, Property 5: Calibrator follows the rejection order and never throws
  property('REQ-CAL-3 REQ-CAL-7 REQ-CAL-8 REQ-CAL-9 REQ-CAL-10 REQ-CAL-11 '
      'REQ-CAL-12 REQ-CAL-31 REQ-EVENT-2 REQ-EVENT-6 Calibrator follows the '
      'rejection order and never throws', () {
    var counted = 0, accepted = 0, zeroD = 0;
    final reasons = <String, int>{};
    final wordRules = <String, int>{};
    forAll(
      rejectionInput(),
      (input) {
        counted++;
        final word = input.word;
        final records = input.keying.events;
        final d = input.config.debounceTime;
        if (d == 0) zeroD++;
        final rule = referenceWordRule(word);
        if (rule != null) wordRules[rule] = (wordRules[rule] ?? 0) + 1;

        final events = <SwitchEvent>[
          for (final (isPress, t) in records)
            isPress ? SwitchEvent.press(t) : SwitchEvent.release(t),
        ];
        final before = List<SwitchEvent>.of(events);
        final calibrator = Calibrator(
          TimingConfig(
            debounceTime: d,
            wordGapFactor: input.config.wordGapFactor,
          ),
        );
        final reason =
            'word "$word", Calibration(${input.calibration}), '
            'debounceTime $d, perturbation ${input.keying.perturbation}, '
            '${records.length} events';

        // REQ-CAL-31, REQ-EVENT-2: returns normally with exactly one of
        // calibration and rejection.
        late final CalibrationResult result;
        expect(
          () => result = calibrator.calibrate(events, word: word),
          returnsNormally,
          reason: reason,
        );
        expect(
          (result.calibration == null) != (result.rejection == null),
          isTrue,
          reason: reason,
        );
        expect(result.isAccepted, equals(result.calibration != null));

        // REQ-EVENT-6: the caller's Event_Sequence is unchanged.
        expect(events, equals(before), reason: reason);

        // REQ-CAL-3, REQ-CAL-7 to REQ-CAL-12, REQ-CAL-31: the same outcome
        // as the reference Calibrator.
        final expected = referenceCalibrate(word, records, d);
        final key = expected.reason ?? 'accepted';
        reasons[key] = (reasons[key] ?? 0) + 1;
        expect(
          result.rejection?.reason.name,
          equals(expected.reason),
          reason: '$reason: ${result.rejection}',
        );
        final message = result.rejection?.message ?? '';
        final numbers = <int>[
          for (final match in RegExp(r'\d+').allMatches(message))
            int.parse(match.group(0)!),
        ];
        switch (expected.reason) {
          case null:
            accepted++;
            final k = expected.calibration!;
            expect(
              result.calibration,
              equals(
                Calibration(
                  ditLength: k.ditLength,
                  dahLength: k.dahLength,
                  symbolGap: k.symbolGap,
                  letterGap: k.letterGap,
                ),
              ),
              reason: reason,
            );
          case 'invalidEvents':
            // REQ-CAL-11: the REQ-EVENT-3 index and rule.
            expect(numbers, equals(<int>[expected.eventIndex!]));
            expect(
              message,
              contains(
                TimingInputErrorKind.values.byName(expected.eventRule!).phrase,
              ),
              reason: reason,
            );
          case 'wrongPressCount':
            // REQ-CAL-8: expected and received counts.
            expect(
              numbers,
              equals(<int>[
                expected.expectedPresses!,
                expected.receivedPresses!,
              ]),
              reason: reason,
            );
        }
      },
      maxExamples: 200,
      seed: 105003,
      onFalsify: report(105003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        // The generator must reach acceptance, every Rejection_Reason and
        // every REQ-CAL-3 rule.
        expect(accepted, greaterThan(0), reason: 'no accepted case');
        for (final name in <String>[
          for (final r in RejectionReason.values) r.name,
        ]) {
          expect(reasons[name] ?? 0, greaterThan(0), reason: 'no $name case');
        }
        for (final name in const <String>[
          'empty',
          'tooLong',
          'badCharacter',
          'tooShort',
          'noDit',
          'noDah',
          'noLongCode',
        ]) {
          expect(wordRules[name] ?? 0, greaterThan(0), reason: 'no $name');
        }
        expect(zeroD, greaterThan(0), reason: 'no d = 0 case');
      },
    );
  });

  // Feature: adaptive-timing, Property 6: Thresholds match the exact formulas and are ordered
  property('REQ-TIMING-1 REQ-TIMING-2 thresholds match the exact formulas '
      'and are ordered', () {
    var counted = 0, nearCap = 0, adjacent = 0, extremeFactor = 0;
    forAll(
      thresholdInput(),
      (input) {
        final (k, factor) = input;
        counted++;
        if (k.dahLength == maxCalibrationValue ||
            k.letterGap == maxCalibrationValue) {
          nearCap++;
        }
        if (k.dahLength == k.ditLength + 1 || k.letterGap == k.symbolGap + 1) {
          adjacent++;
        }
        if (factor == justAboveOne || factor == maxWordGapFactor) {
          extremeFactor++;
        }

        final classifier = Classifier(
          Calibration(
            ditLength: k.ditLength,
            dahLength: k.dahLength,
            symbolGap: k.symbolGap,
            letterGap: k.letterGap,
          ),
          TimingConfig(wordGapFactor: factor),
        );
        final exact = exactThresholds(k, factor);
        final reason = 'Calibration($k), wordGapFactor $factor';

        // REQ-TIMING-1: each threshold equals the exact formula.
        expect(
          classifier.pressThreshold,
          equals(exact.pressThreshold),
          reason: reason,
        );
        expect(
          classifier.letterGapThreshold,
          equals(exact.letterGapThreshold),
          reason: reason,
        );
        expect(
          classifier.wordGapThreshold,
          equals(exact.wordGapThreshold),
          reason: reason,
        );

        // REQ-TIMING-2: dit < Press_Threshold ≤ dah,
        // Symbol_Gap < Letter_Gap_Threshold ≤ Letter_Gap,
        // Word_Gap_Threshold > Letter_Gap.
        expect(
          classifier.pressThreshold,
          greaterThan(k.ditLength),
          reason: reason,
        );
        expect(
          classifier.pressThreshold,
          lessThanOrEqualTo(k.dahLength),
          reason: reason,
        );
        expect(
          classifier.letterGapThreshold,
          greaterThan(k.symbolGap),
          reason: reason,
        );
        expect(
          classifier.letterGapThreshold,
          lessThanOrEqualTo(k.letterGap),
          reason: reason,
        );
        expect(
          classifier.wordGapThreshold,
          greaterThan(k.letterGap),
          reason: reason,
        );
      },
      maxExamples: 200,
      seed: 106003,
      onFalsify: report(106003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        // The generator must reach the edges it is built to cover.
        expect(nearCap, greaterThan(0), reason: 'no value at 2^40');
        expect(adjacent, greaterThan(0), reason: 'no adjacent pair');
        expect(extremeFactor, greaterThan(0), reason: 'no extreme factor');
      },
    );
  });

  // Feature: adaptive-timing, Property 7: Classification is a threshold comparison
  property('REQ-TIMING-3 REQ-TIMING-4 REQ-TIMING-11 classification is a '
      'threshold comparison', () {
    var counted = 0, negative = 0;
    var atPress = 0, atLetter = 0, atWord = 0;
    var dits = 0, dahs = 0, inside = 0, between = 0, words = 0;
    forAll(
      classificationInput(),
      (input) {
        final (k, factor, x) = input;
        counted++;
        final classifier = Classifier(
          Calibration(
            ditLength: k.ditLength,
            dahLength: k.dahLength,
            symbolGap: k.symbolGap,
            letterGap: k.letterGap,
          ),
          TimingConfig(wordGapFactor: factor),
        );
        final reason = 'Calibration($k), wordGapFactor $factor, duration $x';

        if (x < 0) {
          // REQ-TIMING-11: both methods throw negativeDuration, no index.
          negative++;
          final isNegativeDuration = isA<TimingInputException>()
              .having(
                (e) => e.kind,
                'kind',
                TimingInputErrorKind.negativeDuration,
              )
              .having((e) => e.index, 'index', isNull);
          expect(
            () => classifier.classifyPress(x),
            throwsA(isNegativeDuration),
            reason: reason,
          );
          expect(
            () => classifier.classifyGap(x),
            throwsA(isNegativeDuration),
            reason: reason,
          );
        } else {
          // Boundary coverage, read from the oracle thresholds.
          final t = exactThresholds(k, factor);
          if (x == t.pressThreshold) atPress++;
          if (x == t.letterGapThreshold) atLetter++;
          if (x == t.wordGapThreshold) atWord++;

          // REQ-TIMING-3: dit exactly when x < Press_Threshold.
          final expectedSymbol = x < classifier.pressThreshold
              ? MorseSymbol.dit
              : MorseSymbol.dah;
          expect(
            classifier.classifyPress(x),
            equals(expectedSymbol),
            reason: reason,
          );
          if (expectedSymbol == MorseSymbol.dit) {
            dits++;
          } else {
            dahs++;
          }

          // REQ-TIMING-4: insideLetter below Letter_Gap_Threshold,
          // betweenWords from Word_Gap_Threshold, betweenLetters otherwise.
          final GapClass expectedGap;
          if (x < classifier.letterGapThreshold) {
            expectedGap = GapClass.insideLetter;
            inside++;
          } else if (x >= classifier.wordGapThreshold) {
            expectedGap = GapClass.betweenWords;
            words++;
          } else {
            expectedGap = GapClass.betweenLetters;
            between++;
          }
          expect(
            classifier.classifyGap(x),
            equals(expectedGap),
            reason: reason,
          );
        }
      },
      maxExamples: 200,
      seed: 107003,
      onFalsify: report(107003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        // The generator must reach every boundary and every class.
        expect(negative, greaterThan(0), reason: 'no negative duration');
        expect(atPress, greaterThan(0), reason: 'no x = Press_Threshold');
        expect(atLetter, greaterThan(0), reason: 'no x = Letter_Gap_Threshold');
        expect(atWord, greaterThan(0), reason: 'no x = Word_Gap_Threshold');
        expect(dits, greaterThan(0), reason: 'no dit');
        expect(dahs, greaterThan(0), reason: 'no dah');
        expect(inside, greaterThan(0), reason: 'no insideLetter');
        expect(between, greaterThan(0), reason: 'no betweenLetters');
        expect(words, greaterThan(0), reason: 'no betweenWords');
      },
    );
  });

  // Feature: adaptive-timing, Property 8: Press jitter is tolerated
  property('REQ-TIMING-7 press jitter is tolerated', () {
    var counted = 0, dits = 0, dahs = 0;
    var atDitEdge = 0, atDahEdge = 0, largeCalibration = 0;
    forAll(
      pressJitterInput(),
      (input) {
        final (w, band, x) = input;
        final k = w.calibration;
        counted++;
        if (k.dahLength > 10000000) largeCalibration++;
        final reason =
            'Calibration($k), wordGapFactor ${w.wordGapFactor}, '
            'debounceTime ${w.debounceTime}, duration $x';

        // The case is a Well_Separated_Calibration within the 2^40 cap.
        expect(k.dahLength, greaterThanOrEqualTo(2 * k.ditLength));
        expect(k.letterGap, greaterThanOrEqualTo(2 * k.symbolGap));
        expect(k.dahLength, lessThanOrEqualTo(maxCalibrationValue));
        expect(k.letterGap, lessThanOrEqualTo(maxCalibrationValue));
        expect(w.wordGapFactor, inInclusiveRange(1.5, 8.0));
        expect(
          2 * w.debounceTime,
          lessThanOrEqualTo(
            k.ditLength < k.symbolGap ? k.ditLength : k.symbolGap,
          ),
        );

        final classifier = Classifier(
          Calibration(
            ditLength: k.ditLength,
            dahLength: k.dahLength,
            symbolGap: k.symbolGap,
            letterGap: k.letterGap,
          ),
          TimingConfig(
            debounceTime: w.debounceTime,
            wordGapFactor: w.wordGapFactor,
          ),
        );

        if (band == JitterBand.dit) {
          // REQ-TIMING-7: x ≤ 1.2 × Dit_Length exactly, so a dit.
          expect(5 * x, lessThanOrEqualTo(6 * k.ditLength), reason: reason);
          if (x == 6 * k.ditLength ~/ 5) atDitEdge++;
          dits++;
          expect(
            classifier.classifyPress(x),
            equals(MorseSymbol.dit),
            reason: reason,
          );
        } else {
          // REQ-TIMING-7: x ≥ 0.8 × Dah_Length exactly, so a dah.
          expect(5 * x, greaterThanOrEqualTo(4 * k.dahLength), reason: reason);
          if (x == (4 * k.dahLength + 4) ~/ 5) atDahEdge++;
          dahs++;
          expect(
            classifier.classifyPress(x),
            equals(MorseSymbol.dah),
            reason: reason,
          );
        }
      },
      maxExamples: 200,
      seed: 108003,
      onFalsify: report(108003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        // The generator must reach both bands, their edges and large values.
        expect(dits, greaterThan(0), reason: 'no dit-band case');
        expect(dahs, greaterThan(0), reason: 'no dah-band case');
        expect(atDitEdge, greaterThan(0), reason: 'no x at 1.2 × dit');
        expect(atDahEdge, greaterThan(0), reason: 'no x at 0.8 × dah');
        expect(largeCalibration, greaterThan(0), reason: 'no large values');
      },
    );
  });

  // Feature: adaptive-timing, Property 9: Gap jitter is tolerated
  property('REQ-TIMING-8 gap jitter is tolerated', () {
    var counted = 0, inside = 0, between = 0, words = 0;
    var atInsideEdge = 0, atLetterLow = 0, atLetterHigh = 0, atWordEdge = 0;
    var largeCalibration = 0;
    forAll(
      gapJitterInput(),
      (input) {
        final (w, band, x) = input;
        final k = w.calibration;
        counted++;
        if (k.letterGap > 10000000) largeCalibration++;
        final reason =
            'Calibration($k), wordGapFactor ${w.wordGapFactor}, '
            'debounceTime ${w.debounceTime}, duration $x';

        // The case is a Well_Separated_Calibration within the 2^40 cap.
        expect(k.dahLength, greaterThanOrEqualTo(2 * k.ditLength));
        expect(k.letterGap, greaterThanOrEqualTo(2 * k.symbolGap));
        expect(k.dahLength, lessThanOrEqualTo(maxCalibrationValue));
        expect(k.letterGap, lessThanOrEqualTo(maxCalibrationValue));
        expect(w.wordGapFactor, inInclusiveRange(1.5, 8.0));
        expect(
          2 * w.debounceTime,
          lessThanOrEqualTo(
            k.ditLength < k.symbolGap ? k.ditLength : k.symbolGap,
          ),
        );

        final classifier = Classifier(
          Calibration(
            ditLength: k.ditLength,
            dahLength: k.dahLength,
            symbolGap: k.symbolGap,
            letterGap: k.letterGap,
          ),
          TimingConfig(
            debounceTime: w.debounceTime,
            wordGapFactor: w.wordGapFactor,
          ),
        );

        final GapClass expected;
        switch (band) {
          case JitterBand.insideLetter:
            // REQ-TIMING-8: x ≤ 1.2 × Symbol_Gap exactly, so inside-letter.
            expect(5 * x, lessThanOrEqualTo(6 * k.symbolGap), reason: reason);
            if (x == 6 * k.symbolGap ~/ 5) atInsideEdge++;
            inside++;
            expected = GapClass.insideLetter;
          case JitterBand.betweenLetters:
            // REQ-TIMING-8: 0.8 × Letter_Gap ≤ x ≤ 1.2 × Letter_Gap exactly,
            // so between-letters.
            expect(
              5 * x,
              greaterThanOrEqualTo(4 * k.letterGap),
              reason: reason,
            );
            expect(5 * x, lessThanOrEqualTo(6 * k.letterGap), reason: reason);
            if (x == (4 * k.letterGap + 4) ~/ 5) atLetterLow++;
            if (x == 6 * k.letterGap ~/ 5) atLetterHigh++;
            between++;
            expected = GapClass.betweenLetters;
          case JitterBand.betweenWords:
            // REQ-TIMING-8: x ≥ 1.2 × Word_Gap_Threshold exactly, so
            // between-words. The threshold is the engine's own.
            final word = classifier.wordGapThreshold;
            expect(5 * x, greaterThanOrEqualTo(6 * word), reason: reason);
            if (x == (6 * word + 4) ~/ 5) atWordEdge++;
            words++;
            expected = GapClass.betweenWords;
          case JitterBand.dit:
          case JitterBand.dah:
            fail('Press band $band in a Gap case');
        }
        expect(classifier.classifyGap(x), equals(expected), reason: reason);
      },
      maxExamples: 200,
      seed: 109003,
      onFalsify: report(109003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        // The generator must reach every band, its edges and large values.
        expect(inside, greaterThan(0), reason: 'no inside-letter case');
        expect(between, greaterThan(0), reason: 'no between-letters case');
        expect(words, greaterThan(0), reason: 'no between-words case');
        expect(atInsideEdge, greaterThan(0), reason: 'no x at 1.2 × sg');
        expect(atLetterLow, greaterThan(0), reason: 'no x at 0.8 × lg');
        expect(atLetterHigh, greaterThan(0), reason: 'no x at 1.2 × lg');
        expect(atWordEdge, greaterThan(0), reason: 'no x at 1.2 × W');
        expect(largeCalibration, greaterThan(0), reason: 'no large values');
      },
    );
  });

  // Feature: adaptive-timing, Property 10: Classification is scale invariant
  property('REQ-TIMING-10 classification is scale invariant', () {
    var counted = 0, scaled = 0, atThreshold = 0, largeScaled = 0;
    var dits = 0, dahs = 0, inside = 0, between = 0, words = 0;
    forAll(
      scaleInput(),
      (input) {
        final k = input.k;
        final c = input.calibration;
        final x = input.duration;
        final factor = input.wordGapFactor;
        counted++;
        if (k > 1) scaled++;

        // The case meets the REQ-TIMING-10 preconditions.
        expect(k, inInclusiveRange(1, 1000));
        expect((factor * 4).truncateToDouble(), equals(factor * 4));
        expect(factor, inInclusiveRange(1.25, 8.0));
        expect(k * c.dahLength, lessThanOrEqualTo(maxCalibrationValue));
        expect(k * c.letterGap, lessThanOrEqualTo(maxCalibrationValue));

        final config = TimingConfig(wordGapFactor: factor);
        final original = Classifier(
          Calibration(
            ditLength: c.ditLength,
            dahLength: c.dahLength,
            symbolGap: c.symbolGap,
            letterGap: c.letterGap,
          ),
          config,
        );
        final scaledClassifier = Classifier(
          Calibration(
            ditLength: k * c.ditLength,
            dahLength: k * c.dahLength,
            symbolGap: k * c.symbolGap,
            letterGap: k * c.letterGap,
          ),
          config,
        );
        expect(x, inInclusiveRange(0, 10 * original.wordGapThreshold));
        if (x == original.pressThreshold ||
            x == original.letterGapThreshold ||
            x == original.wordGapThreshold) {
          atThreshold++;
        }
        if (k * c.letterGap > 10000000000) largeScaled++;

        final reason =
            'Calibration($c), wordGapFactor $factor, duration $x, k $k';

        // REQ-TIMING-10: the same class for k·x under the scaled
        // Calibration as for x under the original.
        final symbol = original.classifyPress(x);
        expect(
          scaledClassifier.classifyPress(k * x),
          equals(symbol),
          reason: reason,
        );
        final gap = original.classifyGap(x);
        expect(
          scaledClassifier.classifyGap(k * x),
          equals(gap),
          reason: reason,
        );

        if (symbol == MorseSymbol.dit) {
          dits++;
        } else {
          dahs++;
        }
        switch (gap) {
          case GapClass.insideLetter:
            inside++;
          case GapClass.betweenLetters:
            between++;
          case GapClass.betweenWords:
            words++;
        }
      },
      maxExamples: 200,
      seed: 110003,
      onFalsify: report(110003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        // The generator must reach scaling, thresholds, large values and
        // every class.
        expect(scaled, greaterThan(0), reason: 'no k > 1');
        expect(atThreshold, greaterThan(0), reason: 'no x at a threshold');
        expect(largeScaled, greaterThan(0), reason: 'no large scaled values');
        expect(dits, greaterThan(0), reason: 'no dit');
        expect(dahs, greaterThan(0), reason: 'no dah');
        expect(inside, greaterThan(0), reason: 'no insideLetter');
        expect(between, greaterThan(0), reason: 'no betweenLetters');
        expect(words, greaterThan(0), reason: 'no betweenWords');
      },
    );
  });

  // Feature: adaptive-timing, Property 11: Jittered keying decodes to the text
  property('REQ-BATCH-8 REQ-BATCH-2 jittered keying decodes to the text', () {
    var counted = 0, withSpace = 0, atLowEdge = 0, atHighEdge = 0;
    var zeroD = 0, largeCalibration = 0;
    forAll(
      jitteredText(),
      (input) {
        final w = input.setting;
        final k = w.calibration;
        final text = input.text;
        counted++;
        if (text.contains(' ')) withSpace++;
        if (input.factors.contains(80)) atLowEdge++;
        if (input.factors.contains(120)) atHighEdge++;
        if (w.debounceTime == 0) zeroD++;
        if (k.letterGap > 10000000) largeCalibration++;

        // The case meets the REQ-BATCH-8 preconditions: a
        // Well_Separated_Calibration with every value at least 1,000 µs, a
        // text of 1 to 20 characters with single inner spaces only, and
        // jitter factors from 0.8 to 1.2.
        for (final v in <int>[
          k.ditLength,
          k.dahLength,
          k.symbolGap,
          k.letterGap,
        ]) {
          expect(v, inInclusiveRange(1000, maxCalibrationValue));
        }
        expect(k.dahLength, greaterThanOrEqualTo(2 * k.ditLength));
        expect(k.letterGap, greaterThanOrEqualTo(2 * k.symbolGap));
        expect(w.wordGapFactor, inInclusiveRange(1.5, 8.0));
        expect(
          2 * w.debounceTime,
          lessThanOrEqualTo(
            k.ditLength < k.symbolGap ? k.ditLength : k.symbolGap,
          ),
        );
        expect(text.length, inInclusiveRange(1, maxJitteredTextLength));
        expect(text, isNot(startsWith(' ')));
        expect(text, isNot(endsWith(' ')));
        expect(text, isNot(contains('  ')));
        for (final f in input.factors) {
          expect(f, inInclusiveRange(80, 120));
        }

        final events = <SwitchEvent>[
          for (final (isPress, t) in input.events)
            isPress ? SwitchEvent.press(t) : SwitchEvent.release(t),
        ];
        expect(events.first.timestamp, equals(0));

        final decoder = BatchDecoder(
          Calibration(
            ditLength: k.ditLength,
            dahLength: k.dahLength,
            symbolGap: k.symbolGap,
            letterGap: k.letterGap,
          ),
          TimingConfig(
            debounceTime: w.debounceTime,
            wordGapFactor: w.wordGapFactor,
          ),
        );
        final output = decoder.decode(events);

        // Render the output with explicit content, never through
        // DecodedItem.toString() (design T12). A space stands for a
        // Word_Space and `[…]` for an Unknown_Letter_Item.
        final rendered = <String>[
          for (final item in output)
            switch (item.kind) {
              DecodedItemKind.letter => item.character!,
              DecodedItemKind.unknownLetter => '[${item.symbols}]',
              DecodedItemKind.wordSpace => ' ',
            },
        ];
        final reason =
            'text "$text", Calibration($k), '
            'wordGapFactor ${w.wordGapFactor}, '
            'debounceTime ${w.debounceTime}, factors ${input.factors}, '
            'decoded "${rendered.join()}"';

        // REQ-BATCH-8: one Letter_Item per non-space character, carrying
        // that character (REQ-BATCH-2), and one Word_Space per space, in
        // order, with no Unknown_Letter_Item.
        expect(
          output.where((i) => i.kind == DecodedItemKind.unknownLetter),
          isEmpty,
          reason: reason,
        );
        expect(
          rendered,
          equals(<String>[for (final c in text.split('')) c]),
          reason: reason,
        );
      },
      maxExamples: 200,
      seed: 111003,
      onFalsify: report(111003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        // The generator must reach spaces, both jitter edges, d = 0, large
        // values and the longest text.
        expect(withSpace, greaterThan(0), reason: 'no text with a space');
        expect(atLowEdge, greaterThan(0), reason: 'no factor of 0.8');
        expect(atHighEdge, greaterThan(0), reason: 'no factor of 1.2');
        expect(zeroD, greaterThan(0), reason: 'no d = 0 case');
        expect(largeCalibration, greaterThan(0), reason: 'no large values');
      },
    );
  });

  // Feature: adaptive-timing, Property 12: Batch decoding is scale invariant
  property('REQ-BATCH-9 batch decoding is scale invariant', () {
    var counted = 0, withBounce = 0, shrunk = 0, grown = 0;
    var withWordSpace = 0, nonEmpty = 0, largeCalibration = 0;
    forAll(
      marginScenario(),
      (s) {
        final k = s.calibration;
        final d = s.config.debounceTime;
        final f = s.config.wordGapFactor;
        counted++;
        if (s.bounces > 0) withBounce++;
        if (s.k < 1) shrunk++;
        if (s.k > 1) grown++;
        if (k.letterGap > 10000000) largeCalibration++;

        // Scaling as REQ-BATCH-9 defines it: round each value to the nearest
        // Microsecond, keep the first timestamp, rebuild the rest.
        int scale(int v) => (v * s.k).round();
        List<SwitchEvent> eventsOf(List<int> durations) {
          final events = <SwitchEvent>[];
          var t = s.start;
          for (var i = 0; i < durations.length; i++) {
            if (i.isEven) {
              events.add(SwitchEvent.press(t));
              t += durations[i];
              events.add(SwitchEvent.release(t));
            } else {
              t += durations[i];
            }
          }
          return events;
        }

        final scaledDurations = <int>[for (final x in s.durations) scale(x)];
        final scaledValues = <int>[
          scale(k.ditLength),
          scale(k.dahLength),
          scale(k.symbolGap),
          scale(k.letterGap),
        ];

        // The case meets the REQ-BATCH-9 preconditions: every duration at
        // least 1,000 µs, every raw duration more than 1 percent and every
        // post-debounce duration more than 2 percent (the generator's
        // stricter margin) from d and every threshold, k from 0.25 to 4, and
        // the scaled Calibration within the 2^40 cap.
        expect(s.k, inInclusiveRange(0.25, 4.0));
        for (final v in <int>[
          k.ditLength,
          k.dahLength,
          k.symbolGap,
          k.letterGap,
        ]) {
          expect(v, greaterThanOrEqualTo(1000));
        }
        for (final v in scaledValues) {
          expect(v, inInclusiveRange(1, maxCalibrationValue));
        }
        final t = exactThresholds(k, f);
        final marks = <int>[
          d,
          t.pressThreshold,
          t.letterGapThreshold,
          t.wordGapThreshold,
        ];
        bool clear(int x, int percent) =>
            marks.every((m) => 100 * (x - m).abs() > percent * m);
        for (final x in s.durations) {
          expect(x, greaterThanOrEqualTo(1000));
          expect(clear(x, 1), isTrue, reason: 'raw duration $x');
        }
        final events = eventsOf(s.durations);
        final records = <EventRecord>[
          for (final e in events)
            (e.kind == SwitchEventKind.press, e.timestamp),
        ];
        final kept = referenceDebounce(pairEvents(records), d);
        for (var i = 0; i < kept.length; i++) {
          final press = kept[i].$2 - kept[i].$1;
          expect(clear(press, 2), isTrue, reason: 'kept Press $press');
          if (i > 0) {
            final gap = kept[i].$1 - kept[i - 1].$2;
            expect(clear(gap, 2), isTrue, reason: 'kept Gap $gap');
          }
        }
        final scaledEvents = eventsOf(scaledDurations);
        for (final e in <SwitchEvent>[...events, ...scaledEvents]) {
          expect(
            e.timestamp,
            inInclusiveRange(-maxTimestampMagnitude, maxTimestampMagnitude),
          );
        }

        final original = BatchDecoder(
          Calibration(
            ditLength: k.ditLength,
            dahLength: k.dahLength,
            symbolGap: k.symbolGap,
            letterGap: k.letterGap,
          ),
          TimingConfig(debounceTime: d, wordGapFactor: f),
        ).decode(events);
        final scaled = BatchDecoder(
          Calibration(
            ditLength: scaledValues[0],
            dahLength: scaledValues[1],
            symbolGap: scaledValues[2],
            letterGap: scaledValues[3],
          ),
          TimingConfig(debounceTime: scale(d), wordGapFactor: f),
        ).decode(scaledEvents);

        if (original.isNotEmpty) nonEmpty++;
        if (original.any((i) => i.kind == DecodedItemKind.wordSpace)) {
          withWordSpace++;
        }

        // Render with explicit content, never DecodedItem.toString() (T12).
        String render(List<DecodedItem> items) => <String>[
          for (final item in items)
            switch (item.kind) {
              DecodedItemKind.letter => item.character!,
              DecodedItemKind.unknownLetter => '[${item.symbols}]',
              DecodedItemKind.wordSpace => ' ',
            },
        ].join();
        final reason =
            'Calibration($k), d = $d, factor $f, k = ${s.k}, '
            '${s.durations.length} durations, ${s.bounces} bounces, '
            'original "${render(original)}", scaled "${render(scaled)}"';

        // REQ-BATCH-9: scaling the input leaves the output unchanged.
        expect(scaled, equals(original), reason: reason);
      },
      maxExamples: 200,
      seed: 112003,
      onFalsify: report(112003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        expect(withBounce, greaterThan(0), reason: 'no case with bounce');
        expect(shrunk, greaterThan(0), reason: 'no case with k < 1');
        expect(grown, greaterThan(0), reason: 'no case with k > 1');
        expect(nonEmpty, greaterThan(0), reason: 'no non-empty output');
        expect(withWordSpace, greaterThan(0), reason: 'no Word_Space');
        expect(largeCalibration, greaterThan(0), reason: 'no large values');
      },
    );
  });

  // Feature: adaptive-timing, Property 13: Batch output matches the reference decoder and is well formed
  property('REQ-BATCH-1 REQ-BATCH-3 REQ-BATCH-4 REQ-EVENT-2 batch output '
      'matches the reference decoder and is well formed', () {
    var counted = 0, empty = 0, withUnknown = 0, withWordSpace = 0;
    var unknownThenLetter = 0, withZeroDuration = 0, negativeStart = 0;
    forAll(
      referenceDecodeInput(),
      (input) {
        final k = input.calibration;
        final c = input.config;
        final d = c.debounceTime;
        counted++;
        if (input.events.isNotEmpty && input.events.first.$2 < 0) {
          negativeStart++;
        }
        final paired = pairEvents(input.events);
        for (var i = 0; i < paired.length; i++) {
          if (paired[i].$2 == paired[i].$1 ||
              (i > 0 && paired[i].$1 == paired[i - 1].$2)) {
            withZeroDuration++;
            break;
          }
        }

        // The case meets the REQ-TIMING-9 precondition.
        final m = k.ditLength < k.symbolGap ? k.ditLength : k.symbolGap;
        expect(d, inInclusiveRange(0, m));

        final events = <SwitchEvent>[
          for (final (isPress, t) in input.events)
            isPress ? SwitchEvent.press(t) : SwitchEvent.release(t),
        ];
        // REQ-EVENT-2: a Valid_Event_Sequence decodes without an error.
        final output = BatchDecoder(
          Calibration(
            ditLength: k.ditLength,
            dahLength: k.dahLength,
            symbolGap: k.symbolGap,
            letterGap: k.letterGap,
          ),
          TimingConfig(debounceTime: d, wordGapFactor: c.wordGapFactor),
        ).decode(events);

        // Render with explicit content, never DecodedItem.toString() (T12).
        final actual = <DecodedRecord>[
          for (final item in output)
            switch (item.kind) {
              DecodedItemKind.letter => (
                kind: 'letter',
                value: item.character!,
              ),
              DecodedItemKind.unknownLetter => (
                kind: 'unknownLetter',
                value: item.symbols!,
              ),
              DecodedItemKind.wordSpace => (kind: 'wordSpace', value: ''),
            },
        ];
        final expected = referenceDecode(input.events, k, d, c.wordGapFactor);
        final reason =
            'Calibration($k), d = $d, factor ${c.wordGapFactor}, '
            '${paired.length} Presses, actual $actual, expected $expected';

        // REQ-BATCH-1, REQ-BATCH-3: equals the reference decoder.
        expect(actual, equals(expected), reason: reason);

        // REQ-BATCH-4: empty, or starts and ends with a letter item, with no
        // two Word_Spaces in a row.
        if (actual.isEmpty) {
          empty++;
        } else {
          expect(actual.first.kind, isNot('wordSpace'), reason: reason);
          expect(actual.last.kind, isNot('wordSpace'), reason: reason);
        }
        for (var i = 1; i < actual.length; i++) {
          expect(
            actual[i].kind == 'wordSpace' && actual[i - 1].kind == 'wordSpace',
            isFalse,
            reason: reason,
          );
        }

        // REQ-BATCH-2, REQ-BATCH-3: letters are fixture characters; unknown
        // letters carry a non-empty Symbol sequence that is not a code.
        final codes = ituFixture.values.toSet();
        for (var i = 0; i < output.length; i++) {
          final item = output[i];
          switch (item.kind) {
            case DecodedItemKind.letter:
              expect(ituFixture, contains(item.character), reason: reason);
              expect(item.symbols, isNull);
            case DecodedItemKind.unknownLetter:
              expect(item.symbols, matches(RegExp(r'^[.\-]+$')));
              expect(codes, isNot(contains(item.symbols)), reason: reason);
              expect(item.character, isNull);
            case DecodedItemKind.wordSpace:
              expect(item.character, isNull);
              expect(item.symbols, isNull);
          }
        }

        if (actual.any((i) => i.kind == 'unknownLetter')) withUnknown++;
        if (actual.any((i) => i.kind == 'wordSpace')) withWordSpace++;
        // REQ-BATCH-3: decoding goes on after an unknown letter.
        final firstUnknown = actual.indexWhere(
          (i) => i.kind == 'unknownLetter',
        );
        if (firstUnknown >= 0 &&
            actual.skip(firstUnknown + 1).any((i) => i.kind == 'letter')) {
          unknownThenLetter++;
        }
      },
      maxExamples: 200,
      seed: 113003,
      onFalsify: report(113003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        expect(empty, greaterThan(0), reason: 'no empty output');
        expect(withUnknown, greaterThan(0), reason: 'no unknown letter');
        expect(withWordSpace, greaterThan(0), reason: 'no Word_Space');
        expect(
          unknownThenLetter,
          greaterThan(0),
          reason: 'no letter after an unknown letter',
        );
        expect(withZeroDuration, greaterThan(0), reason: 'no zero duration');
        expect(negativeStart, greaterThan(0), reason: 'no negative start');
      },
    );
  });

  // Feature: adaptive-timing, Property 14: Invalid sequences are rejected at the lowest index
  property('REQ-EVENT-3 REQ-EVENT-5 REQ-EVENT-6 invalid sequences are '
      'rejected at the lowest index', () {
    var counted = 0, stillValid = 0, multiEdit = 0;
    final rules = <String, int>{};
    final editKinds = <EventCorruption, int>{};
    forAll(
      corruptedInput(),
      (input) {
        final k = input.calibration;
        final c = input.config;
        final records = input.corrupted.events;
        counted++;
        if (input.corrupted.edits.length > 1) multiEdit++;
        for (final e in input.corrupted.edits) {
          editKinds[e.corruption] = (editKinds[e.corruption] ?? 0) + 1;
        }

        final events = <SwitchEvent>[
          for (final (isPress, t) in records)
            isPress ? SwitchEvent.press(t) : SwitchEvent.release(t),
        ];
        final before = List<SwitchEvent>.of(events);
        final decoder = BatchDecoder(
          Calibration(
            ditLength: k.ditLength,
            dahLength: k.dahLength,
            symbolGap: k.symbolGap,
            letterGap: k.letterGap,
          ),
          TimingConfig(
            debounceTime: c.debounceTime,
            wordGapFactor: c.wordGapFactor,
          ),
        );

        final expected = referenceValidate(records);
        TimingInputException? thrown;
        List<DecodedItem>? output;
        try {
          output = decoder.decode(events);
        } on TimingInputException catch (e) {
          thrown = e;
        }
        final reason =
            '${records.length} events after edits '
            '${[for (final e in input.corrupted.edits) e.corruption.name]}, '
            'expected $expected, actual ${thrown?.kind.name} at '
            '${thrown?.index}';

        if (expected == null) {
          // The edits happened to give a Valid_Event_Sequence: REQ-EVENT-2.
          stillValid++;
          expect(thrown, isNull, reason: reason);
          expect(output, isNotNull, reason: reason);
        } else {
          rules[expected.rule] = (rules[expected.rule] ?? 0) + 1;
          // REQ-EVENT-3: one error, lowest index, highest precedence there,
          // and no partial result.
          expect(thrown, isNotNull, reason: reason);
          expect(output, isNull, reason: reason);
          expect(thrown!.kind.name, equals(expected.rule), reason: reason);
          expect(thrown.index, equals(expected.index), reason: reason);
        }

        // REQ-EVENT-6: the caller's list is unchanged.
        expect(events, equals(before), reason: reason);
      },
      maxExamples: 200,
      seed: 114003,
      onFalsify: report(114003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        expect(multiEdit, greaterThan(0), reason: 'no case with several edits');
        for (final kind in EventCorruption.values) {
          expect(editKinds[kind] ?? 0, greaterThan(0), reason: 'no $kind');
        }
        for (final rule in const <String>[
          'timestampOutOfRange',
          'startsWithRelease',
          'twoPressesInARow',
          'twoReleasesInARow',
          'decreasingTimestamp',
          'endsWithPress',
        ]) {
          expect(rules[rule] ?? 0, greaterThan(0), reason: 'no $rule');
        }
        // A corruption that leaves the sequence valid is rare, never the
        // bulk of the cases.
        expect(stillValid, lessThan(counted ~/ 2));
      },
    );
  });

  // Feature: adaptive-timing, Property 15: Live decoding equals batch decoding
  property('REQ-LIVE-11 REQ-LIVE-3 REQ-LIVE-4 REQ-LIVE-7 REQ-LIVE-8 '
      'REQ-PBT-8 live decoding equals batch decoding', () {
    var counted = 0, withAdvance = 0, withWordSpace = 0, endsWithSpace = 0;
    var withPartial = 0, zeroD = 0, negativeStart = 0;
    forAll(
      liveScenario(),
      (s) {
        final k = s.calibration;
        final c = s.config;
        final d = c.debounceTime;
        counted++;
        if (s.advanceCount > 0) withAdvance++;
        if (d == 0) zeroD++;
        if (s.events.isNotEmpty && s.events.first.$2 < 0) negativeStart++;

        // The case meets the REQ-TIMING-9 precondition.
        final m = k.ditLength < k.symbolGap ? k.ditLength : k.symbolGap;
        expect(d, inInclusiveRange(0, m));

        final calibration = Calibration(
          ditLength: k.ditLength,
          dahLength: k.dahLength,
          symbolGap: k.symbolGap,
          letterGap: k.letterGap,
        );
        final config = TimingConfig(
          debounceTime: d,
          wordGapFactor: c.wordGapFactor,
        );
        final live = LiveDecoder(calibration, config);
        final batch = BatchDecoder(calibration, config).decode(<SwitchEvent>[
          for (final (isPress, t) in s.events)
            isPress ? SwitchEvent.press(t) : SwitchEvent.release(t),
        ]);

        // REQ-LIVE-11: the final advanceTo is the last release plus
        // max(d, Letter_Gap_Threshold).
        final calls = List<LiveCallRecord>.of(s.calls);
        final last = s.finalAdvance;
        if (last != null) {
          final lgt = live.classifier.letterGapThreshold;
          expect(last, equals(s.events.last.$2 + (d > lgt ? d : lgt)));
          calls.add((kind: LiveCallKind.advance, timestamp: last));
        }
        final trace = liveOracleTrace(calls, k, d, c.wordGapFactor);

        String render(List<DecodedItem> items) => <String>[
          for (final i in items)
            switch (i.kind) {
              DecodedItemKind.letter => i.character!,
              DecodedItemKind.unknownLetter => '?${i.symbols}',
              DecodedItemKind.wordSpace => '_',
            },
        ].join(' ');

        var previous = <DecodedItem>[];
        for (var i = 0; i < calls.length; i++) {
          final call = calls[i];
          switch (call.kind) {
            case LiveCallKind.press:
              live.press(call.timestamp);
            case LiveCallKind.release:
              live.release(call.timestamp);
            case LiveCallKind.advance:
              live.advanceTo(call.timestamp);
          }
          final current = List<DecodedItem>.of(live.items);
          final reason =
              'Calibration($k), d = $d, factor ${c.wordGapFactor}, after '
              'call $i of ${calls.length} (${call.kind.name} at '
              '${call.timestamp}): items [${render(current)}], partial '
              '"${live.partialSequence}", expected partial '
              '"${trace[i].partial}"';

          // REQ-LIVE-3: the pressed state follows the last press or release.
          expect(live.isPressed, equals(trace[i].pressed), reason: reason);
          if (call.kind != LiveCallKind.advance) {
            expect(
              live.isPressed,
              equals(call.kind == LiveCallKind.press),
              reason: reason,
            );
          }

          // REQ-LIVE-4: the Partial_Sequence holds exactly the confirmed
          // Symbols of the current letter.
          expect(
            live.partialSequence,
            equals(trace[i].partial),
            reason: reason,
          );
          if (live.partialSequence.isNotEmpty) withPartial++;

          // REQ-LIVE-8: earlier items are a prefix of the current items.
          expect(
            current.length,
            greaterThanOrEqualTo(previous.length),
            reason: reason,
          );
          expect(
            current.sublist(0, previous.length),
            equals(previous),
            reason: '$reason, before [${render(previous)}]',
          );

          // REQ-LIVE-7: a Word_Space is only appended with the first Symbol
          // of the next letter, so the items end with one only while that
          // letter is in the Partial_Sequence. Silence never adds one.
          if (current.isNotEmpty &&
              current.last.kind == DecodedItemKind.wordSpace) {
            endsWithSpace++;
            expect(live.partialSequence, isNotEmpty, reason: reason);
          }
          previous = current;
        }

        // REQ-LIVE-11: the final state equals the batch output, with an
        // empty Partial_Sequence.
        final reason =
            'Calibration($k), d = $d, factor ${c.wordGapFactor}, '
            '${s.events.length ~/ 2} Presses, ${s.advanceCount} advances: '
            'live [${render(live.items)}], batch [${render(batch)}]';
        expect(live.items, equals(batch), reason: reason);
        expect(live.partialSequence, isEmpty, reason: reason);
        expect(live.isPressed, isFalse, reason: reason);
        if (batch.any((i) => i.kind == DecodedItemKind.wordSpace)) {
          withWordSpace++;
        }
      },
      maxExamples: 200,
      seed: 115003,
      onFalsify: report(115003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        expect(withAdvance / counted, greaterThanOrEqualTo(0.10)); // REQ-PBT-8
        expect(withWordSpace, greaterThan(0), reason: 'no Word_Space');
        expect(
          endsWithSpace,
          greaterThan(0),
          reason: 'no state with a trailing Word_Space',
        );
        expect(withPartial, greaterThan(0), reason: 'no Partial_Sequence');
        expect(zeroD, greaterThan(0), reason: 'no d = 0 case');
        expect(negativeStart, greaterThan(0), reason: 'no negative start');
      },
    );
  });

  // Feature: adaptive-timing, Property 16: Invalid live calls change nothing
  property('REQ-LIVE-9 REQ-EVENT-5 invalid live calls change nothing', () {
    var counted = 0, continued = 0, midScenario = 0;
    final rules = <InvalidLiveRule, int>{};
    final kinds = <TimingInputErrorKind, int>{};
    final rangeCallKinds = <LiveCallKind>{};
    final decreasingCallKinds = <LiveCallKind>{};
    forAll(
      invalidLiveScenario(),
      (input) {
        final s = input.scenario;
        final k = s.calibration;
        final c = s.config;
        final invalid = input.invalid;
        counted++;
        rules[input.rule] = (rules[input.rule] ?? 0) + 1;

        final calibration = Calibration(
          ditLength: k.ditLength,
          dahLength: k.dahLength,
          symbolGap: k.symbolGap,
          letterGap: k.letterGap,
        );
        final config = TimingConfig(
          debounceTime: c.debounceTime,
          wordGapFactor: c.wordGapFactor,
        );
        final calls = <LiveCallRecord>[
          ...s.calls,
          if (s.finalAdvance != null)
            (kind: LiveCallKind.advance, timestamp: s.finalAdvance!),
        ];
        void apply(LiveDecoder decoder, LiveCallRecord call) {
          switch (call.kind) {
            case LiveCallKind.press:
              decoder.press(call.timestamp);
            case LiveCallKind.release:
              decoder.release(call.timestamp);
            case LiveCallKind.advance:
              decoder.advanceTo(call.timestamp);
          }
        }

        // The decoder under test and a reference that never sees the
        // invalid call, both fed the same valid prefix.
        final live = LiveDecoder(calibration, config);
        final reference = LiveDecoder(calibration, config);
        for (final call in calls.take(input.cut)) {
          apply(live, call);
          apply(reference, call);
        }
        if (input.cut > 0 && input.cut < calls.length) midScenario++;

        // The expected error, written from REQ-LIVE-9 and REQ-EVENT-5 with
        // the prefix state taken from the calls, not from the decoder.
        final st = livePrefixState(calls, input.cut);
        final t = invalid.timestamp;
        final TimingInputErrorKind expectedKind;
        if (t < SwitchEvent.minTimestamp || t > SwitchEvent.maxTimestamp) {
          expectedKind = TimingInputErrorKind.timestampOutOfRange;
          rangeCallKinds.add(invalid.kind);
        } else if (st.latest != null && t < st.latest!) {
          expectedKind = TimingInputErrorKind.decreasingTimestamp;
          decreasingCallKinds.add(invalid.kind);
        } else if (invalid.kind == LiveCallKind.press && st.pressed) {
          expectedKind = TimingInputErrorKind.twoPressesInARow;
        } else if (invalid.kind == LiveCallKind.release && !st.pressed) {
          expectedKind = st.eventCount == 0
              ? TimingInputErrorKind.startsWithRelease
              : TimingInputErrorKind.twoReleasesInARow;
        } else {
          fail('generated call ${invalid.kind.name} breaks no rule');
        }
        kinds[expectedKind] = (kinds[expectedKind] ?? 0) + 1;
        final expectedIndex = invalid.kind == LiveCallKind.advance
            ? null
            : st.eventCount;

        final itemsBefore = List<DecodedItem>.of(live.items);
        final partialBefore = live.partialSequence;
        final pressedBefore = live.isPressed;
        final latestBefore = live.latestTimestamp;
        final reason =
            'Calibration($k), d = ${c.debounceTime}, cut ${input.cut} of '
            '${calls.length}, ${input.rule.name}: ${invalid.kind.name} at $t';

        TimingInputException? thrown;
        try {
          apply(live, invalid);
        } on TimingInputException catch (e) {
          thrown = e;
        }
        expect(thrown, isNotNull, reason: reason);
        expect(thrown!.kind, equals(expectedKind), reason: reason);
        expect(thrown.index, equals(expectedIndex), reason: reason);

        // REQ-LIVE-9: every observable value is unchanged, and equal to the
        // reference decoder's.
        expect(live.items, equals(itemsBefore), reason: reason);
        expect(live.partialSequence, equals(partialBefore), reason: reason);
        expect(live.isPressed, equals(pressedBefore), reason: reason);
        expect(live.latestTimestamp, equals(latestBefore), reason: reason);
        expect(live.items, equals(reference.items), reason: reason);
        expect(
          live.partialSequence,
          equals(reference.partialSequence),
          reason: reason,
        );
        expect(live.isPressed, equals(reference.isPressed), reason: reason);
        expect(
          live.latestTimestamp,
          equals(reference.latestTimestamp),
          reason: reason,
        );

        // Continuing with the rest of the valid calls matches the reference
        // after every call, including the error index of later calls.
        for (var i = input.cut; i < calls.length; i++) {
          continued++;
          apply(live, calls[i]);
          apply(reference, calls[i]);
          final step = '$reason, then call $i (${calls[i].kind.name})';
          expect(live.items, equals(reference.items), reason: step);
          expect(
            live.partialSequence,
            equals(reference.partialSequence),
            reason: step,
          );
          expect(live.isPressed, equals(reference.isPressed), reason: step);
          expect(
            live.latestTimestamp,
            equals(reference.latestTimestamp),
            reason: step,
          );
        }
        if (calls.isNotEmpty) {
          // Both decoders also reject the same next invalid call alike, so
          // the hidden event count was not changed either.
          final probe = SwitchEvent.maxTimestamp + 1;
          final a = _errorOf(() => live.press(probe));
          final b = _errorOf(() => reference.press(probe));
          expect(a, equals(b), reason: reason);
        }
      },
      maxExamples: 200,
      seed: 116003,
      onFalsify: report(116003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        for (final rule in InvalidLiveRule.values) {
          expect(rules[rule] ?? 0, greaterThan(0), reason: 'no $rule');
        }
        for (final kind in const <TimingInputErrorKind>[
          TimingInputErrorKind.timestampOutOfRange,
          TimingInputErrorKind.decreasingTimestamp,
          TimingInputErrorKind.twoPressesInARow,
          TimingInputErrorKind.startsWithRelease,
          TimingInputErrorKind.twoReleasesInARow,
        ]) {
          expect(kinds[kind] ?? 0, greaterThan(0), reason: 'no $kind');
        }
        expect(rangeCallKinds, equals(LiveCallKind.values.toSet()));
        expect(decreasingCallKinds, equals(LiveCallKind.values.toSet()));
        expect(midScenario, greaterThan(0), reason: 'no mid-scenario cut');
        expect(continued, greaterThan(0), reason: 'no continuation');
      },
    );
  });

  // Feature: adaptive-timing, Property 17: Determinism
  property('REQ-ENGINE-2 two new instances given the same calls return '
      'equal results or the same error', () {
    var counted = 0;
    final seen = <String, int>{};
    void note(String key) => seen[key] = (seen[key] ?? 0) + 1;

    // Each instance gets its own argument objects, built from the same
    // plain values, so equality cannot come from shared state.
    Calibration calibrationOf(CalibrationRecord k) => Calibration(
      ditLength: k.ditLength,
      dahLength: k.dahLength,
      symbolGap: k.symbolGap,
      letterGap: k.letterGap,
    );
    List<SwitchEvent> eventsOf(List<EventRecord> records) => <SwitchEvent>[
      for (final (isPress, t) in records)
        isPress ? SwitchEvent.press(t) : SwitchEvent.release(t),
    ];

    /// Runs [call] and returns its result and its error (kind and index).
    (T?, (TimingInputErrorKind, int?)?) run<T>(T Function() call) {
      try {
        return (call(), null);
      } on TimingInputException catch (e) {
        return (null, (e.kind, e.index));
      }
    }

    void same<T>(
      (T?, (TimingInputErrorKind, int?)?) a,
      (T?, (TimingInputErrorKind, int?)?) b,
      String what,
    ) {
      expect(a.$2, equals(b.$2), reason: '$what: error');
      expect(a.$1, equals(b.$1), reason: '$what: result');
      note(a.$2 == null ? '$what ok' : '$what error');
    }

    forAll(
      determinismInput(),
      (input) {
        counted++;

        // Debouncer.
        final db = input.debounce;
        List<Press> pressesOf() => <Press>[
          for (final (a, b) in db.presses) Press(a, b),
        ];
        Debouncer debouncerOf() =>
            Debouncer(TimingConfig(debounceTime: db.debounceTime));
        final dA = run(() => _records(debouncerOf().debounce(pressesOf())));
        final dB = run(() => _records(debouncerOf().debounce(pressesOf())));
        same(dA, dB, 'Debouncer');
        expect(dA.$2 != null, equals(db.corrupted), reason: 'Debouncer');

        // Classifier: thresholds and both classifications, including the
        // negative-duration error.
        final (ck, factor, x) = input.classify;
        Classifier classifierOf() =>
            Classifier(calibrationOf(ck), TimingConfig(wordGapFactor: factor));
        final cA = classifierOf(), cB = classifierOf();
        expect(
          <int>[cA.pressThreshold, cA.letterGapThreshold, cA.wordGapThreshold],
          equals(<int>[
            cB.pressThreshold,
            cB.letterGapThreshold,
            cB.wordGapThreshold,
          ]),
          reason: 'Classifier thresholds',
        );
        same(
          run(() => cA.classifyPress(x)),
          run(() => cB.classifyPress(x)),
          'classifyPress',
        );
        same(
          run(() => cA.classifyGap(x)),
          run(() => cB.classifyGap(x)),
          'classifyGap',
        );

        // Calibrator: accepted or rejected alike. It never throws.
        final cal = input.calibrate;
        TimingConfig configOf(ConfigInput c) => TimingConfig(
          debounceTime: c.debounceTime,
          wordGapFactor: c.wordGapFactor,
        );
        CalibrationResult calibrateOnce() =>
            Calibrator(configOf(cal.config))
                .calibrate(eventsOf(cal.keying.events), word: cal.word);
        final rA = calibrateOnce(), rB = calibrateOnce();
        expect(rA.calibration, equals(rB.calibration), reason: 'Calibrator');
        expect(
          rA.rejection?.reason,
          equals(rB.rejection?.reason),
          reason: 'Calibrator reason',
        );
        expect(
          rA.rejection?.message,
          equals(rB.rejection?.message),
          reason: 'Calibrator message',
        );
        note(rA.isAccepted ? 'Calibrator accepted' : 'Calibrator rejected');

        // Decoder construction: the Property 5 Debounce_Time may exceed the
        // REQ-TIMING-9 limit, so both constructors may throw.
        same(
          run(() {
            BatchDecoder(calibrationOf(cal.calibration), configOf(cal.config));
            return true;
          }),
          run(() {
            BatchDecoder(calibrationOf(cal.calibration), configOf(cal.config));
            return true;
          }),
          'BatchDecoder constructor',
        );
        same(
          run(() {
            LiveDecoder(calibrationOf(cal.calibration), configOf(cal.config));
            return true;
          }),
          run(() {
            LiveDecoder(calibrationOf(cal.calibration), configOf(cal.config));
            return true;
          }),
          'LiveDecoder constructor',
        );

        // Batch_Decoder: the valid original and the corrupted events.
        final b = input.batch;
        BatchDecoder batchOf() =>
            BatchDecoder(calibrationOf(b.calibration), configOf(b.config));
        for (final records in <List<EventRecord>>[
          b.original,
          b.corrupted.events,
        ]) {
          same(
            run(() => batchOf().decode(eventsOf(records))),
            run(() => batchOf().decode(eventsOf(records))),
            'BatchDecoder',
          );
        }

        // Live_Decoder: the valid calls with one invalid call at the cut,
        // compared after every call, including the later valid calls.
        final l = input.live;
        final s = l.scenario;
        final calls = <LiveCallRecord>[
          ...s.calls,
          if (s.finalAdvance != null)
            (kind: LiveCallKind.advance, timestamp: s.finalAdvance!),
        ];
        final sequence = <LiveCallRecord>[
          ...calls.take(l.cut),
          l.invalid,
          ...calls.skip(l.cut),
        ];
        LiveDecoder liveOf() =>
            LiveDecoder(calibrationOf(s.calibration), configOf(s.config));
        final lA = liveOf(), lB = liveOf();
        void apply(LiveDecoder decoder, LiveCallRecord call) {
          switch (call.kind) {
            case LiveCallKind.press:
              decoder.press(call.timestamp);
            case LiveCallKind.release:
              decoder.release(call.timestamp);
            case LiveCallKind.advance:
              decoder.advanceTo(call.timestamp);
          }
        }

        for (var i = 0; i < sequence.length; i++) {
          final call = sequence[i];
          final what = 'LiveDecoder call $i (${call.kind.name})';
          same(
            run(() {
              apply(lA, call);
              return true;
            }),
            run(() {
              apply(lB, call);
              return true;
            }),
            'LiveDecoder',
          );
          expect(lA.items, equals(lB.items), reason: what);
          expect(lA.partialSequence, equals(lB.partialSequence), reason: what);
          expect(lA.isPressed, equals(lB.isPressed), reason: what);
          expect(lA.latestTimestamp, equals(lB.latestTimestamp), reason: what);
        }
      },
      maxExamples: 200,
      seed: 117003,
      onFalsify: report(117003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        // Every component is reached with both outcomes.
        for (final key in const <String>[
          'Debouncer ok',
          'Debouncer error',
          'classifyPress ok',
          'classifyPress error',
          'classifyGap ok',
          'classifyGap error',
          'Calibrator accepted',
          'Calibrator rejected',
          'BatchDecoder constructor ok',
          'BatchDecoder constructor error',
          'LiveDecoder constructor ok',
          'LiveDecoder constructor error',
          'BatchDecoder ok',
          'BatchDecoder error',
          'LiveDecoder ok',
          'LiveDecoder error',
        ]) {
          expect(seen[key] ?? 0, greaterThan(0), reason: 'no "$key" case');
        }
      },
    );
  });

  // Feature: adaptive-timing, Property 18: Messages leak no input
  property('REQ-ENGINE-5 REQ-EVENT-4 REQ-CAL-13 messages and toString leak '
      'no input', () {
    var counted = 0, batchErrors = 0, liveErrors = 0, liveNoIndex = 0;
    var constructorErrors = 0, items = 0;
    final reasons = <RejectionReason, int>{};
    // The text frame first seen per error kind or Rejection_Reason and rule.
    final frames = <String, String>{};

    Calibration calibrationOf(CalibrationRecord k) => Calibration(
      ditLength: k.ditLength,
      dahLength: k.dahLength,
      symbolGap: k.symbolGap,
      letterGap: k.letterGap,
    );
    TimingConfig configOf(ConfigInput c) => TimingConfig(
      debounceTime: c.debounceTime,
      wordGapFactor: c.wordGapFactor,
    );
    List<SwitchEvent> eventsOf(List<EventRecord> records) => <SwitchEvent>[
      for (final (isPress, t) in records)
        isPress ? SwitchEvent.press(t) : SwitchEvent.release(t),
    ];
    void apply(LiveDecoder decoder, LiveCallRecord call) {
      switch (call.kind) {
        case LiveCallKind.press:
          decoder.press(call.timestamp);
        case LiveCallKind.release:
          decoder.release(call.timestamp);
        case LiveCallKind.advance:
          decoder.advanceTo(call.timestamp);
      }
    }

    // REQ-ENGINE-5: every in-range timestamp is at least 1,000,000, so it
    // differs from every event index and Press count.
    void expectShifted(List<int> timestamps, String reason) {
      for (final t in timestamps) {
        if (t >= SwitchEvent.minTimestamp && t <= SwitchEvent.maxTimestamp) {
          expect(
            t,
            greaterThanOrEqualTo(privacyTimestampFloor),
            reason: reason,
          );
        }
      }
    }

    // REQ-EVENT-4, REQ-ENGINE-5: the kind's phrase, the index only where
    // one is involved, and nothing taken from the input.
    void expectErrorPrivate(
      TimingInputException e,
      List<int> timestamps,
      String reason,
    ) {
      final index = e.index;
      if (index != null) {
        expect(index, lessThan(privacyTimestampFloor), reason: reason);
      }
      for (final text in <String>[e.message, e.toString()]) {
        _expectPrivate(
          text,
          key: 'error ${e.kind.name} ${index == null ? 'no index' : 'index'}',
          phrase: e.kind.phrase,
          allowedNumbers: index == null ? const <int>[] : <int>[index],
          timestamps: timestamps,
          frames: frames,
          reason: reason,
        );
      }
    }

    forAll(
      privacyInput(),
      (input) {
        counted++;

        // Calibrator: every Calibration_Rejection. REQ-CAL-13.
        final cal = input.calibrate;
        final calRecords = cal.keying.events;
        final calTimes = <int>[for (final (_, t) in calRecords) t];
        final calReason =
            'Calibrator: word "${cal.word}", '
            'perturbation ${cal.keying.perturbation.name}, '
            'd = ${cal.config.debounceTime}';
        expectShifted(calTimes, calReason);
        final result = Calibrator(configOf(cal.config))
            .calibrate(eventsOf(calRecords), word: cal.word);
        final expected = referenceCalibrate(
          cal.word,
          calRecords,
          cal.config.debounceTime,
        );
        final rejection = result.rejection;
        expect(
          rejection?.reason.name,
          equals(expected.reason),
          reason: calReason,
        );
        if (rejection != null) {
          reasons[rejection.reason] = (reasons[rejection.reason] ?? 0) + 1;
          final wordRule = referenceWordRule(cal.word);
          final (allowed, phrase, rule) = switch (rejection.reason) {
            RejectionReason.unsuitableWord => (
              wordRule == 'tooLong'
                  ? const <int>[_maxCalibrationWordLength]
                  : const <int>[],
              null,
              wordRule!,
            ),
            RejectionReason.invalidEvents => (
              <int>[expected.eventIndex!],
              TimingInputErrorKind.values.byName(expected.eventRule!).phrase,
              expected.eventRule!,
            ),
            RejectionReason.wrongPressCount => (
              <int>[expected.expectedPresses!, expected.receivedPresses!],
              null,
              '',
            ),
            _ => (const <int>[], null, ''),
          };
          for (final text in <String>[rejection.message, '$rejection']) {
            _expectPrivate(
              text,
              key: 'rejection ${rejection.reason.name} $rule',
              phrase: phrase,
              allowedNumbers: allowed,
              timestamps: calTimes,
              frames: frames,
              reason: calReason,
            );
          }
        }

        // Decoder constructors: the Property 5 Debounce_Time may exceed the
        // REQ-TIMING-9 limit. REQ-EVENT-4.
        for (final build in <void Function()>[
          () => BatchDecoder(
            calibrationOf(cal.calibration),
            configOf(cal.config),
          ),
          () =>
              LiveDecoder(calibrationOf(cal.calibration), configOf(cal.config)),
        ]) {
          try {
            build();
          } on TimingInputException catch (e) {
            constructorErrors++;
            expectErrorPrivate(e, calTimes, 'decoder constructor');
          }
        }

        // Batch_Decoder: the decoded items of the valid original, and the
        // error for the corrupted events. REQ-EVENT-3, REQ-EVENT-4.
        final b = input.batch;
        final batchTimes = <int>[
          for (final (_, t) in b.original) t,
          for (final (_, t) in b.corrupted.events) t,
        ];
        final batchReason =
            'BatchDecoder: Calibration(${b.calibration}), '
            'd = ${b.config.debounceTime}, edits '
            '${[for (final e in b.corrupted.edits) e.corruption.name]}';
        expectShifted(batchTimes, batchReason);
        final decoder = BatchDecoder(
          calibrationOf(b.calibration),
          configOf(b.config),
        );
        for (final item in decoder.decode(eventsOf(b.original))) {
          items++;
          _expectItemPrivate(item, batchReason);
        }
        final violation = referenceValidate(b.corrupted.events);
        TimingInputException? batchError;
        try {
          decoder.decode(eventsOf(b.corrupted.events));
        } on TimingInputException catch (e) {
          batchError = e;
        }
        expect(batchError?.kind.name, equals(violation?.rule));
        expect(batchError?.index, equals(violation?.index));
        if (batchError != null) {
          batchErrors++;
          expectErrorPrivate(batchError, batchTimes, batchReason);
        }

        // Live_Decoder: the items after the valid prefix, and the error for
        // the invalid call. REQ-LIVE-9, REQ-EVENT-4, T9.
        final l = input.live;
        final liveTimes = <int>[
          for (final c in l.prefix) c.timestamp,
          l.invalid.timestamp,
        ];
        final liveReason =
            'LiveDecoder: Calibration(${l.calibration}), '
            'd = ${l.config.debounceTime}, ${l.prefix.length} calls, then '
            '${l.rule.name}: ${l.invalid.kind.name}';
        expectShifted(liveTimes, liveReason);
        final live = LiveDecoder(
          calibrationOf(l.calibration),
          configOf(l.config),
        );
        for (final call in l.prefix) {
          apply(live, call);
        }
        for (final item in live.items) {
          items++;
          _expectItemPrivate(item, liveReason);
        }
        TimingInputException? liveError;
        try {
          apply(live, l.invalid);
        } on TimingInputException catch (e) {
          liveError = e;
        }
        expect(liveError, isNotNull, reason: liveReason);
        liveErrors++;
        expect(
          liveError!.index == null,
          equals(l.invalid.kind == LiveCallKind.advance),
          reason: liveReason,
        );
        if (liveError.index == null) liveNoIndex++;
        expectErrorPrivate(liveError, liveTimes, liveReason);
      },
      maxExamples: 200,
      seed: 118003,
      onFalsify: report(118003),
      tearDownAll: () {
        expect(counted, greaterThanOrEqualTo(100)); // REQ-PBT-1
        // Every source of messages is reached.
        for (final r in RejectionReason.values) {
          expect(reasons[r] ?? 0, greaterThan(0), reason: 'no $r rejection');
        }
        expect(batchErrors, greaterThan(0), reason: 'no batch error');
        expect(liveErrors, greaterThan(liveNoIndex), reason: 'no indexed');
        expect(liveNoIndex, greaterThan(0), reason: 'no advanceTo error');
        expect(constructorErrors, greaterThan(0), reason: 'no constructor');
        expect(items, greaterThan(0), reason: 'no decoded item');
      },
    );
  });

  // Feature: adaptive-timing, Property 19: Config and Calibration validation
  property('REQ-DEBOUNCE-1 REQ-DEBOUNCE-3 REQ-CAL-14 config and Calibration '
      'validation', () {
    var validConfigs = 0, invalidConfigs = 0;
    var validCalibrations = 0, invalidCalibrations = 0;
    forAll(
      validationInput(),
      (input) {
        final (c, k) = input;

        // Timing_Config: succeeds exactly when REQ-DEBOUNCE-3 allows it.
        final expectedConfig = _expectedConfigError(c);
        TimingConfig? config;
        final configKind = _errorKindOf(() {
          config = TimingConfig(
            debounceTime: c.debounceTime,
            wordGapFactor: c.wordGapFactor,
          );
        });
        expect(
          configKind,
          equals(expectedConfig),
          reason:
              'TimingConfig(debounceTime: ${c.debounceTime}, '
              'wordGapFactor: ${c.wordGapFactor})',
        );
        if (expectedConfig == null) {
          validConfigs++;
          // REQ-DEBOUNCE-1: supplied values read back exactly.
          expect(config!.debounceTime, equals(c.debounceTime));
          expect(config!.wordGapFactor, equals(c.wordGapFactor));
        } else {
          invalidConfigs++;
          expect(config, isNull);
        }

        // Calibration: succeeds exactly when REQ-CAL-14 allows it.
        final expectedCalibration = _expectedCalibrationError(k);
        Calibration? calibration;
        final calibrationKind = _errorKindOf(() {
          calibration = Calibration(
            ditLength: k.ditLength,
            dahLength: k.dahLength,
            symbolGap: k.symbolGap,
            letterGap: k.letterGap,
          );
        });
        expect(
          calibrationKind,
          equals(expectedCalibration),
          reason: 'Calibration($k)',
        );
        if (expectedCalibration == null) {
          validCalibrations++;
          expect(calibration!.ditLength, equals(k.ditLength));
          expect(calibration!.dahLength, equals(k.dahLength));
          expect(calibration!.symbolGap, equals(k.symbolGap));
          expect(calibration!.letterGap, equals(k.letterGap));
        } else {
          invalidCalibrations++;
          expect(calibration, isNull);
        }
      },
      maxExamples: 200,
      seed: 119003,
      onFalsify: report(119003),
      tearDownAll: () {
        // The generator must reach both outcomes for both types.
        expect(validConfigs, greaterThan(0), reason: 'no valid config');
        expect(invalidConfigs, greaterThan(0), reason: 'no invalid config');
        expect(
          validCalibrations,
          greaterThan(0),
          reason: 'no valid Calibration',
        );
        expect(
          invalidCalibrations,
          greaterThan(0),
          reason: 'no invalid Calibration',
        );
      },
    );
  });
}
