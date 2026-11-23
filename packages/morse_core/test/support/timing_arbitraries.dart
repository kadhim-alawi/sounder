/// kiri_check generators for the adaptive-timing property tests.
///
/// This file does not import `package:morse_core`. Every generator returns
/// plain records of `int`s, `double`s and `String`s, and the test bodies build
/// the engine's values from them, so a bug in the engine cannot shape its own
/// inputs.
///
/// Preconditions are built into the generators (generate to satisfy); no
/// generator uses `.filter`, so every generated case counts. REQ-PBT-1,
/// REQ-PBT-8.
library;

import 'package:kiri_check/kiri_check.dart';

import 'itu_fixture.dart';
import 'timing_oracles.dart';

/// 2^40 Microseconds, the largest valid Calibration value. REQ-CAL-14.
const int maxCalibrationValue = 1099511627776;

/// The largest valid Word_Gap_Factor. REQ-DEBOUNCE-3.
const double maxWordGapFactor = 1000.0;

/// The double just above 1.0 (1 + 2^-52). REQ-DEBOUNCE-3.
final double justAboveOne = 1.0 + 1.0 / (1 << 52);

/// The double just below 1.0 (1 − 2^-53). REQ-DEBOUNCE-3.
final double justBelowOne = 1.0 - 1.0 / (1 << 53);

/// The double just above 1,000 (1000 + 2^-43). REQ-DEBOUNCE-3.
final double justAboveMaxFactor = maxWordGapFactor + 1.0 / (1 << 43);

/// The double just below 1,000 (1000 − 2^-43). REQ-DEBOUNCE-3.
final double justBelowMaxFactor = maxWordGapFactor - 1.0 / (1 << 43);

/// Raw Timing_Config inputs: a Debounce_Time and a Word_Gap_Factor.
typedef ConfigInput = ({int debounceTime, double wordGapFactor});

/// Raw Calibration inputs: four integers, any of which may be invalid.
typedef CalibrationInput = ({
  int ditLength,
  int dahLength,
  int symbolGap,
  int letterGap,
});

/// A Debounce_Time from −10,000,000 to 10,000,000, weighted towards the
/// boundary at 0 and the default 30,000. Negative values are common.
/// REQ-DEBOUNCE-1, REQ-DEBOUNCE-3.
Arbitrary<int> anyDebounceTime() => frequency(<(int, Arbitrary<dynamic>)>[
  (2, constantFrom<int>(const <int>[-1, 0, 1, 30000, -30000])),
  (3, integer(min: -10000000, max: -1)),
  (5, integer(min: 0, max: 10000000)),
]).cast<int>();

/// A Word_Gap_Factor that may be invalid: NaN, ±infinity, 1.0, the doubles
/// next to 1.0 and to 1,000, other fixed boundary values, and arbitrary
/// doubles from −10 to 2,000. REQ-DEBOUNCE-1, REQ-DEBOUNCE-3.
Arbitrary<double> anyWordGapFactor() => frequency(<(int, Arbitrary<dynamic>)>[
  (
    4,
    constantFrom<double>(<double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
      1.0,
      justAboveOne,
      justBelowOne,
      maxWordGapFactor,
      justAboveMaxFactor,
      justBelowMaxFactor,
      0.0,
      -1.0,
      1.5,
      2.0,
      2.5,
    ]),
  ),
  (3, float(min: 1.0, max: 1000.0, minExcluded: true)),
  (3, float(min: -10.0, max: 2000.0)),
]).cast<double>();

/// One Timing_Config input. REQ-DEBOUNCE-1, REQ-DEBOUNCE-3.
Arbitrary<ConfigInput> configInput() => combine2<int, double>(
  anyDebounceTime(),
  anyWordGapFactor(),
).map((r) => (debounceTime: r.$1, wordGapFactor: r.$2));

/// One Calibration value that may be invalid, weighted towards 0 and 2^40
/// and their neighbours. REQ-CAL-14.
Arbitrary<int> _calibrationValue() => frequency(<(int, Arbitrary<dynamic>)>[
  (
    2,
    constantFrom<int>(const <int>[
      -1,
      0,
      1,
      2,
      maxCalibrationValue - 1,
      maxCalibrationValue,
      maxCalibrationValue + 1,
    ]),
  ),
  (2, integer(min: -10, max: 10)),
  (2, integer(min: maxCalibrationValue - 10, max: maxCalibrationValue + 10)),
  (4, integer(min: 1, max: 10000000)),
]).cast<int>();

/// An offset added to the previous value, so `dah ≤ dit` and
/// `letterGap ≤ symbolGap` cases sit at the boundary often, and valid
/// orderings are common.
Arbitrary<int> _offset() => frequency(<(int, Arbitrary<dynamic>)>[
  (2, constantFrom<int>(const <int>[-1, 0, 1])),
  (1, integer(min: -1000, max: -1)),
  (5, integer(min: 1, max: 10000000)),
]).cast<int>();

/// Dah_Length or Letter_Gap: either a value of its own, or [base] plus an
/// offset.
int _second(int base, int own, int offset, bool relative) =>
    relative ? base + offset : own;

/// Four Calibration integers covering every REQ-CAL-14 rule: values around 0
/// and 2^40, Dah_Length at or below Dit_Length, Letter_Gap at or below
/// Symbol_Gap, and valid Calibrations. REQ-CAL-14.
Arbitrary<CalibrationInput> calibrationInput() =>
    combine8<int, int, int, bool, int, int, int, bool>(
      _calibrationValue(),
      _calibrationValue(),
      _offset(),
      frequency(<(int, Arbitrary<dynamic>)>[
        (3, constant(true)),
        (1, constant(false)),
      ]).cast<bool>(),
      _calibrationValue(),
      _calibrationValue(),
      _offset(),
      frequency(<(int, Arbitrary<dynamic>)>[
        (3, constant(true)),
        (1, constant(false)),
      ]).cast<bool>(),
    ).map(
      (r) => (
        ditLength: r.$1,
        dahLength: _second(r.$1, r.$2, r.$3, r.$4),
        symbolGap: r.$5,
        letterGap: _second(r.$5, r.$6, r.$7, r.$8),
      ),
    );

/// One Property 19 case: a Timing_Config input and a Calibration input.
/// REQ-DEBOUNCE-1, REQ-DEBOUNCE-3, REQ-CAL-14.
Arbitrary<(ConfigInput, CalibrationInput)> validationInput() =>
    combine2<ConfigInput, CalibrationInput>(configInput(), calibrationInput());

/// 2^52, the largest accepted timestamp magnitude. REQ-EVENT-1.
const int maxTimestampMagnitude = 4503599627370496;

/// One Property 1 and 2 case: a Debounce_Time [debounceTime] and a time
/// ordered list of Presses as `(pressedAt, releasedAt)` records.
/// REQ-DEBOUNCE-7.
typedef PressListCase = ({int debounceTime, List<(int, int)> presses});

/// A duration from 0 to [max], with one draw in four from 0 to [d], so
/// durations shorter than the Debounce_Time are common. REQ-PBT-8.
Arbitrary<int> _durationWithShort(int d, int max) =>
    frequency(<(int, Arbitrary<dynamic>)>[
      (1, integer(min: 0, max: d)),
      (3, integer(min: 0, max: max)),
    ]).cast<int>();

/// A Debounce_Time from 0 to 100,000, with 0 and 100,000 drawn often.
/// REQ-DEBOUNCE-7, REQ-DEBOUNCE-10.
Arbitrary<int> _debounceTime() => frequency(<(int, Arbitrary<dynamic>)>[
  (1, constant(0)),
  (1, constant(100000)),
  (6, integer(min: 0, max: 100000)),
]).cast<int>();

/// The Property 1 and 2 generator: a Debounce_Time `d` from 0 to 100,000 and
/// 0 to [maxLength] time-ordered Presses whose Press and Gap durations run
/// from 0 to [maxDuration], one in four drawn from 0 to `d`. The first press
/// timestamp ranges over negative and positive values and leaves room for
/// the whole list below 2^52. REQ-DEBOUNCE-7, REQ-PBT-8.
Arbitrary<PressListCase> pressList({
  int maxLength = 50,
  int maxDuration = 2000000,
}) => _debounceTime().flatMap(
  (d) =>
      combine2<int, List<(int, int)>>(
        integer(
          min: -maxTimestampMagnitude,
          max: maxTimestampMagnitude - 2 * maxLength * maxDuration,
        ),
        list<(int, int)>(
          combine2<int, int>(
            _durationWithShort(d, maxDuration),
            _durationWithShort(d, maxDuration),
          ),
          maxLength: maxLength,
        ),
      ).map((r) {
        // Each pair is (Gap before this Press, Press duration); the Gap of
        // the first pair is unused.
        var t = r.$1;
        final presses = <(int, int)>[];
        for (var i = 0; i < r.$2.length; i++) {
          final (gap, duration) = r.$2[i];
          if (i > 0) t += gap;
          presses.add((t, t + duration));
          t += duration;
        }
        return (debounceTime: d, presses: presses);
      }),
);

/// Whether [c] has a Press or a Gap shorter than its Debounce_Time.
/// REQ-PBT-8.
bool hasShortDuration(PressListCase c) {
  final p = c.presses;
  final d = c.debounceTime;
  for (var i = 0; i < p.length; i++) {
    if (p[i].$2 - p[i].$1 < d) return true;
    if (i > 0 && p[i].$1 - p[i - 1].$2 < d) return true;
  }
  return false;
}

/// A whole number from [min] to [max], with [min], [max] and their inner
/// neighbours drawn often. Requires `min < max`.
Arbitrary<int> _valueWithEdges(int min, int max) =>
    frequency(<(int, Arbitrary<dynamic>)>[
      (1, constantFrom<int>(<int>[min, min + 1, max - 1, max])),
      (1, integer(min: min, max: min + 10 < max ? min + 10 : max)),
      (1, integer(min: max - 10 > min ? max - 10 : min, max: max)),
      (5, integer(min: min, max: max)),
    ]).cast<int>();

/// An amount by which Dah_Length exceeds Dit_Length, or Letter_Gap exceeds
/// Symbol_Gap: at least 1, with 1 and 2 drawn often.
Arbitrary<int> _positiveStep(int max) => frequency(<(int, Arbitrary<dynamic>)>[
  (2, constantFrom<int>(const <int>[1, 2])),
  (1, integer(min: 1, max: 1000)),
  (5, integer(min: 1, max: max)),
]).cast<int>();

/// The larger value of an ordered pair: [base] plus [step], kept at or below
/// [max]. Since `base < max`, the result is always greater than [base].
int _above(int base, int step, int max) =>
    max - base < step ? max : base + step;

/// One ordered pair `(a, b)` with `min ≤ a < b ≤ max`, built without a
/// filter.
Arbitrary<(int, int)> _orderedPair(int min, int max) => combine2<int, int>(
  _valueWithEdges(min, max - 1),
  _positiveStep(max - min),
).map((r) => (r.$1, _above(r.$1, r.$2, max)));

