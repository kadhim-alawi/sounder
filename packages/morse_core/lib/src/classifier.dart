import 'calibration.dart';
import 'gap_class.dart';
import 'morse_symbol.dart';
import 'timing_config.dart';
import 'timing_input_error_kind.dart';
import 'timing_input_exception.dart';

/// Classifies Press and Gap durations against whole-Microsecond thresholds
/// derived from a Calibration and a Timing_Config. REQ-TIMING-1.
final class Classifier {
  /// Creates a Classifier and computes the three thresholds once, from
  /// [calibration] and the Word_Gap_Factor of [config] only. Never throws for
  /// a valid Calibration and Timing_Config. REQ-TIMING-1, REQ-TIMING-2,
  /// REQ-DEBOUNCE-2.
  Classifier(this.calibration, this.config)
    : pressThreshold = _midpointUp(
        calibration.ditLength,
        calibration.dahLength,
      ),
      letterGapThreshold = _midpointUp(
        calibration.symbolGap,
        calibration.letterGap,
      ),
      wordGapThreshold = _wordGapThreshold(
        config.wordGapFactor,
        calibration.letterGap,
      );

  /// The Calibration the thresholds come from. REQ-TIMING-1.
  final Calibration calibration;

  /// The Timing_Config that supplies the Word_Gap_Factor. REQ-TIMING-1,
  /// REQ-DEBOUNCE-2.
  final TimingConfig config;

  /// Press_Threshold, ⌈(Dit_Length + Dah_Length) / 2⌉. A Press at or above
  /// it is a dah. REQ-TIMING-1, REQ-TIMING-3.
  final int pressThreshold;

  /// Letter_Gap_Threshold, ⌈(Symbol_Gap + Letter_Gap) / 2⌉. A Gap at or
  /// above it ends a letter. REQ-TIMING-1, REQ-TIMING-4.
  final int letterGapThreshold;

  /// Word_Gap_Threshold, the smallest whole number greater than Letter_Gap
  /// and not less than Word_Gap_Factor × Letter_Gap. A Gap at or above it
  /// ends a word. REQ-TIMING-1, REQ-TIMING-4.
  final int wordGapThreshold;

  /// Returns [MorseSymbol.dit] when [duration] is shorter than
  /// [pressThreshold], otherwise [MorseSymbol.dah].
  ///
  /// Throws a [TimingInputException] of kind
  /// [TimingInputErrorKind.negativeDuration], with no index, for a negative
  /// [duration]. REQ-TIMING-3, REQ-TIMING-11.
  MorseSymbol classifyPress(int duration) {
    _checkDuration(duration);
    return duration < pressThreshold ? MorseSymbol.dit : MorseSymbol.dah;
  }

  /// Returns [GapClass.insideLetter] when [duration] is shorter than
  /// [letterGapThreshold], [GapClass.betweenLetters] when it is shorter than
  /// [wordGapThreshold], otherwise [GapClass.betweenWords].
  ///
  /// Throws a [TimingInputException] of kind
  /// [TimingInputErrorKind.negativeDuration], with no index, for a negative
  /// [duration]. REQ-TIMING-4, REQ-TIMING-11.
  GapClass classifyGap(int duration) {
    _checkDuration(duration);
    if (duration < letterGapThreshold) return GapClass.insideLetter;
    if (duration < wordGapThreshold) return GapClass.betweenLetters;
    return GapClass.betweenWords;
  }

  // REQ-TIMING-11.
  static void _checkDuration(int duration) {
    if (duration < 0) {
      throw TimingInputException(TimingInputErrorKind.negativeDuration);
    }
  }

  // ⌈(a + b) / 2⌉ for a < b, without computing a + b, so it stays exact on
  // the web build. REQ-TIMING-1.
  static int _midpointUp(int a, int b) => a + (b - a + 1) ~/ 2;

  // Exact max(⌈factor × letterGap⌉, letterGap + 1) (Decision T8). Doubling a
  // finite double greater than 1 is exact and reaches a whole number within
  // 52 steps, so factor = m / 2^k exactly. REQ-TIMING-1, REQ-TIMING-2.
  static int _wordGapThreshold(double factor, int letterGap) {
    var m = factor;
    var k = 0;
    while (m != m.truncateToDouble()) {
      m *= 2;
      k++;
    }
    final numerator = BigInt.from(m) * BigInt.from(letterGap);
    final denominator = BigInt.one << k;
    final w0 = (numerator + denominator - BigInt.one) ~/ denominator;
    final floor = BigInt.from(letterGap) + BigInt.one;
    return (w0 > floor ? w0 : floor).toInt();
  }
}
