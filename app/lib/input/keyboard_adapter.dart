/// Maps keyboard events to what they mean on the Key_Screen.
/// REQ-KEY-1, REQ-KEY-2, REQ-SPEAK-4, REQ-TOKENS-4, REQ-CHOICE-3,
/// REQ-NOTICE-2.
library;

import 'package:flutter/services.dart';

/// What a key event means to the Key_Screen. REQ-KEY-1, REQ-KEY-2,
/// REQ-SPEAK-4, REQ-TOKENS-4, REQ-CHOICE-3, REQ-NOTICE-2.
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

  /// Non-repeat ArrowDown key-down: an Expand_Action, or Send while the
  /// Expansion_Notice is shown (E18). REQ-TOKENS-4, REQ-NOTICE-2.
  expand,

  /// Non-repeat key-down of digit-row `1` or numpad `1`: choose Candidate 1
  /// (E24). REQ-CHOICE-3.
  choose1,

  /// Non-repeat key-down of digit-row `2` or numpad `2`: choose Candidate 2
  /// (E24). REQ-CHOICE-3.
  choose2,

  /// Non-repeat key-down of digit-row `3` or numpad `3`: choose Candidate 3
  /// (E24). REQ-CHOICE-3.
  choose3,

  /// Non-repeat key-down of digit-row `4` or numpad `4`: choose Candidate 4
  /// (E24). REQ-CHOICE-3.
  choose4,

  /// Handled with no call, such as a Repeat_Event or an Enter, Escape,
  /// ArrowDown or number key-up. REQ-KEY-2.
  swallow,

  /// Not a Key_Screen key; left to the focus system (for example Tab).
  /// REQ-KEY-1.
  ignore,
}

/// The choose action for number keys 1 to 4 on the digit row and the
/// numpad (E24), or null for any other key. REQ-CHOICE-3.
KeyAction? _chooseActionFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
    return KeyAction.choose1;
  }
  if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
    return KeyAction.choose2;
  }
  if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
    return KeyAction.choose3;
  }
  if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
    return KeyAction.choose4;
  }
  return null;
}

/// Pure mapping, no state. REQ-KEY-1, REQ-KEY-2, REQ-SPEAK-4, REQ-TOKENS-4,
/// REQ-CHOICE-3, REQ-NOTICE-2.
///
/// | Event            | Space   | Enter   | Escape        | ArrowDown | 1 to 4     | Other  |
/// |------------------|---------|---------|---------------|-----------|------------|--------|
/// | [KeyDownEvent]   | press   | speak   | closeFallback | expand    | choose1..4 | ignore |
/// | [KeyUpEvent]     | release | swallow | swallow       | swallow   | swallow    | ignore |
/// | [KeyRepeatEvent] | swallow | swallow | swallow       | swallow   | swallow    | ignore |
///
/// Enter matches both [LogicalKeyboardKey.enter] and
/// [LogicalKeyboardKey.numpadEnter]. "1 to 4" means
/// [LogicalKeyboardKey.digit1] to [LogicalKeyboardKey.digit4] and
/// [LogicalKeyboardKey.numpad1] to [LogicalKeyboardKey.numpad4] (E24); `1`
/// maps to [KeyAction.choose1] and so on. Other digits are
/// [KeyAction.ignore]. [KeyAction.closeFallback], [KeyAction.expand] and the
/// choose actions are returned whatever the screen shows; the caller decides.
/// Any other [KeyEvent] subtype for these keys is [KeyAction.swallow], so it
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
  if (key == LogicalKeyboardKey.arrowDown) {
    return event is KeyDownEvent ? KeyAction.expand : KeyAction.swallow;
  }
  final choose = _chooseActionFor(key);
  if (choose != null) {
    return event is KeyDownEvent ? choose : KeyAction.swallow;
  }
  return KeyAction.ignore;
}