/// A valid Calibration as plain integers: every value from [min] to [max]
/// (default 1 to 10,000,000), Dah_Length > Dit_Length and Letter_Gap >
/// Symbol_Gap. Values at [min], [max] and their neighbours, and adjacent
/// pairs, are drawn often. [max] must not exceed 2^40 and [min] must be at
/// least 1. REQ-CAL-14, REQ-TIMING-1, REQ-TIMING-2.
Arbitrary<CalibrationInput> calibrationValues({
  int min = 1,
  int max = 10000000,
}) =>
    combine2<(int, int), (int, int)>(
      _orderedPair(min, max),
      _orderedPair(min, max),
    ).map(
      (r) => (
        ditLength: r.$1.$1,
        dahLength: r.$1.$2,
        symbolGap: r.$2.$1,
        letterGap: r.$2.$2,
      ),
    );

/// A valid Word_Gap_Factor: finite, greater than 1.0 and at most 1,000.
/// Draws the double just above 1.0, the double just below 1,000, 1,000
/// itself, multiples of 0.25 from 1.25 to 8.0, other fixed values, and
/// arbitrary doubles in range. REQ-DEBOUNCE-3, REQ-TIMING-1.
Arbitrary<double> wordGapFactor() => frequency(<(int, Arbitrary<dynamic>)>[
  (
    2,
    constantFrom<double>(<double>[
      justAboveOne,
      1.25,
      1.5,
      2.0,
      2.5,
      7.75,
      8.0,
      justBelowMaxFactor,
      maxWordGapFactor,
    ]),
  ),
  (2, integer(min: 5, max: 32).map((n) => n / 4)),
  (4, float(min: 1.0, max: maxWordGapFactor, minExcluded: true)),
  (2, float(min: 1.0, max: 3.0, minExcluded: true)),
]).cast<double>();

/// One Property 6 case: a valid Calibration, drawn either from 1 to
/// 10,000,000 or from the whole range up to 2^40, and a valid
/// Word_Gap_Factor. REQ-TIMING-1, REQ-TIMING-2.
Arbitrary<(CalibrationInput, double)> thresholdInput() =>
    combine2<CalibrationInput, double>(
      frequency(<(int, Arbitrary<dynamic>)>[
        (1, calibrationValues()),
        (1, calibrationValues(max: maxCalibrationValue)),
      ]).cast<CalibrationInput>(),
      wordGapFactor(),
    );

/// A non-negative duration near the threshold [t]: `t − 1`, `t` and `t + 1`
/// often, values within 10 of [t], 0, and any value from 0 to `10·t`.
/// Requires `t ≥ 1`. REQ-TIMING-3, REQ-TIMING-4, REQ-PBT-6.
Arbitrary<int> durationNear(int t) => frequency(<(int, Arbitrary<dynamic>)>[
  (3, constantFrom<int>(<int>[t - 1, t, t + 1])),
  (2, integer(min: t > 10 ? t - 10 : 0, max: t + 10)),
  (1, constant(0)),
  (3, integer(min: 0, max: 10 * t)),
]).cast<int>();

/// A negative duration: −1 often, otherwise any value from −[max] to −1.
/// REQ-TIMING-11.
Arbitrary<int> negativeDuration({int max = 10000000}) =>
    frequency(<(int, Arbitrary<dynamic>)>[
      (1, constant(-1)),
      (2, integer(min: -max, max: -1)),
    ]).cast<int>();

/// One Property 7 case: a valid Calibration, a valid Word_Gap_Factor and a
/// duration. The duration is drawn near one of the three thresholds (from
/// [exactThresholds]), from 0 to 10 × Word_Gap_Threshold, or negative.
/// REQ-TIMING-3, REQ-TIMING-4, REQ-TIMING-11.
Arbitrary<(CalibrationInput, double, int)> classificationInput() =>
    thresholdInput().flatMap((input) {
      final (k, factor) = input;
      final t = exactThresholds(k, factor);
      return frequency(<(int, Arbitrary<dynamic>)>[
        (3, durationNear(t.pressThreshold)),
        (3, durationNear(t.letterGapThreshold)),
        (3, durationNear(t.wordGapThreshold)),
        (1, negativeDuration(max: 10 * t.wordGapThreshold)),
      ]).cast<int>().map((x) => (k, factor, x));
    });

/// One Well_Separated_Calibration case as plain values: a valid Calibration
/// with Dah_Length ≥ 2 × Dit_Length and Letter_Gap ≥ 2 × Symbol_Gap, a
/// Word_Gap_Factor from 1.5 to 8, and a Debounce_Time at most half the
/// smaller of Dit_Length and Symbol_Gap. REQ-TIMING-7, REQ-TIMING-8.
typedef WellSeparatedInput = ({
  CalibrationInput calibration,
  double wordGapFactor,
  int debounceTime,
});

/// A pair `(base, 2·base + extra)` with `min ≤ base`, `extra ≥ 0` and the
/// second value at most [max]. `extra` is 0 or 1 often, so the 2× boundary
/// is reached. Requires `min < max ~/ 2`.
Arbitrary<(int, int)> _doubledPair(int min, int max) =>
    _valueWithEdges(min, max ~/ 2).flatMap((base) {
      final room = max - 2 * base;
      final extra = room == 0
          ? constant(0)
          : frequency(<(int, Arbitrary<dynamic>)>[
              (2, constantFrom<int>(const <int>[0, 1])),
              (5, integer(min: 0, max: room)),
            ]).cast<int>();
      return extra.map((e) => (base, 2 * base + e));
    });

/// A Word_Gap_Factor from 1.5 to 8 inclusive, with 1.5, 2.0 and 8.0 drawn
/// often. REQ-TIMING-7, REQ-TIMING-8.
Arbitrary<double> _wellSeparatedFactor() =>
    frequency(<(int, Arbitrary<dynamic>)>[
      (1, constantFrom<double>(const <double>[1.5, 2.0, 8.0])),
      (4, float(min: 1.5, max: 8.0)),
    ]).cast<double>();

/// A Well_Separated_Calibration, built to satisfy the definition rather than
/// filtered: `dah = 2·dit + extra`, `lg = 2·sg + extra`, every value from
/// [min] to [max] (default 1 to 10,000,000, never above 2^40), factor from
/// 1.5 to 8, and `d` from 0 to `min(dit, sg) ~/ 2` with both ends drawn
/// often. Requires `1 ≤ min < max ~/ 2` and `max ≤ 2^40`.
/// REQ-TIMING-7, REQ-TIMING-8, REQ-CAL-14.
Arbitrary<WellSeparatedInput> wellSeparated({
  int min = 1,
  int max = 10000000,
}) =>
    combine3<(int, int), (int, int), double>(
      _doubledPair(min, max),
      _doubledPair(min, max),
      _wellSeparatedFactor(),
    ).flatMap((r) {
      final calibration = (
        ditLength: r.$1.$1,
        dahLength: r.$1.$2,
        symbolGap: r.$2.$1,
        letterGap: r.$2.$2,
      );
      final smaller = r.$1.$1 < r.$2.$1 ? r.$1.$1 : r.$2.$1;
      final m = smaller ~/ 2;
      final d = m == 0
          ? constant(0)
          : frequency(<(int, Arbitrary<dynamic>)>[
              (1, constant(0)),
              (1, constant(m)),
              (6, integer(min: 0, max: m)),
            ]).cast<int>();
      return d.map(
        (debounceTime) => (
          calibration: calibration,
          wordGapFactor: r.$3,
          debounceTime: debounceTime,
        ),
      );
    });

/// The jitter bands of [jitterDuration]. Each band is a range of whole-µs
/// durations whose class REQ-TIMING-7 or REQ-TIMING-8 fixes.
enum JitterBand {
  /// Press durations `x` with `5x ≤ 6 × Dit_Length`: always dit.
  /// REQ-TIMING-7.
  dit,

  /// Press durations `x` with `5x ≥ 4 × Dah_Length`, up to 10 × Dah_Length:
  /// always dah. REQ-TIMING-7.
  dah,

  /// Gap durations `x` with `5x ≤ 6 × Symbol_Gap`: always inside-letter.
  /// REQ-TIMING-8.
  insideLetter,

  /// Gap durations `x` with `4 × Letter_Gap ≤ 5x ≤ 6 × Letter_Gap`: always
  /// between-letters. REQ-TIMING-8.
  betweenLetters,

  /// Gap durations `x` with `5x ≥ 6 × Word_Gap_Threshold`, up to
  /// 10 × Word_Gap_Threshold: always between-words. REQ-TIMING-8.
  betweenWords,
}

/// A whole number from [min] to [max] with the edges drawn often; a single
/// value when `min == max`. Requires `min ≤ max`.
Arbitrary<int> _band(int min, int max) =>
    min == max ? constant(min) : _valueWithEdges(min, max);

/// A whole-µs duration inside [band] for the Well_Separated_Calibration [w].
/// The bounds are the exact integer forms of the real bounds: the dit band is
/// `integer(0, 6·dit ~/ 5)`, the dah band is
/// `integer((4·dah + 4) ~/ 5, 10·dah)`, the inside-letter band is
/// `integer(0, 6·sg ~/ 5)`, the between-letters band is
/// `integer((4·lg + 4) ~/ 5, 6·lg ~/ 5)` and the between-words band is
/// `integer((6·W + 4) ~/ 5, 10·W)`, where `W` is the Word_Gap_Threshold from
/// [exactThresholds]. The edge values are drawn often.
/// REQ-TIMING-7, REQ-TIMING-8.
Arbitrary<int> jitterDuration(WellSeparatedInput w, JitterBand band) {
  final k = w.calibration;
  switch (band) {
    case JitterBand.dit:
      return _band(0, 6 * k.ditLength ~/ 5);
    case JitterBand.dah:
      return _band((4 * k.dahLength + 4) ~/ 5, 10 * k.dahLength);
    case JitterBand.insideLetter:
      return _gapBand(0, 6 * k.symbolGap ~/ 5);
    case JitterBand.betweenLetters:
      return _gapBand((4 * k.letterGap + 4) ~/ 5, 6 * k.letterGap ~/ 5);
    case JitterBand.betweenWords:
      final word = exactThresholds(k, w.wordGapFactor).wordGapThreshold;
      return _gapBand((6 * word + 4) ~/ 5, 10 * word);
  }
}

/// [_band] with the two band ends drawn about one time in three, so each
/// REQ-TIMING-8 edge is reached by many cases. Requires `min ≤ max`.
Arbitrary<int> _gapBand(int min, int max) =>
    frequency(<(int, Arbitrary<dynamic>)>[
      (1, constantFrom<int>(<int>[min, max])),
      (2, _band(min, max)),
    ]).cast<int>();

/// One Property 8 case: a Well_Separated_Calibration (values up to
/// 10,000,000, or up to 2^40), a Press band and a duration in that band.
/// REQ-TIMING-7.
Arbitrary<(WellSeparatedInput, JitterBand, int)> pressJitterInput() =>
    combine2<WellSeparatedInput, JitterBand>(
      frequency(<(int, Arbitrary<dynamic>)>[
        (3, wellSeparated()),
        (1, wellSeparated(max: maxCalibrationValue)),
      ]).cast<WellSeparatedInput>(),
      constantFrom<JitterBand>(const <JitterBand>[
        JitterBand.dit,
        JitterBand.dah,
      ]),
    ).flatMap((r) => jitterDuration(r.$1, r.$2).map((x) => (r.$1, r.$2, x)));

