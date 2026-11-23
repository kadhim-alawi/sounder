import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

void main() {
  group('RejectionReason', () {
    test('REQ-CAL-12 values are in precedence order', () {
      expect(RejectionReason.values, [
        RejectionReason.unsuitableWord,
        RejectionReason.invalidEvents,
        RejectionReason.wrongPressCount,
        RejectionReason.pressesOverlap,
        RejectionReason.gapsOverlap,
        RejectionReason.zeroDuration,
        RejectionReason.durationTooLong,
      ]);
    });
  });

  group('CalibrationRejection', () {
    test('REQ-CAL-13 keeps reason and message; toString returns message', () {
      const rejection = CalibrationRejection(
        RejectionReason.gapsOverlap,
        'Pauses inside letters and between letters could not be told apart.',
      );
      expect(rejection.reason, RejectionReason.gapsOverlap);
      expect(rejection.toString(), rejection.message);
    });
  });

  group('CalibrationResult', () {
    test('REQ-CAL-31 accepted carries only a Calibration', () {
      final calibration = Calibration(
        ditLength: 100000,
        dahLength: 300000,
        symbolGap: 250000,
        letterGap: 700000,
      );
      final result = CalibrationResult.accepted(calibration);
      expect(result.isAccepted, isTrue);
      expect(result.calibration, same(calibration));
      expect(result.rejection, isNull);
    });

    test('REQ-CAL-31 rejected carries only a CalibrationRejection', () {
      const rejection = CalibrationRejection(
        RejectionReason.zeroDuration,
        'A press or pause was too short to measure.',
      );
      const result = CalibrationResult.rejected(rejection);
      expect(result.isAccepted, isFalse);
      expect(result.rejection, same(rejection));
      expect(result.calibration, isNull);
    });
  });
}
