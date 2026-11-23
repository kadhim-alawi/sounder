import 'timing_input_error_kind.dart';
import 'timing_input_exception.dart';

/// The Timing_Config: Debounce_Time and Word_Gap_Factor.
///
/// This is the only place the default values appear; every other Timing_Engine
/// component reads them from the Timing_Config it is given. REQ-DEBOUNCE-1,
/// REQ-DEBOUNCE-2.
final class TimingConfig {
  /// Creates a Timing_Config. Each field left out takes its default; each
  /// supplied field is stored unchanged.
  ///
  /// Throws a [TimingInputException] of kind
  /// [TimingInputErrorKind.invalidDebounceTime] when [debounceTime] is
  /// negative. Otherwise throws kind
  /// [TimingInputErrorKind.invalidWordGapFactor] when [wordGapFactor] is NaN,
  /// infinite, at most 1.0 or greater than 1,000. REQ-DEBOUNCE-1,
  /// REQ-DEBOUNCE-3, REQ-DEBOUNCE-14.
  TimingConfig({
    this.debounceTime = defaultDebounceTime,
    this.wordGapFactor = defaultWordGapFactor,
  }) {
    if (debounceTime < 0) {
      throw TimingInputException(TimingInputErrorKind.invalidDebounceTime);
    }
    // NaN fails both comparisons, so test the valid range and negate it.
    final factorInRange =
        wordGapFactor > 1.0 && wordGapFactor <= _maxWordGapFactor;
    if (!factorInRange) {
      throw TimingInputException(TimingInputErrorKind.invalidWordGapFactor);
    }
  }

  /// Default Debounce_Time: 30,000 Microseconds. REQ-DEBOUNCE-1,
  /// REQ-DEBOUNCE-2.
  static const int defaultDebounceTime = 30000;

  /// Default Word_Gap_Factor: 2.0. REQ-DEBOUNCE-1, REQ-DEBOUNCE-2.
  static const double defaultWordGapFactor = 2.0;

  /// A Timing_Config with both defaults. REQ-DEBOUNCE-1.
  static final TimingConfig defaults = TimingConfig();

  // Largest valid Word_Gap_Factor (B17). Infinity is above it. REQ-DEBOUNCE-3.
  static const double _maxWordGapFactor = 1000.0;

  /// The Debounce_Time in Microseconds, zero or more. REQ-DEBOUNCE-1.
  final int debounceTime;

  /// The Word_Gap_Factor, finite, greater than 1.0 and at most 1,000.
  /// REQ-DEBOUNCE-1, REQ-DEBOUNCE-3.
  final double wordGapFactor;
}