/// One Property 9 case: a Well_Separated_Calibration (values up to
/// 10,000,000, or up to 2^40), a Gap band and a duration in that band.
/// REQ-TIMING-8.
Arbitrary<(WellSeparatedInput, JitterBand, int)> gapJitterInput() =>
    combine2<WellSeparatedInput, JitterBand>(
      frequency(<(int, Arbitrary<dynamic>)>[
        (3, wellSeparated()),
        (1, wellSeparated(max: maxCalibrationValue)),
      ]).cast<WellSeparatedInput>(),
      constantFrom<JitterBand>(const <JitterBand>[
        JitterBand.insideLetter,
        JitterBand.betweenLetters,
        JitterBand.betweenWords,
      ]),
    ).flatMap((r) => jitterDuration(r.$1, r.$2).map((x) => (r.$1, r.$2, x)));

/// The longest text [jitteredText] draws, in UTF-16 code units.
/// REQ-BATCH-8.
const int maxJitteredTextLength = 20;

/// One Property 11 case: a Well_Separated_Calibration [setting], a [text] of
/// 1 to 20 ITU fixture characters and single spaces (never leading, trailing
/// or doubled), the jitter factors in percent applied to each Press and Gap
/// in order ([factors], Press 0, Gap 0, Press 1, …), and the jittered
/// [events], whose timestamps are rebuilt from 0. REQ-BATCH-8.
typedef JitteredTextInput = ({
  WellSeparatedInput setting,
  String text,
  List<int> factors,
  List<EventRecord> events,
});

/// A jitter factor in percent from 80 to 120 inclusive, with both ends drawn
/// often. REQ-BATCH-8.
Arbitrary<int> _jitterPercent() => frequency(<(int, Arbitrary<dynamic>)>[
  (1, constantFrom<int>(const <int>[80, 120])),
  (1, constant(100)),
  (4, integer(min: 80, max: 120)),
]).cast<int>();

/// A text of 1 to [maxJitteredTextLength] code units, built word by word
/// rather than filtered: 1 to 20 fixture characters, and before each
/// character after the first an optional single space, added only when the
/// remaining characters still fit. So no space is leading, trailing or
/// doubled. REQ-BATCH-8.
Arbitrary<String> _spacedText() =>
    list<String>(
      constantFrom<String>(ituFixture.keys.toList()),
      minLength: 1,
      maxLength: maxJitteredTextLength,
    ).flatMap((characters) {
      final n = characters.length;
      return list<bool>(
        frequency(<(int, Arbitrary<dynamic>)>[
          (1, constant(true)),
          (3, constant(false)),
        ]).cast<bool>(),
        minLength: n,
        maxLength: n,
      ).map((spaces) {
        final text = StringBuffer();
        for (var i = 0; i < n; i++) {
          // A space here, plus this and the remaining characters, must fit.
          if (i > 0 &&
              spaces[i] &&
              text.length + 1 + (n - i) <= maxJitteredTextLength) {
            text.write(' ');
          }
          text.write(characters[i]);
        }
        return text.toString();
      });
    });

/// The Property 11 generator. The Well_Separated_Calibration [setting] has
/// every value at least 1,000 µs (REQ-BATCH-8), from up to 10,000,000 or up
/// to 2^40. The text comes from [_spacedText]. Each Press and Gap of the
/// text's Ideal_Timing (word gaps `(1.5 × W).round()`, as in [idealTiming])
/// is multiplied by its own factor from 0.80 to 1.20 and rounded to the
/// nearest Microsecond, and the timestamps are rebuilt from 0 by adding the
/// durations in order. REQ-BATCH-8, REQ-BATCH-2.
Arbitrary<JitteredTextInput> jitteredText() =>
    combine2<WellSeparatedInput, String>(
      frequency(<(int, Arbitrary<dynamic>)>[
        (3, wellSeparated(min: 1000)),
        (1, wellSeparated(min: 1000, max: maxCalibrationValue)),
      ]).cast<WellSeparatedInput>(),
      _spacedText(),
    ).flatMap((r) {
      final (setting, text) = r;
      final cal = setting.calibration;
      final plan = keyingPlan(text);
      final n = plan.symbols.length;
      final m = 2 * n - 1;
      final wordGap =
          (1.5 * exactThresholds(cal, setting.wordGapFactor).wordGapThreshold)
              .round();
      return list<int>(_jitterPercent(), minLength: m, maxLength: m).map((
        factors,
      ) {
        final events = <EventRecord>[];
        var t = 0;
        for (var i = 0; i < n; i++) {
          if (i > 0) {
            final gap = switch (plan.gapClasses[i - 1]) {
              0 => cal.symbolGap,
              1 => cal.letterGap,
              _ => wordGap,
            };
            t += _jitter(gap, factors[2 * i - 1]);
          }
          events.add((true, t));
          final press = plan.symbols[i] == '.' ? cal.ditLength : cal.dahLength;
          t += _jitter(press, factors[2 * i]);
          events.add((false, t));
        }
        return (setting: setting, text: text, factors: factors, events: events);
      });
    });

/// One Property 10 case: a valid Calibration, a Word_Gap_Factor that is a
/// multiple of 0.25 from 1.25 to 8.0, a duration `x` from 0 to
/// 10 × Word_Gap_Threshold, and a whole-number scale factor `k` from 1 to
/// 1,000. REQ-TIMING-10.
typedef ScaleInput = ({
  CalibrationInput calibration,
  double wordGapFactor,
  int duration,
  int k,
});

/// A scale factor `k` from 1 to 1,000, with 1, 2 and 1,000 drawn often.
/// REQ-TIMING-10.
Arbitrary<int> _scaleFactor() => frequency(<(int, Arbitrary<dynamic>)>[
  (1, constantFrom<int>(const <int>[1, 2, 1000])),
  (2, integer(min: 1, max: 10)),
  (4, integer(min: 1, max: 1000)),
]).cast<int>();

/// A Word_Gap_Factor that is a multiple of 0.25 from 1.25 to 8.0 inclusive.
/// REQ-TIMING-10.
Arbitrary<double> _quarterFactor() =>
    integer(min: 5, max: 32).map((n) => n / 4);

/// A duration from 0 to [max] near one of [thresholds] (the threshold and
/// its neighbours ±1), 0, [max], or anywhere in range. Every value lies in
/// `[0, max]`. Requires `max ≥ 1`.
Arbitrary<int> _durationNearAny(List<int> thresholds, int max) {
  final near = <int>{
    0,
    max,
    for (final t in thresholds)
      for (final v in <int>[t - 1, t, t + 1])
        if (v >= 0 && v <= max) v,
  }.toList();
  return frequency(<(int, Arbitrary<dynamic>)>[
    (1, constantFrom<int>(near)),
    (1, integer(min: 0, max: max)),
  ]).cast<int>();
}

/// The Property 10 generator. It draws `k` first and bounds every base
/// Calibration value by `2^40 ~/ k`, so the Calibration scaled by `k` stays
/// within the REQ-CAL-14 cap without a filter. Base values come from 1 to
/// `min(10,000,000, 2^40 ~/ k)` or from the whole allowed range. The
/// duration is drawn from 0 to 10 × the base Word_Gap_Threshold, with each
/// threshold and its neighbours drawn often. REQ-TIMING-10, REQ-CAL-14.
Arbitrary<ScaleInput> scaleInput() => _scaleFactor().flatMap((k) {
  final cap = maxCalibrationValue ~/ k;
  final small = cap < 10000000 ? cap : 10000000;
  return combine2<CalibrationInput, double>(
    frequency(<(int, Arbitrary<dynamic>)>[
      (3, calibrationValues(max: small)),
      (1, calibrationValues(max: cap)),
    ]).cast<CalibrationInput>(),
    _quarterFactor(),
  ).flatMap((r) {
    final (cal, factor) = r;
    final t = exactThresholds(cal, factor);
    return _durationNearAny(
      <int>[t.pressThreshold, t.letterGapThreshold, t.wordGapThreshold],
      10 * t.wordGapThreshold,
    ).map((x) => (calibration: cal, wordGapFactor: factor, duration: x, k: k));
  });
});

/// A Calibration_Word that passes every REQ-CAL-3 rule, built to satisfy
/// them rather than filtered: 1 to 15 ITU fixture characters (no space),
/// then `A` (`.-`: a dit, a dah and two Symbols) inserted at a random
/// position, then each character lower-cased or not at random. The result
/// has 2 to 16 UTF-16 code units. REQ-CAL-3, REQ-CAL-20.
Arbitrary<String> suitableWord() =>
    list<String>(
      constantFrom<String>(ituFixture.keys.toList()),
      minLength: 1,
      maxLength: 15,
    ).flatMap((characters) {
      final n = characters.length + 1;
      return combine2<int, List<bool>>(
        integer(min: 0, max: characters.length),
        list<bool>(boolean(), minLength: n, maxLength: n),
      ).map((r) {
        final units = List<String>.of(characters)..insert(r.$1, 'A');
        return <String>[
          for (var i = 0; i < n; i++)
            r.$2[i] ? units[i].toLowerCase() : units[i],
        ].join();
      });
    });

/// A Timing_Config for the decoders and the Calibrator under [cal]: a
/// Debounce_Time `d` from 0 to `min(Dit_Length, Symbol_Gap)`, with both ends
/// drawn often, and a valid Word_Gap_Factor. REQ-TIMING-9, REQ-CAL-15.
Arbitrary<ConfigInput> decoderConfig(CalibrationRecord cal) {
  final m = cal.ditLength < cal.symbolGap ? cal.ditLength : cal.symbolGap;
  return combine2<int, double>(
    frequency(<(int, Arbitrary<dynamic>)>[
      (1, constant(0)),
      (1, constant(m)),
      (6, integer(min: 0, max: m)),
    ]).cast<int>(),
    wordGapFactor(),
  ).map((r) => (debounceTime: r.$1, wordGapFactor: r.$2));
}

/// One Property 4 case: a suitable Calibration_Word, a valid Calibration, a
/// Timing_Config with `d ≤ min(Dit_Length, Symbol_Gap)` and the timestamp of
/// the first press. REQ-CAL-15.
typedef RoundTripInput = ({
  String word,
  CalibrationRecord calibration,
  ConfigInput config,
  int start,
});

/// The Property 4 generator. The Calibration comes from 1 to 10,000,000 or
/// from the whole range up to 2^40. The start timestamp ranges from −2^52 to
/// `2^52 − span`, where `span` is the length of the word's Ideal_Timing, so
/// every event stays within ±2^52; both ends and 0 are drawn often.
/// REQ-CAL-15, REQ-EVENT-1.
Arbitrary<RoundTripInput> roundTripInput() =>
    combine2<String, CalibrationInput>(
      suitableWord(),
      frequency(<(int, Arbitrary<dynamic>)>[
        (3, calibrationValues()),
        (1, calibrationValues(max: maxCalibrationValue)),
      ]).cast<CalibrationInput>(),
    ).flatMap((r) {
      final (word, cal) = r;
      return decoderConfig(cal).flatMap((config) {
        final span = idealTiming(word, cal, config.wordGapFactor, 0).last.$2;
        final latest = maxTimestampMagnitude - span;
        return frequency(<(int, Arbitrary<dynamic>)>[
          (1, constant(0)),
          (3, _valueWithEdges(-maxTimestampMagnitude, latest)),
        ]).cast<int>().map(
          (start) =>
              (word: word, calibration: cal, config: config, start: start),
        );
      });
    });

