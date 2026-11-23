import 'rejection_reason.dart';

/// A Calibration_Rejection: the reason a calibration attempt failed and an
/// English message for the user. REQ-CAL-13.
final class CalibrationRejection {
  /// Creates a Calibration_Rejection with [reason] and [message].
  /// REQ-CAL-13.
  const CalibrationRejection(this.reason, this.message);

  /// The Rejection_Reason that comes first in precedence order. REQ-CAL-12.
  final RejectionReason reason;

  /// Non-empty English text with no timestamp, measured duration or Symbol.
  /// REQ-CAL-13.
  final String message;

  /// Returns [message]. REQ-ENGINE-5.
  @override
  String toString() => message;
}
