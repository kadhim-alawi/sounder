/// Tracks which pointer pressed the On_Screen_Key so only that pointer
/// releases it. REQ-KEY-3, REQ-KEY-7.
library;

/// Tracks the one pointer that pressed the On_Screen_Key. REQ-KEY-3,
/// REQ-KEY-7.
///
/// Every pointer down makes a press call. A down from a second pointer while
/// one is tracked still makes the call, so the Live_Decoder rejects it as two
/// presses in a row (REQ-KEY-7, K3), but the tracked pointer does not change.
/// Only the tracked pointer's up or cancel makes a release call (REQ-KEY-3).
final class PointerAdapter {
  /// Creates an adapter with no tracked pointer. REQ-KEY-3.
  PointerAdapter();

  int? _active;

  /// Handles a pointer down and returns true, meaning a press call should be
  /// made. Tracks [pointer] only when no pointer is tracked. REQ-KEY-3,
  /// REQ-KEY-7.
  bool down(int pointer) {
    _active ??= pointer;
    return true;
  }

  /// Handles a pointer up or cancel. Returns true, and stops tracking, only
  /// when [pointer] is the tracked pointer, meaning a release call should be
  /// made. REQ-KEY-3, REQ-KEY-7.
  bool end(int pointer) {
    if (_active != pointer) return false;
    _active = null;
    return true;
  }
}