/// [characters] joined, each character lower-cased or not at random.
/// REQ-CAL-20.
Arbitrary<String> _randomCase(Arbitrary<List<String>> characters) =>
    characters.flatMap(
      (cs) =>
          list<bool>(boolean(), minLength: cs.length, maxLength: cs.length).map(
            (lower) => <String>[
              for (var i = 0; i < cs.length; i++)
                lower[i] ? cs[i].toLowerCase() : cs[i],
            ].join(),
          ),
    );

/// [minLength] to [maxLength] characters drawn from [from], in random ASCII
/// case.
Arbitrary<String> _wordOf(List<String> from, int minLength, int maxLength) =>
    _randomCase(
      list<String>(
        constantFrom<String>(from),
        minLength: minLength,
        maxLength: maxLength,
      ),
    );

/// Characters that are a space or have no Morse code. `😀` is two UTF-16
/// code units; `ı` and `ß` are not case folded. REQ-CAL-3.
const List<String> _badCharacters = <String>[
  ' ',
  '#',
  '!',
  '@',
  'é',
  'ı',
  'ß',
  '😀',
];

/// A Calibration_Word that fails a REQ-CAL-3 rule, with one constructor per
/// rule so each is reached without a filter: `''`; 17 to 24 fixture
/// characters; 0 to 14 fixture characters with a space or a character with
/// no code inserted; one fixture character; 2 to 16 of `E`, `I`, `S`, `H`,
/// `5` (no dah); 2 to 16 of `T`, `M`, `O`, `0` (no dit); and `E` and `T`
/// only, with at least one of each. Letters are in random ASCII case.
/// REQ-CAL-3, REQ-CAL-21.
Arbitrary<String> unsuitableWord() {
  final keys = ituFixture.keys.toList();
  return frequency(<(int, Arbitrary<dynamic>)>[
    (1, constant('')),
    (1, _wordOf(keys, 17, 24)),
    (
      2,
      combine3<String, String, int>(
        _wordOf(keys, 0, 14),
        constantFrom<String>(_badCharacters),
        integer(min: 0, max: 1 << 20),
      ).map((r) {
        final at = r.$3 % (r.$1.length + 1);
        return r.$1.substring(0, at) + r.$2 + r.$1.substring(at);
      }),
    ),
    (1, _wordOf(keys, 1, 1)),
    (1, _wordOf(const <String>['E', 'I', 'S', 'H', '5'], 2, 16)),
    (1, _wordOf(const <String>['T', 'M', 'O', '0'], 2, 16)),
    (
      1,
      combine3<List<String>, int, int>(
        list<String>(
          constantFrom<String>(const <String>['E', 'T']),
          maxLength: 14,
        ),
        integer(min: 0, max: 1 << 20),
        integer(min: 0, max: 1 << 20),
      ).flatMap((r) {
        final cs = List<String>.of(r.$1)..insert(r.$2 % (r.$1.length + 1), 'E');
        cs.insert(r.$3 % (cs.length + 1), 'T');
        return _randomCase(constant(cs));
      }),
    ),
  ]).cast<String>();
}

/// The one optional perturbation [calibrationKeying] applies to the keying.
/// REQ-CAL-8 to REQ-CAL-11, REQ-CAL-30, REQ-CAL-31.
enum KeyingPerturbation {
  /// No perturbation: the jittered keying as drawn.
  none,

  /// One Press and a neighbouring Gap removed. REQ-CAL-8.
  dropPress,

  /// One extra dit-length Press added with a Symbol_Gap. REQ-CAL-8.
  addPress,

  /// Every expected dit Press lasts 0. REQ-CAL-30.
  zeroDits,

  /// Every Gap inside a character lasts 0. REQ-CAL-30.
  zeroInsideGaps,

  /// One expected dit duration swapped with one expected dah duration.
  /// REQ-CAL-9.
  swapDitDah,

  /// One inside-letter Gap swapped with one between-letters Gap.
  /// REQ-CAL-10.
  swapGapClasses,

  /// Every expected dah Press lasts more than 2^40. REQ-CAL-31.
  tooLong,

  /// One invalid event injected. REQ-CAL-11.
  invalidEvent,
}

/// The kinds of invalid event [KeyingPerturbation.invalidEvent] injects.
/// REQ-EVENT-3, REQ-EVENT-5.
enum EventCorruption {
  /// The kind of one event flipped.
  swapKind,

  /// One event removed.
  dropEvent,

  /// One timestamp set below the one before it.
  lowerTimestamp,

  /// One timestamp set just above 2^52.
  pastMax,

  /// One timestamp set just below −2^52.
  pastMin,

  /// A press appended at the last timestamp.
  appendPress,
}

/// One [calibrationKeying] result: the events and the perturbation used.
typedef KeyingCase = ({
  List<EventRecord> events,
  KeyingPerturbation perturbation,
});

/// `v` scaled by `j / 100`, rounded half up.
int _jitter(int v, int j) => (v * j + 50) ~/ 100;

/// A keying of [word] for [cal]: the Ideal_Timing of the word's characters
/// that have a code (a Gap across spaces lasts 3 × Letter_Gap), then either
/// no jitter or a factor from 0.80 to 1.20 per Press and Gap, then one
/// optional [KeyingPerturbation]. The start timestamp is drawn so every
/// event lies within ±2^52 before any [EventCorruption]. Built to satisfy,
/// with no filter. REQ-CAL-8 to REQ-CAL-11, REQ-CAL-30, REQ-CAL-31.
Arbitrary<KeyingCase> calibrationKeying(String word, CalibrationRecord cal) {
  final plan = keyingPlan(word);
  final n = plan.symbols.length;
  final m = n == 0 ? 0 : 2 * n - 1;
  return combine6<
        bool,
        List<int>,
        KeyingPerturbation,
        EventCorruption,
        int,
        int
      >(
        boolean(),
        list<int>(integer(min: 80, max: 120), minLength: m, maxLength: m),
        frequency(<(int, Arbitrary<dynamic>)>[
          (3, constant(KeyingPerturbation.none)),
          (2, constantFrom<KeyingPerturbation>(KeyingPerturbation.values)),
          (1, constant(KeyingPerturbation.tooLong)),
          (
            1,
            constantFrom<KeyingPerturbation>(const <KeyingPerturbation>[
              KeyingPerturbation.zeroDits,
              KeyingPerturbation.zeroInsideGaps,
            ]),
          ),
        ]).cast<KeyingPerturbation>(),
        constantFrom<EventCorruption>(EventCorruption.values),
        integer(min: 0, max: 1 << 20),
        integer(min: 0, max: 1 << 20),
      )
      .flatMap((r) {
        final (jittered, factors, perturbation, corruption, pos, pos2) = r;
        int factor(int i) => jittered ? factors[i] : 100;
        final presses = <int>[
          for (var i = 0; i < n; i++)
            _jitter(
              plan.symbols[i] == '.' ? cal.ditLength : cal.dahLength,
              factor(2 * i),
            ),
        ];
        final gaps = <int>[
          for (var j = 0; j < plan.gapClasses.length; j++)
            _jitter(switch (plan.gapClasses[j]) {
              0 => cal.symbolGap,
              1 => cal.letterGap,
              _ => 3 * cal.letterGap,
            }, factor(2 * j + 1)),
        ];
        final dits = <int>[
          for (var i = 0; i < n; i++)
            if (plan.symbols[i] == '.') i,
        ];
        final dahs = <int>[
          for (var i = 0; i < n; i++)
            if (plan.symbols[i] == '-') i,
        ];
        final inside = <int>[
          for (var j = 0; j < gaps.length; j++)
            if (plan.gapClasses[j] == 0) j,
        ];
        final between = <int>[
          for (var j = 0; j < gaps.length; j++)
            if (plan.gapClasses[j] == 1) j,
        ];
        switch (perturbation) {
          case KeyingPerturbation.none:
          case KeyingPerturbation.invalidEvent:
            break;
          case KeyingPerturbation.dropPress:
            if (n > 0) {
              final i = pos % n;
              presses.removeAt(i);
              if (gaps.isNotEmpty) gaps.removeAt(i < gaps.length ? i : i - 1);
            }
          case KeyingPerturbation.addPress:
            final i = pos % (n + 1);
            presses.insert(i, cal.ditLength);
            if (n > 0) {
              gaps.insert(i < gaps.length ? i : gaps.length, cal.symbolGap);
            }
          case KeyingPerturbation.zeroDits:
            for (final i in dits) {
              presses[i] = 0;
            }
          case KeyingPerturbation.zeroInsideGaps:
            for (final j in inside) {
              gaps[j] = 0;
            }
          case KeyingPerturbation.swapDitDah:
            if (dits.isNotEmpty && dahs.isNotEmpty) {
              final a = dits[pos % dits.length];
              final b = dahs[pos2 % dahs.length];
              final t = presses[a];
              presses[a] = presses[b];
              presses[b] = t;
            }
          case KeyingPerturbation.swapGapClasses:
            if (inside.isNotEmpty && between.isNotEmpty) {
              final a = inside[pos % inside.length];
              final b = between[pos2 % between.length];
              final t = gaps[a];
              gaps[a] = gaps[b];
              gaps[b] = t;
            }
          case KeyingPerturbation.tooLong:
            for (final i in dahs) {
              presses[i] = maxCalibrationValue + 1 + pos % 1000;
            }
        }
        var span = 0;
        for (final p in presses) {
          span += p;
        }
        for (final g in gaps) {
          span += g;
        }
        final latest = maxTimestampMagnitude - span;
        return frequency(<(int, Arbitrary<dynamic>)>[
          (1, constant(0)),
          (3, _valueWithEdges(-maxTimestampMagnitude, latest)),
        ]).cast<int>().map((start) {
          final events = <EventRecord>[];
          var t = start;
          for (var i = 0; i < presses.length; i++) {
            if (i > 0) t += gaps[i - 1];
            events.add((true, t));
            t += presses[i];
            events.add((false, t));
          }
          if (perturbation == KeyingPerturbation.invalidEvent) {
            _corrupt(events, corruption, pos, pos2);
          }
          return (events: events, perturbation: perturbation);
        });
      });
}

