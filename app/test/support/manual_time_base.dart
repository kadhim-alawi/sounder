/// A test-controlled Time_Base for widget tests. REQ-KEY-4, REQ-CI-2.
library;

import 'package:sounder/input/time_base.dart';

/// A [TimeBase] whose value the test sets (design D3). REQ-KEY-4, REQ-CI-2.
///
/// Widget-test key and pointer events carry `Duration.zero` time stamps, so
/// [stamp] ignores its argument and returns [now].
final class ManualTimeBase implements TimeBase {
  /// Creates a clock that starts at [now] Microseconds. REQ-CI-2.
  ManualTimeBase([this.now = 0]);

  /// The current Time_Base value in Microseconds, set by the test. REQ-CI-2.
  int now;

  /// Returns [now] and ignores [platformTimeStamp]. REQ-KEY-4, REQ-CI-2.
  @override
  int stamp(Duration platformTimeStamp) => now;
}
