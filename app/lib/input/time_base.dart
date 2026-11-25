/// Converts platform event and frame timestamps to the Key_Screen's single
/// Time_Base, in whole Microseconds. REQ-KEY-4.
library;

/// Converts a platform timestamp to Time_Base Microseconds. REQ-KEY-4.
///
/// Key events, pointer events and frames all pass their platform `Duration`
/// through one [TimeBase] so every Live_Decoder call shares one clock
/// (design D1, D3).
abstract interface class TimeBase {
  /// Returns [platformTimeStamp] as a whole number of Time_Base
  /// Microseconds. REQ-KEY-4.
  int stamp(Duration platformTimeStamp);
}

/// DOMHighResTimeStamp in µs (research R1). REQ-KEY-4.
///
/// On the web, `KeyEvent.timeStamp`, `PointerEvent.timeStamp` and
/// `SchedulerBinding.currentSystemFrameTimeStamp` share the browser's
/// `DOMHighResTimeStamp` origin, so converting each with
/// [Duration.inMicroseconds] yields one time base.
final class PlatformTimeBase implements TimeBase {
  /// Creates the production Time_Base. REQ-KEY-4.
  const PlatformTimeBase();

  /// Returns `d.inMicroseconds`. REQ-KEY-4.
  @override
  int stamp(Duration d) => d.inMicroseconds;
}