/// Applies [corruption] to [events] at index `pos % length`. An empty list
/// gets a single press. Changes [events] in place.
void _corrupt(
  List<EventRecord> events,
  EventCorruption corruption,
  int pos,
  int pos2,
) {
  if (events.isEmpty) {
    events.add((true, 0));
    return;
  }
  final i = pos % events.length;
  final (isPress, t) = events[i];
  switch (corruption) {
    case EventCorruption.swapKind:
      events[i] = (!isPress, t);
    case EventCorruption.dropEvent:
      events.removeAt(i);
    case EventCorruption.lowerTimestamp:
      if (events.length < 2) {
        // A single event has nothing before it: append one below it.
        events.add((true, t - 1 - pos2 % 1000));
        return;
      }
      final j = i == 0 ? 1 : i;
      events[j] = (events[j].$1, events[j - 1].$2 - 1 - pos2 % 1000);
    case EventCorruption.pastMax:
      events[i] = (isPress, maxTimestampMagnitude + 1 + pos2 % 1000);
    case EventCorruption.pastMin:
      events[i] = (isPress, -maxTimestampMagnitude - 1 - pos2 % 1000);
    case EventCorruption.appendPress:
      events.add((true, events.last.$2));
  }
}

/// One Property 5 case: a Calibration_Word, its keying, the Calibration it
/// was keyed from, and a Timing_Config. REQ-CAL-3, REQ-CAL-12.
typedef RejectionInput = ({
  String word,
  CalibrationRecord calibration,
  KeyingCase keying,
  ConfigInput config,
});

/// The Property 5 generator. The word is suitable three times in four and
/// otherwise breaks one REQ-CAL-3 rule. The Calibration comes from 1 to 50
/// (so jitter rounding makes ties), 1 to 10,000,000, or up to 2^40. The
/// Debounce_Time is 0 three times in four for the zero perturbations, and
/// otherwise 0, `min(Dit_Length, Symbol_Gap)`, a value between them, or a
/// value above it that drops Presses. REQ-CAL-3, REQ-CAL-5, REQ-CAL-8 to
/// REQ-CAL-12, REQ-CAL-30, REQ-CAL-31.
Arbitrary<RejectionInput> rejectionInput() =>
    combine2<String, CalibrationInput>(
      frequency(<(int, Arbitrary<dynamic>)>[
        (3, suitableWord()),
        (1, unsuitableWord()),
      ]).cast<String>(),
      frequency(<(int, Arbitrary<dynamic>)>[
        (1, calibrationValues(max: 50)),
        (3, calibrationValues()),
        (1, calibrationValues(max: maxCalibrationValue)),
      ]).cast<CalibrationInput>(),
    ).flatMap((r) {
      final (word, cal) = r;
      return calibrationKeying(word, cal).flatMap((keying) {
        final m = cal.ditLength < cal.symbolGap ? cal.ditLength : cal.symbolGap;
        final zero =
            keying.perturbation == KeyingPerturbation.zeroDits ||
            keying.perturbation == KeyingPerturbation.zeroInsideGaps;
        final d = zero
            ? frequency(<(int, Arbitrary<dynamic>)>[
                (3, constant(0)),
                (1, integer(min: 0, max: m)),
              ]).cast<int>()
            : frequency(<(int, Arbitrary<dynamic>)>[
                (1, constant(0)),
                (1, constant(m)),
                (4, integer(min: 0, max: m)),
                (1, integer(min: m + 1, max: m + 1 + 2 * cal.dahLength)),
              ]).cast<int>();
        return combine2<int, double>(d, wordGapFactor()).map(
          (c) => (
            word: word,
            calibration: cal,
            keying: keying,
            config: (debounceTime: c.$1, wordGapFactor: c.$2),
          ),
        );
      });
    });

/// The longest Press or Gap [validEvents] draws, 10,000,000 µs. REQ-PBT-8.
const int maxEventDuration = 10000000;

/// The most Presses [validEvents] draws.
const int maxEventPresses = 40;

/// A Valid_Event_Sequence as plain records for the Calibration [cal] and the
/// Timing_Config [cfg]: 0 to [maxEventPresses] Presses whose Press and Gap
/// durations run from 0 to [maxEventDuration], one in four drawn from 0 to
/// the Debounce_Time so bounce is common. The first press timestamp ranges
/// over negative and positive values, with both ends drawn often, and leaves
/// room so the last event stays within 2^52. Built to satisfy, with no
/// filter. [cal] is unused beyond documenting the case it belongs to.
/// REQ-EVENT-1, REQ-BATCH-1, REQ-DEBOUNCE-9, REQ-PBT-8.
Arbitrary<List<EventRecord>> validEvents(
  CalibrationRecord cal,
  ConfigInput cfg,
) {
  final d = cfg.debounceTime;
  return combine2<int, List<(int, int)>>(
    frequency(<(int, Arbitrary<dynamic>)>[
      (1, constant(0)),
      (
        3,
        _valueWithEdges(
          -maxTimestampMagnitude,
          maxTimestampMagnitude - 2 * maxEventPresses * maxEventDuration,
        ),
      ),
    ]).cast<int>(),
    list<(int, int)>(
      combine2<int, int>(
        _durationWithShort(d, maxEventDuration),
        _durationWithShort(d, maxEventDuration),
      ),
      maxLength: maxEventPresses,
    ),
  ).map((r) {
    // Each pair is (Gap before this Press, Press duration); the Gap of the
    // first pair is unused.
    var t = r.$1;
    final events = <EventRecord>[];
    for (var i = 0; i < r.$2.length; i++) {
      final (gap, duration) = r.$2[i];
      if (i > 0) t += gap;
      events.add((true, t));
      t += duration;
      events.add((false, t));
    }
    return events;
  });
}

/// The Presses of a Valid_Event_Sequence [events], pairing each press with
/// the release after it. REQ-BATCH-1.
List<PressRecord> pairEvents(List<EventRecord> events) => <PressRecord>[
  for (var i = 0; i + 1 < events.length; i += 2)
    (events[i].$2, events[i + 1].$2),
];

/// Whether the Valid_Event_Sequence [events] has a Press or a Gap shorter
/// than [d]. REQ-PBT-8.
bool eventsHaveShortDuration(List<EventRecord> events, int d) =>
    hasShortDuration((debounceTime: d, presses: pairEvents(events)));

/// One Property 3 case: a valid Calibration, a Timing_Config with
/// `d ≤ min(Dit_Length, Symbol_Gap)` and a Valid_Event_Sequence.
/// REQ-DEBOUNCE-9, REQ-BATCH-1, REQ-TIMING-9.
typedef DecodeInput = ({
  CalibrationRecord calibration,
  ConfigInput config,
  List<EventRecord> events,
});

/// The Property 3 generator. The Calibration comes from 1 to 1,000,000 (so
/// the 10,000,000 µs durations span every class) or from 1 to 10,000,000;
/// the Timing_Config from [decoderConfig]; the events from [validEvents].
/// REQ-DEBOUNCE-9, REQ-BATCH-1, REQ-PBT-8.
Arbitrary<DecodeInput> decodeInput() =>
    frequency(<(int, Arbitrary<dynamic>)>[
      (1, calibrationValues(max: 1000000)),
      (1, calibrationValues()),
    ]).cast<CalibrationInput>().flatMap(
      (cal) => decoderConfig(cal).flatMap(
        (cfg) => validEvents(
          cal,
          cfg,
        ).map((events) => (calibration: cal, config: cfg, events: events)),
      ),
    );

/// An inclusive range of whole Microseconds `(low, high)`.
typedef DurationSpan = (int, int);

/// The durations within [percent] percent of [t] (`t ≥ 0`), as an inclusive
/// integer range: every whole `x` with `100·|x − t| ≤ percent·t`. A duration
/// outside it is more than [percent] percent from [t]. REQ-BATCH-9.
DurationSpan marginAround(int t, int percent) =>
    ((((100 - percent) * t) + 99) ~/ 100, ((100 + percent) * t) ~/ 100);

/// The parts of `[low, high]` that no range in [forbidden] covers, in
/// ascending order. Empty when everything is covered or `low > high`.
List<DurationSpan> _allowedSpans(
  int low,
  int high,
  List<DurationSpan> forbidden,
) {
  final sorted = List<DurationSpan>.of(forbidden)
    ..sort((a, b) => a.$1.compareTo(b.$1));
  final out = <DurationSpan>[];
  var current = low;
  for (final (a, b) in sorted) {
    if (current > high || a > high) break;
    if (b < current) continue;
    if (a > current) out.add((current, a - 1));
    current = b + 1;
  }
  if (current <= high) out.add((current, high));
  return out;
}

/// A duration from one of [spans] (non-empty): a span index, then an offset
/// inside that span with its ends drawn often.
Arbitrary<int> _fromSpans(List<DurationSpan> spans) {
  Arbitrary<int> inSpan(DurationSpan s) => _band(s.$1, s.$2);
  if (spans.length == 1) return inSpan(spans.first);
  return integer(
    min: 0,
    max: spans.length - 1,
  ).flatMap((i) => inSpan(spans[i]));
}

/// A pair `(a, b)` with `1,000 ≤ a ≤ max − 5` and `a + 5 ≤ b ≤ max`, so the
/// pair stays ordered after scaling by any `k ≥ 0.25` and rounding.
Arbitrary<(int, int)> _spreadPair(int max) => combine2<int, int>(
  _valueWithEdges(1000, max - 5),
  _positiveStep(max),
).map((r) => (r.$1, _above(r.$1, r.$2 + 4, max)));

/// A valid Calibration with every value from 1,000 to [max], Dah_Length at
/// least Dit_Length + 5 and Letter_Gap at least Symbol_Gap + 5.
/// REQ-BATCH-9, REQ-CAL-14.
Arbitrary<CalibrationInput> _marginCalibration(int max) =>
    combine2<(int, int), (int, int)>(_spreadPair(max), _spreadPair(max)).map(
      (r) => (
        ditLength: r.$1.$1,
        dahLength: r.$1.$2,
        symbolGap: r.$2.$1,
        letterGap: r.$2.$2,
      ),
    );

/// A scale factor `k` from 0.25 to 4 inclusive, with both ends, 1 and some
/// round values drawn often. REQ-BATCH-9.
Arbitrary<double> _marginScale() => frequency(<(int, Arbitrary<dynamic>)>[
  (1, constantFrom<double>(const <double>[0.25, 0.5, 1.0, 2.0, 4.0])),
  (3, float(min: 0.25, max: 4.0)),
]).cast<double>();

/// A kept duration [total] split into `[a, bounce, c]` with the bounce from
/// 1,000 to [bounceHigh] and `a`, `c` at least 1,000 and outside every range
/// in [forbidden]. When no split fits, `[total]` unchanged (a fixed
/// fallback, not a filter).
Arbitrary<List<int>> _withBounce(
  int total,
  int bounceHigh,
  List<DurationSpan> forbidden,
) => _band(1000, bounceHigh).flatMap((bounce) {
  final rest = total - bounce;
  if (rest < 2000) return constant(<int>[total]);
  final spans = _allowedSpans(1000, rest - 1000, <DurationSpan>[
    ...forbidden,
    for (final (lo, hi) in forbidden) (rest - hi, rest - lo),
  ]);
  if (spans.isEmpty) return constant(<int>[total]);
  return _fromSpans(spans).map((a) => <int>[a, bounce, rest - a]);
});

