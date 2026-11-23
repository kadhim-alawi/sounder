/// Why the Calibrator rejected a calibration attempt, listed in precedence
/// order: when several apply, the first one listed is reported (REQ-CAL-12).
/// REQ-CAL-3.
enum RejectionReason {
  /// The Calibration_Word cannot be used for calibration. REQ-CAL-3.
  unsuitableWord,

  /// The Event_Sequence is not a Valid_Event_Sequence. REQ-CAL-11.
  invalidEvents,

  /// The number of Presses differs from the Calibration_Word's plan.
  /// REQ-CAL-8.
  wrongPressCount,

  /// Dit Presses and dah Presses could not be told apart. REQ-CAL-9.
  pressesOverlap,

  /// Gaps inside letters and Gaps between letters could not be told apart.
  /// REQ-CAL-10.
  gapsOverlap,

  /// A press or pause was too short to measure. REQ-CAL-30.
  zeroDuration,

  /// A press or pause was longer than a Calibration can hold (2^40
  /// Microseconds). REQ-CAL-12, REQ-CAL-31.
  durationTooLong,
}
