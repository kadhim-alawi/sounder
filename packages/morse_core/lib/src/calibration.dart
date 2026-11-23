import 'timing_input_error_kind.dart';
import 'timing_input_exception.dart';

/// A Calibration: the four calibrated durations in Microseconds.
/// REQ-CAL-6, REQ-CAL-14.
final class Calibration {
  /// Creates a Calibration.
  ///
  /// Throws a [TimingInputException] naming the first invalid field, in the
  /// order Dit_Length, Dah_Length, Symbol_Gap, Letter_Gap. A value is invalid
  /// when it is 0 or less or greater than 2^40; Dah_Length is also invalid
  /// when it is at most Dit_Length, and Letter_Gap when it is at most
  /// Symbol_Gap. REQ-CAL-14.
  Calibration({
    required this.ditLength,
    required this.dahLength,
    required this.symbolGap,
    required this.letterGap,
  }) {
    if (!_inRange(ditLength)) {
      throw TimingInputException(TimingInputErrorKind.invalidDitLength);
    }
    if (!_inRange(dahLength) || dahLength <= ditLength) {
      throw TimingInputException(TimingInputErrorKind.invalidDahLength);
    }
    if (!_inRange(symbolGap)) {
      throw TimingInputException(TimingInputErrorKind.invalidSymbolGap);
    }
    if (!_inRange(letterGap) || letterGap <= symbolGap) {
      throw TimingInputException(TimingInputErrorKind.invalidLetterGap);
    }
  }

  // Largest valid duration, 2^40 Microseconds (B17). REQ-CAL-14.
  static const int _maxDuration = 1099511627776;

  static bool _inRange(int value) => value > 0 && value <= _maxDuration;

  /// The calibrated duration of a dit Press. REQ-CAL-6.
  final int ditLength;

  /// The calibrated duration of a dah Press. REQ-CAL-6.
  final int dahLength;

  /// The calibrated Gap inside a letter. REQ-CAL-6.
  final int symbolGap;

  /// The calibrated Gap between letters. REQ-CAL-6.
  final int letterGap;

  /// Value equality on all four durations. REQ-CAL-15.
  @override
  bool operator ==(Object other) =>
      other is Calibration &&
      other.ditLength == ditLength &&
      other.dahLength == dahLength &&
      other.symbolGap == symbolGap &&
      other.letterGap == letterGap;

  /// Hash consistent with `==`. REQ-CAL-15.
  @override
  int get hashCode => Object.hash(ditLength, dahLength, symbolGap, letterGap);
}