/// One Property 12 case: a Calibration, a Timing_Config, a scale factor `k`,
/// the first press timestamp, and the Press and Gap durations in order
/// (Press 0, Gap 0, Press 1, …; empty or of odd length). [bounces] counts the
/// kept Presses split by a short Gap plus the kept Gaps holding a short
/// Press. REQ-BATCH-9.
typedef MarginScenario = ({
  CalibrationRecord calibration,
  ConfigInput config,
  double k,
  int start,
  List<int> durations,
  int bounces,
});

/// The most kept Presses [marginScenario] draws.
const int maxMarginPresses = 20;

/// The Property 12 generator (REQ-BATCH-9), built to satisfy the margins
/// rather than filtered.
///
/// It draws a Calibration with every value at least 1,000 µs (up to
/// 10,000,000, or up to 2^38 so the Calibration scaled by 4 stays within
/// the 2^40 cap), a Debounce_Time `d` from 0 to `min(Dit_Length,
/// Symbol_Gap)`, a Word_Gap_Factor and `k` from 0.25 to 4. It then builds
/// the sequence at the debounced level: each kept Press (1,000 to
/// 3 × Dah_Length) and kept Gap (1,000 to 3 × Word_Gap_Threshold) comes
/// from the parts of its range more than 2 percent from `d` and from every
/// threshold. When `d ≥ 1,011`, it may add bounce that leaves every kept
/// duration unchanged: a kept Press split into Press, short Gap, Press, or
/// a short Press put inside a kept Gap. Each bounce duration lies from
/// 1,000 to below 0.99 × `d`; every other raw part is more than 1 percent
/// from `d` and from every threshold, and a part of a split Gap is more
/// than 1.01 × `d`. The first press timestamp lies within ±2^51, which
/// leaves room for the scaled sequence below 2^52. REQ-BATCH-9, REQ-PBT-8.
Arbitrary<MarginScenario> marginScenario() =>
    frequency(<(int, Arbitrary<dynamic>)>[
      (3, _marginCalibration(10000000)),
      (1, _marginCalibration(maxCalibrationValue ~/ 4)),
    ]).cast<CalibrationInput>().flatMap((cal) {
      final m = cal.ditLength < cal.symbolGap ? cal.ditLength : cal.symbolGap;
      final debounce = frequency(<(int, Arbitrary<dynamic>)>[
        (1, constant(0)),
        (2, integer(min: 0, max: m)),
        if (m >= 1011) (4, integer(min: 1011, max: m)),
      ]).cast<int>();
      // Large Calibrations keep the factor small so the sequence stays well
      // inside ±2^52 after scaling.
      final factor = cal.letterGap <= 10000000
          ? wordGapFactor()
          : _quarterFactor();
      final half = maxTimestampMagnitude ~/ 2;
      final start = frequency(<(int, Arbitrary<dynamic>)>[
        (1, constant(0)),
        (3, _valueWithEdges(-half, half)),
      ]).cast<int>();
      return combine4<int, double, double, int>(
        debounce,
        factor,
        _marginScale(),
        start,
      ).flatMap((r) {
        final (d, f, k, first) = r;
        final t = exactThresholds(cal, f);
        final thresholds = <int>[
          t.pressThreshold,
          t.letterGapThreshold,
          t.wordGapThreshold,
        ];
        final kept = <DurationSpan>[
          (0, (102 * d) ~/ 100),
          for (final x in thresholds) marginAround(x, 2),
        ];
        final rawPress = <DurationSpan>[
          marginAround(d, 1),
          for (final x in thresholds) marginAround(x, 1),
        ];
        final rawGap = <DurationSpan>[
          (0, (101 * d) ~/ 100),
          for (final x in thresholds) marginAround(x, 1),
        ];
        final pressSpans = _allowedSpans(1000, 3 * cal.dahLength, kept);
        final gapSpans = _allowedSpans(1000, 3 * t.wordGapThreshold, kept);
        final canBounce = d >= 1011;
        // Bounce lies below 0.99 × d: the largest whole value less than it.
        final bounceHigh = (99 * d + 99) ~/ 100 - 1;

        Arbitrary<List<int>> parts(int total, List<DurationSpan> forbidden) =>
            frequency(<(int, Arbitrary<dynamic>)>[
              (2, constant(<int>[total])),
              (1, _withBounce(total, bounceHigh, forbidden)),
            ]).cast<List<int>>();

        final element =
            combine2<int, int>(
              _fromSpans(pressSpans),
              _fromSpans(gapSpans),
            ).flatMap((pg) {
              final (p, g) = pg;
              if (!canBounce) {
                return constant((<int>[p], <int>[g]));
              }
              return combine2<List<int>, List<int>>(
                parts(p, rawPress),
                parts(g, rawGap),
              );
            });

        return list<(List<int>, List<int>)>(
          element,
          maxLength: maxMarginPresses,
        ).map((elements) {
          final durations = <int>[];
          var bounces = 0;
          for (var i = 0; i < elements.length; i++) {
            final (pressParts, gapParts) = elements[i];
            // The Gap of the first element is unused.
            if (i > 0) {
              durations.addAll(gapParts);
              if (gapParts.length > 1) bounces++;
            }
            durations.addAll(pressParts);
            if (pressParts.length > 1) bounces++;
          }
          return (
            calibration: cal,
            config: (debounceTime: d, wordGapFactor: f),
            k: k,
            start: first,
            durations: durations,
            bounces: bounces,
          );
        });
      });
    });

/// A whole number from [low] to [high], each capped at [maxEventDuration].
/// Requires `low ≤ high`.
Arbitrary<int> _cappedBand(int low, int high) {
  final lo = low < maxEventDuration ? low : maxEventDuration;
  final hi = high < maxEventDuration ? high : maxEventDuration;
  return _band(lo, hi);
}

/// A Valid_Event_Sequence for [cal] and [cfg] whose Press and Gap durations
/// are drawn by class rather than uniformly, so letters of every length,
/// unknown Symbol sequences and word gaps are common. Each Press is short
/// (0 to `d`), near the dit or dah class, or anywhere up to
/// [maxEventDuration]; each Gap is short (0 to `d`), inside a letter (`d` to
/// Letter_Gap_Threshold − 1), between letters, between words, or anywhere.
/// Every duration stays from 0 to [maxEventDuration]. The first press
/// timestamp ranges over negative and positive values and leaves room so
/// the last event stays within 2^52. Built to satisfy, with no filter.
/// Requires `d ≤ min(Dit_Length, Symbol_Gap)`. REQ-BATCH-1, REQ-BATCH-3,
/// REQ-PBT-8.
Arbitrary<List<EventRecord>> classedEvents(
  CalibrationRecord cal,
  ConfigInput cfg,
) {
  final d = cfg.debounceTime;
  final t = exactThresholds(cal, cfg.wordGapFactor);
  final press = frequency(<(int, Arbitrary<dynamic>)>[
    (1, _cappedBand(0, d)),
    (3, _cappedBand(d, t.pressThreshold - 1)),
    (2, _cappedBand(t.pressThreshold, 2 * cal.dahLength)),
    (1, integer(min: 0, max: maxEventDuration)),
  ]).cast<int>();
  final gap = frequency(<(int, Arbitrary<dynamic>)>[
    (1, _cappedBand(0, d)),
    (5, _cappedBand(d, t.letterGapThreshold - 1)),
    (2, _cappedBand(t.letterGapThreshold, t.wordGapThreshold - 1)),
    (1, _cappedBand(t.wordGapThreshold, 2 * t.wordGapThreshold)),
    (1, integer(min: 0, max: maxEventDuration)),
  ]).cast<int>();
  return combine2<int, List<(int, int)>>(
    frequency(<(int, Arbitrary<dynamic>)>[
      (1, constant(0)),
      (
        3,
        _valueWithEdges(
          -maxTimestampMagnitude,
          maxTimestampMagnitude - 2 * maxEventPresses * maxEventDuration,
        ),
      ),
    ]).cast<int>(),
    list<(int, int)>(
      combine2<int, int>(gap, press),
      maxLength: maxEventPresses,
    ),
  ).map((r) {
    // Each pair is (Gap before this Press, Press duration); the Gap of the
    // first pair is unused.
    var time = r.$1;
    final events = <EventRecord>[];
    for (var i = 0; i < r.$2.length; i++) {
      final (g, p) = r.$2[i];
      if (i > 0) time += g;
      events.add((true, time));
      time += p;
      events.add((false, time));
    }
    return events;
  });
}

/// The Property 13 generator: a valid Calibration from 1 to 1,000,000 or
/// from 1 to 10,000,000, a Timing_Config from [decoderConfig]
/// (`d ≤ min(Dit_Length, Symbol_Gap)`), and a Valid_Event_Sequence drawn
/// either uniformly by [validEvents] or by class by [classedEvents].
/// REQ-BATCH-1, REQ-BATCH-3, REQ-BATCH-4, REQ-EVENT-2.
Arbitrary<DecodeInput> referenceDecodeInput() =>
    frequency(<(int, Arbitrary<dynamic>)>[
      (1, calibrationValues(max: 1000000)),
      (1, calibrationValues()),
    ]).cast<CalibrationInput>().flatMap(
      (cal) => decoderConfig(cal).flatMap(
        (cfg) =>
            frequency(<(int, Arbitrary<dynamic>)>[
              (1, validEvents(cal, cfg)),
              (2, classedEvents(cal, cfg)),
            ]).cast<List<EventRecord>>().map(
              (events) => (calibration: cal, config: cfg, events: events),
            ),
      ),
    );

/// One edit [corrupted] applies: the [corruption], the event [position]
/// (−1 for the last event, otherwise taken modulo the current length) and an
/// [amount] from 0 to 2^20 that sets how far a timestamp moves.
/// REQ-EVENT-3, REQ-EVENT-5.
typedef EventEdit = ({EventCorruption corruption, int position, int amount});

/// One [corrupted] result: the [edits] in the order applied and the edited
/// [events].
typedef CorruptedEvents = ({List<EventEdit> edits, List<EventRecord> events});

/// An event position: the first event, the last event (−1), or any event,
/// so rules tied to index 0 and to the last index are reached often.
Arbitrary<int> _editPosition() => frequency(<(int, Arbitrary<dynamic>)>[
  (1, constant(0)),
  (1, constant(-1)),
  (4, integer(min: 0, max: 1 << 20)),
]).cast<int>();

/// One [EventEdit], every [EventCorruption] equally likely.
Arbitrary<EventEdit> _eventEdit() => combine3<EventCorruption, int, int>(
  constantFrom<EventCorruption>(EventCorruption.values),
  _editPosition(),
  integer(min: 0, max: 1 << 20),
).map((r) => (corruption: r.$1, position: r.$2, amount: r.$3));

/// A copy of [events] with [edits] applied in order. Each edit resolves its
/// position against the list as it stands after the edits before it. An
/// edit on an empty list adds a single press. [events] is not changed.
/// REQ-EVENT-3, REQ-EVENT-5.
List<EventRecord> applyEdits(List<EventRecord> events, List<EventEdit> edits) {
  final out = List<EventRecord>.of(events);
  for (final e in edits) {
    final position = e.position < 0
        ? (out.isEmpty ? 0 : out.length - 1)
        : e.position;
    _corrupt(out, e.corruption, position, e.amount);
  }
  return out;
}

