import 'calibration.dart';
import 'calibration_rejection.dart';

/// The outcome of a calibration attempt: exactly one of [calibration] and
/// [rejection] is non-null. REQ-CAL-31.
final class CalibrationResult {
  /// An accepted result carrying [calibration] and no rejection. REQ-CAL-31.
  const CalibrationResult.accepted(Calibration this.calibration)
    : rejection = null;

  /// A rejected result carrying [rejection] and no partial Calibration.
  /// REQ-CAL-31.
  const CalibrationResult.rejected(CalibrationRejection this.rejection)
    : calibration = null;

  /// The measured Calibration, or null when rejected. REQ-CAL-6.
  final Calibration? calibration;

  /// The Calibration_Rejection, or null when accepted. REQ-CAL-12.
  final CalibrationRejection? rejection;

  /// True when [calibration] is non-null. REQ-CAL-31.
  bool get isAccepted => calibration != null;
}
