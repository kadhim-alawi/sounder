/// Maps keyboard events to what they mean on the Key_Screen.
/// REQ-KEY-1, REQ-KEY-2, REQ-SPEAK-4.
library;

import 'package:flutter/services.dart';

/// What a key event means to the Key_Screen. REQ-KEY-1, REQ-KEY-2,
/// REQ-SPEAK-4.
///
/// Every value except [ignore] means the Key_Screen handles the event, so no
/// focused control activates and the browser performs no default action
/// (design D8).
enum KeyAction {
  /// Space key-down: one Live_Decoder `press` call. REQ-KEY-1.
  press,

  /// Space key-up: one Live_Decoder `release` call. REQ-KEY-1.
  release,

  /// Non-repeat Enter key-down: a Speak_Action. REQ-SPEAK-1.
  speak,

  /// Non-repeat Escape key-down: close the Fallback_View if it is shown.
  /// REQ-SPEAK-4.
  closeFallback,

  /// Handled with no call, such as a Repeat_Event or an Enter or Escape
  /// key-up. REQ-KEY-2.
  swallow,

  /// Not a Key_Screen key; left to the focus system (for example Tab).
  /// REQ-KEY-1.
  ignore,
}

/// Pure mapping, no state. REQ-KEY-1, REQ-KEY-2, REQ-SPEAK-4.
///
/// | Event            | Space   | Enter   | Escape        | Other  |
/// |------------------|---------|---------|---------------|--------|
/// | [KeyDownEvent]   | press   | speak   | closeFallback | ignore |
/// | [KeyUpEvent]     | release | swallow | swallow       | ignore |
/// | [KeyRepeatEvent] | swallow | swallow | swallow       | ignore |
///
/// Enter matches both [LogicalKeyboardKey.enter] and
/// [LogicalKeyboardKey.numpadEnter]. [KeyAction.closeFallback] is returned
/// whether or not the Fallback_View is shown; the caller decides. Any other
/// [KeyEvent] subtype for Space, Enter or Escape is [KeyAction.swallow], so it
/// makes no call.
KeyAction keyActionFor(KeyEvent event) {
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.space) {
    return switch (event) {
      KeyDownEvent() => KeyAction.press,
      KeyUpEvent() => KeyAction.release,
      _ => KeyAction.swallow,
    };
  }
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    return event is KeyDownEvent ? KeyAction.speak : KeyAction.swallow;
  }
  if (key == LogicalKeyboardKey.escape) {
    return event is KeyDownEvent ? KeyAction.closeFallback : KeyAction.swallow;
  }
  return KeyAction.ignore;
}