/// [events] with 1 to 3 edits applied: swap a kind, drop an event, lower a
/// timestamp below the one before it, push a timestamp just past 2^52 or
/// just below −2^52, or append a press at the last timestamp. Built without
/// a filter; a combination of edits may happen to give a
/// Valid_Event_Sequence, which the property checks against the reference
/// too. [events] is not changed. REQ-EVENT-3, REQ-EVENT-5.
Arbitrary<CorruptedEvents> corrupted(List<EventRecord> events) =>
    list<EventEdit>(
      _eventEdit(),
      minLength: 1,
      maxLength: 3,
    ).map((edits) => (edits: edits, events: applyEdits(events, edits)));

/// One Property 14 case: a valid Calibration, a Timing_Config with
/// `d ≤ min(Dit_Length, Symbol_Gap)`, the Valid_Event_Sequence before
/// corruption ([original]) and the [corrupted] result. REQ-EVENT-3.
typedef CorruptedInput = ({
  CalibrationRecord calibration,
  ConfigInput config,
  List<EventRecord> original,
  CorruptedEvents corrupted,
});

/// The Property 14 generator: a valid Calibration from 1 to 10,000,000, a
/// Timing_Config from [decoderConfig], a Valid_Event_Sequence from
/// [validEvents] (negative starts included), then [corrupted].
/// REQ-EVENT-3, REQ-EVENT-5, REQ-EVENT-6.
Arbitrary<CorruptedInput> corruptedInput() => calibrationValues().flatMap(
  (cal) => decoderConfig(cal).flatMap(
    (cfg) => validEvents(cal, cfg).flatMap(
      (events) => corrupted(events).map(
        (c) => (calibration: cal, config: cfg, original: events, corrupted: c),
      ),
    ),
  ),
);

/// One Property 15 case: a valid Calibration, a Timing_Config with
/// `d ≤ min(Dit_Length, Symbol_Gap)`, a Valid_Event_Sequence ([events]) and
/// the Live_Decoder calls built from it ([calls]): every event in order,
/// with [advanceCount] `advanceTo` calls inserted at non-decreasing times.
/// [calls] does not include the final `advanceTo`; [finalAdvance] is its
/// time, the last release plus `max(d, Letter_Gap_Threshold)`, or null when
/// [events] is empty. REQ-LIVE-11.
typedef LiveScenario = ({
  CalibrationRecord calibration,
  ConfigInput config,
  List<EventRecord> events,
  List<LiveCallRecord> calls,
  int advanceCount,
  int? finalAdvance,
});

/// The most `advanceTo` calls [liveScenario] inserts.
const int maxLiveAdvances = 20;

/// An `advanceTo` offset from 0 to [maxEventDuration]: 0, the Debounce_Time
/// [d], each threshold in [t] and their neighbours, or anywhere in range.
/// REQ-LIVE-4, REQ-LIVE-6.
Arbitrary<int> _liveOffset(int d, ThresholdRecord t) {
  final near = <int>{
    0,
    for (final x in <int>[
      d,
      t.pressThreshold,
      t.letterGapThreshold,
      t.wordGapThreshold,
    ])
      for (final y in <int>[x - 1, x, x + 1])
        if (y >= 0 && y <= maxEventDuration) y,
  }.toList()..sort();
  return frequency(<(int, Arbitrary<dynamic>)>[
    (2, constantFrom<int>(near)),
    (1, integer(min: 0, max: maxEventDuration)),
  ]).cast<int>();
}

/// The calls of [events] with one `advanceTo` per entry of [advances]
/// inserted. Each entry is `(slot, offset)`. Slot −1 is before the first
/// event, at the first event's timestamp minus the offset (never below
/// −2^52); slot `i` is right after event `i`, at its timestamp plus the
/// offset, capped at the next event's timestamp, or for the last event at
/// [tail]. With no events, the time is the offset itself. Entries are sorted
/// by slot and time, so the timestamps never decrease. [events] and
/// [advances] are not changed. REQ-LIVE-11.
List<LiveCallRecord> interleaveAdvances(
  List<EventRecord> events,
  List<(int, int)> advances,
  int tail,
) {
  final n = events.length;
  int timeOf((int, int) a) {
    final (slot, offset) = a;
    if (n == 0) return offset;
    if (slot < 0) {
      final first = events.first.$2;
      final room = first + maxTimestampMagnitude;
      return first - (offset < room ? offset : room);
    }
    final at = events[slot].$2;
    final cap = slot + 1 < n ? events[slot + 1].$2 - at : tail;
    return at + (offset < cap ? offset : cap);
  }

  final timed = <(int, int)>[
    for (final a in advances) (n == 0 ? -1 : a.$1, timeOf(a)),
  ]..sort((x, y) => x.$1 != y.$1 ? x.$1 - y.$1 : x.$2.compareTo(y.$2));
  final calls = <LiveCallRecord>[];
  var next = 0;
  void advancesIn(int slot) {
    while (next < timed.length && timed[next].$1 == slot) {
      calls.add((kind: LiveCallKind.advance, timestamp: timed[next].$2));
      next++;
    }
  }

  advancesIn(-1);
  for (var i = 0; i < n; i++) {
    final (isPress, t) = events[i];
    calls.add((
      kind: isPress ? LiveCallKind.press : LiveCallKind.release,
      timestamp: t,
    ));
    advancesIn(i);
  }
  return calls;
}

/// The Property 15 generator (REQ-LIVE-11), built to satisfy with no filter.
///
/// A valid Calibration from 1 to 1,000,000 or from 1 to 10,000,000, a
/// Timing_Config from [decoderConfig], and a Valid_Event_Sequence drawn
/// uniformly by [validEvents] or by class by [classedEvents] (negative
/// starts and durations up to 10,000,000 included, REQ-PBT-8). In about one
/// case in three it then draws 1 to [maxLiveAdvances] `advanceTo` calls as
/// `(slot, offset)` pairs placed by [interleaveAdvances], with offsets near
/// the Debounce_Time and the thresholds drawn often. A sequence spans at
/// most `79 × 10,000,000` µs from a start at most `2^52 − 80 × 10,000,000`,
/// and `max(d, Letter_Gap_Threshold)` is at most 10,000,000, so the final
/// `advanceTo` stays within 2^52. REQ-LIVE-11, REQ-PBT-8.
Arbitrary<LiveScenario> liveScenario() =>
    frequency(<(int, Arbitrary<dynamic>)>[
      (1, calibrationValues(max: 1000000)),
      (1, calibrationValues()),
    ]).cast<CalibrationInput>().flatMap(
      (cal) => decoderConfig(cal).flatMap((cfg) {
        final d = cfg.debounceTime;
        final t = exactThresholds(cal, cfg.wordGapFactor);
        final tail = d > t.letterGapThreshold ? d : t.letterGapThreshold;
        return frequency(<(int, Arbitrary<dynamic>)>[
          (1, validEvents(cal, cfg)),
          (2, classedEvents(cal, cfg)),
        ]).cast<List<EventRecord>>().flatMap((events) {
          final n = events.length;
          final slot = n == 0 ? constant(-1) : integer(min: -1, max: n - 1);
          final advances = frequency(<(int, Arbitrary<dynamic>)>[
            (2, constant(<(int, int)>[])),
            (
              1,
              list<(int, int)>(
                combine2<int, int>(slot, _liveOffset(d, t)),
                minLength: 1,
                maxLength: maxLiveAdvances,
              ),
            ),
          ]).cast<List<(int, int)>>();
          return advances.map(
            (a) => (
              calibration: cal,
              config: cfg,
              events: events,
              calls: interleaveAdvances(events, a, tail),
              advanceCount: a.length,
              finalAdvance: n == 0 ? null : events.last.$2 + tail,
            ),
          );
        });
      }),
    );

/// The REQ-LIVE-9 rule a Property 16 invalid call is built to break.
/// REQ-LIVE-9, REQ-EVENT-5.
enum InvalidLiveRule {
  /// A timestamp below −2^52. REQ-EVENT-5.
  belowRange,

  /// A timestamp above 2^52. REQ-EVENT-5.
  aboveRange,

  /// A timestamp earlier than the latest received one. REQ-LIVE-9.
  decreasing,

  /// A press call while pressed. REQ-LIVE-9.
  pressWhilePressed,

  /// A release call while not pressed. REQ-LIVE-9.
  releaseWhileNotPressed,
}

/// One Property 16 case: a [scenario] from [liveScenario], a [cut] from 0 to
/// `scenario.calls.length`, and one [invalid] call made after the first
/// [cut] calls, built to break [rule]. REQ-LIVE-9, REQ-EVENT-5.
typedef InvalidLiveScenario = ({
  LiveScenario scenario,
  int cut,
  InvalidLiveRule rule,
  LiveCallRecord invalid,
});

/// Whether the switch is pressed after the first [cut] of [calls], the
/// latest timestamp among them (null when [cut] is 0), and the number of
/// press and release calls among them. REQ-LIVE-9.
({bool pressed, int? latest, int eventCount}) livePrefixState(
  List<LiveCallRecord> calls,
  int cut,
) {
  var pressed = false;
  int? latest;
  var eventCount = 0;
  for (final c in calls.take(cut)) {
    latest = c.timestamp;
    switch (c.kind) {
      case LiveCallKind.press:
        pressed = true;
        eventCount++;
      case LiveCallKind.release:
        pressed = false;
        eventCount++;
      case LiveCallKind.advance:
        break;
    }
  }
  return (pressed: pressed, latest: latest, eventCount: eventCount);
}

const List<LiveCallKind> _allCallKinds = LiveCallKind.values;

/// A timestamp from [from] to [from] + 10,000,000, capped at 2^52, with
/// [from] itself drawn often. REQ-LIVE-9.
Arbitrary<int> _notBefore(int from) {
  final room = maxTimestampMagnitude - from;
  final hi = room < maxEventDuration ? room : maxEventDuration;
  return frequency(<(int, Arbitrary<dynamic>)>[
    (1, constant(0)),
    (3, integer(min: 0, max: hi)),
  ]).cast<int>().map((o) => from + o);
}

/// The invalid call for [rule] in the prefix state [st]. Every result
/// breaks [rule] and, for the state rules, keeps the timestamp in range and
/// not decreasing. REQ-LIVE-9, REQ-EVENT-5.
Arbitrary<LiveCallRecord> _invalidCall(
  InvalidLiveRule rule,
  ({bool pressed, int? latest, int eventCount}) st,
) {
  final kind = constantFrom<LiveCallKind>(_allCallKinds);
  final beyond = frequency(<(int, Arbitrary<dynamic>)>[
    (1, constant(1)),
    (1, integer(min: 1, max: maxEventDuration)),
  ]).cast<int>();
  switch (rule) {
    case InvalidLiveRule.belowRange:
      return combine2<LiveCallKind, int>(
        kind,
        beyond,
      ).map((r) => (kind: r.$1, timestamp: -maxTimestampMagnitude - r.$2));
    case InvalidLiveRule.aboveRange:
      return combine2<LiveCallKind, int>(
        kind,
        beyond,
      ).map((r) => (kind: r.$1, timestamp: maxTimestampMagnitude + r.$2));
    case InvalidLiveRule.decreasing:
      // Only offered when latest > −2^52 (see invalidLiveScenario).
      final latest = st.latest!;
      final room = latest + maxTimestampMagnitude;
      final hi = room < maxEventDuration ? room : maxEventDuration;
      final back = frequency(<(int, Arbitrary<dynamic>)>[
        (1, constant(1)),
        (3, integer(min: 1, max: hi)),
      ]).cast<int>();
      return combine2<LiveCallKind, int>(
        kind,
        back,
      ).map((r) => (kind: r.$1, timestamp: latest - r.$2));
    case InvalidLiveRule.pressWhilePressed:
      return _notBefore(st.latest!)
          .map((t) => (kind: LiveCallKind.press, timestamp: t));
    case InvalidLiveRule.releaseWhileNotPressed:
      final latest = st.latest;
      final time = latest == null
          ? frequency(<(int, Arbitrary<dynamic>)>[
              (
                1,
                constantFrom<int>(<int>[
                  -maxTimestampMagnitude,
                  0,
                  maxTimestampMagnitude,
                ]),
              ),
              (
                3,
                integer(
                  min: -maxTimestampMagnitude,
                  max: maxTimestampMagnitude,
                ),
              ),
            ]).cast<int>()
          : _notBefore(latest);
      return time.map((t) => (kind: LiveCallKind.release, timestamp: t));
  }
}

/// The Property 16 generator (REQ-LIVE-9, REQ-EVENT-5), built to satisfy
/// with no filter.
///
/// Draws a [liveScenario], a cut point (0 drawn often, so a release before
/// any event is common), then one rule from those that can be broken in the
/// state after the cut: both range rules always; decreasing when a call has
/// been received and the latest timestamp is above −2^52; press while
/// pressed or release while not pressed, whichever matches the state. The
/// invalid call itself comes from [_invalidCall].
Arbitrary<InvalidLiveScenario> invalidLiveScenario() =>
    liveScenario().flatMap((s) {
      final n = s.calls.length;
      final cuts = n == 0
          ? constant(0)
          : frequency(<(int, Arbitrary<dynamic>)>[
              (1, constant(0)),
              (1, constant(n)),
              (4, integer(min: 0, max: n)),
            ]).cast<int>();
      return cuts.flatMap((cut) {
        final st = livePrefixState(s.calls, cut);
        final latest = st.latest;
        final rules = <InvalidLiveRule>[
          InvalidLiveRule.belowRange,
          InvalidLiveRule.aboveRange,
          if (latest != null && latest > -maxTimestampMagnitude)
            InvalidLiveRule.decreasing,
          st.pressed
              ? InvalidLiveRule.pressWhilePressed
              : InvalidLiveRule.releaseWhileNotPressed,
        ];
        return constantFrom<InvalidLiveRule>(rules).flatMap(
          (rule) => _invalidCall(
            rule,
            st,
          ).map((call) => (scenario: s, cut: cut, rule: rule, invalid: call)),
        );
      });
    });

/// One Property 17 Debouncer case: a [PressListCase] that is either valid
/// ([corrupted] false) or has one Press made to break a REQ-DEBOUNCE-20
/// rule ([corrupted] true). REQ-ENGINE-2, REQ-DEBOUNCE-20.
typedef DebounceDeterminismCase = ({
  int debounceTime,
  List<(int, int)> presses,
  bool corrupted,
});

/// A [pressList] case (up to 20 Presses), left valid half the time and
/// otherwise given one invalid Press: a release before its press, or a
/// press before the previous release. An empty list becomes one Press
/// released before it is pressed. Built to satisfy, with no filter.
/// REQ-ENGINE-2, REQ-DEBOUNCE-20.
Arbitrary<DebounceDeterminismCase> debounceDeterminismInput() =>
    combine2<PressListCase, (bool, bool, int, int)>(
      pressList(maxLength: 20),
      combine4<bool, bool, int, int>(
        boolean(),
        boolean(),
        integer(min: 0, max: 1 << 20),
        integer(min: 1, max: 1000),
      ),
    ).map((r) {
      final (c, (corrupt, releaseFirst, position, amount)) = r;
      if (!corrupt) {
        return (
          debounceTime: c.debounceTime,
          presses: c.presses,
          corrupted: false,
        );
      }
      final presses = List<(int, int)>.of(c.presses);
      final n = presses.length;
      if (n == 0) {
        presses.add((0, -amount));
      } else if (releaseFirst || n == 1) {
        final i = position % n;
        final p = presses[i].$1;
        presses[i] = (p, p - amount);
      } else {
        final i = 1 + position % (n - 1);
        presses[i] = (presses[i - 1].$2 - amount, presses[i].$2);
      }
      return (debounceTime: c.debounceTime, presses: presses, corrupted: true);
    });

/// One Property 17 case: an input for each of the five components.
/// [debounce] for the Debouncer, [classify] for the Classifier, [calibrate]
/// for the Calibrator (its Calibration and Timing_Config also build the two
/// decoders, which may be rejected under REQ-TIMING-9), [batch] for the
/// Batch_Decoder (the valid original and the corrupted events are both
/// decoded), and [live] for the Live_Decoder. REQ-ENGINE-2.
typedef DeterminismInput = ({
  DebounceDeterminismCase debounce,
  (CalibrationInput, double, int) classify,
  RejectionInput calibrate,
  CorruptedInput batch,
  InvalidLiveScenario live,
});

/// The Property 17 generator: the generators of Properties 1, 7, 5, 14 and
/// 16 combined, so every component sees both valid and invalid input.
/// REQ-ENGINE-2.
Arbitrary<DeterminismInput> determinismInput() =>
    combine5<
          DebounceDeterminismCase,
          (CalibrationInput, double, int),
          RejectionInput,
          CorruptedInput,
          InvalidLiveScenario
        >(
          debounceDeterminismInput(),
          classificationInput(),
          rejectionInput(),
          corruptedInput(),
          invalidLiveScenario(),
        )
        .map(
          (r) => (
            debounce: r.$1,
            classify: r.$2,
            calibrate: r.$3,
            batch: r.$4,
            live: r.$5,
          ),
        );

/// The lowest in-range timestamp a Property 18 case uses, 1,000,000 µs. It
/// is far above every event index and Press count the generators reach, so
/// a timestamp in a message cannot pass for an index. REQ-ENGINE-5.
const int privacyTimestampFloor = 1000000;

/// Whether [t] lies within ±2^52. REQ-EVENT-1.
bool _inTimestampRange(int t) =>
    t >= -maxTimestampMagnitude && t <= maxTimestampMagnitude;

/// The amount that moves the lowest in-range value of [timestamps] to
/// [privacyTimestampFloor], or 0 when none is in range. REQ-ENGINE-5.
int _privacyShift(Iterable<int> timestamps) {
  int? low;
  for (final t in timestamps) {
    if (_inTimestampRange(t) && (low == null || t < low)) low = t;
  }
  return low == null ? 0 : privacyTimestampFloor - low;
}

/// [t] moved by [shift] when it is within ±2^52; a timestamp outside the
/// range is kept, so an out-of-range event stays out of range.
int _shifted(int t, int shift) => _inTimestampRange(t) ? t + shift : t;

/// A copy of [events] with every in-range timestamp moved by one amount so
/// the lowest is [privacyTimestampFloor]. Differences between in-range
/// timestamps, the kinds and the order are kept, and out-of-range
/// timestamps are left as they are. [events] is not changed. REQ-ENGINE-5.
List<EventRecord> shiftedForPrivacy(List<EventRecord> events) {
  final shift = _privacyShift([for (final (_, t) in events) t]);
  return <EventRecord>[
    for (final (isPress, t) in events) (isPress, _shifted(t, shift)),
  ];
}

/// One Property 18 Live_Decoder case: a valid Calibration and
/// Timing_Config, the valid [prefix] of calls and one [invalid] call built
/// to break [rule]. REQ-LIVE-9, REQ-ENGINE-5.
typedef PrivacyLiveCase = ({
  CalibrationRecord calibration,
  ConfigInput config,
  List<LiveCallRecord> prefix,
  InvalidLiveRule rule,
  LiveCallRecord invalid,
});

/// [s] cut to its valid prefix and moved, together with its invalid call,
/// so the lowest in-range timestamp is [privacyTimestampFloor]. The calls
/// after the cut are dropped. An out-of-range invalid timestamp is kept.
/// REQ-LIVE-9, REQ-ENGINE-5.
PrivacyLiveCase _shiftedLive(InvalidLiveScenario s) {
  final calls = <LiveCallRecord>[
    ...s.scenario.calls,
    if (s.scenario.finalAdvance != null)
      (kind: LiveCallKind.advance, timestamp: s.scenario.finalAdvance!),
  ];
  final prefix = calls.take(s.cut).toList();
  final shift = _privacyShift([
    for (final c in prefix) c.timestamp,
    s.invalid.timestamp,
  ]);
  return (
    calibration: s.scenario.calibration,
    config: s.scenario.config,
    prefix: <LiveCallRecord>[
      for (final c in prefix)
        (kind: c.kind, timestamp: _shifted(c.timestamp, shift)),
    ],
    rule: s.rule,
    invalid: (
      kind: s.invalid.kind,
      timestamp: _shifted(s.invalid.timestamp, shift),
    ),
  );
}

/// One Property 18 case: a Property 5 case for the Calibrator (its
/// Calibration and Timing_Config also build the two decoders, which may be
/// rejected under REQ-TIMING-9), a Property 14 case for the Batch_Decoder
/// and a Property 16 case for the Live_Decoder, each moved so every
/// in-range timestamp is at least [privacyTimestampFloor]. REQ-EVENT-4,
/// REQ-CAL-13, REQ-ENGINE-5.
typedef PrivacyInput = ({
  RejectionInput calibrate,
  CorruptedInput batch,
  PrivacyLiveCase live,
});

/// The Property 18 generator: the generators of Properties 5, 14 and 16,
/// each passed through [shiftedForPrivacy] or its live counterpart. A
/// shift is a map, not a filter, so every generated case counts.
/// REQ-EVENT-4, REQ-CAL-13, REQ-ENGINE-5.
Arbitrary<PrivacyInput> privacyInput() =>
    combine3<RejectionInput, CorruptedInput, InvalidLiveScenario>(
      rejectionInput(),
      corruptedInput(),
      invalidLiveScenario(),
    ).map((r) {
      final (cal, batch, live) = r;
      return (
        calibrate: (
          word: cal.word,
          calibration: cal.calibration,
          keying: (
            events: shiftedForPrivacy(cal.keying.events),
            perturbation: cal.keying.perturbation,
          ),
          config: cal.config,
        ),
        batch: (
          calibration: batch.calibration,
          config: batch.config,
          original: shiftedForPrivacy(batch.original),
          corrupted: (
            edits: batch.corrupted.edits,
            events: shiftedForPrivacy(batch.corrupted.events),
          ),
        ),
        live: _shiftedLive(live),
      );
    });
