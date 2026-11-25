import 'package:flutter/material.dart';

import 'sounder_colors.dart';

/// The style shared by the Speak, Undo, Clear and Close buttons: at least
/// 64 by 64 logical pixels, white text on the released background, no
/// splash, no hover or press overlay and no animation (design D9). A white
/// outline appears only while the button has keyboard focus, so a user who
/// moves focus with Tab can see where it is. REQ-A11Y-2, REQ-A11Y-3,
/// REQ-KEY-12.
ButtonStyle sounderButtonStyle() => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(64, 64)),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  ),
  backgroundColor: const WidgetStatePropertyAll(SounderColors.released),
  foregroundColor: const WidgetStatePropertyAll(SounderColors.text),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  shadowColor: const WidgetStatePropertyAll(Colors.transparent),
  elevation: const WidgetStatePropertyAll(0),
  splashFactory: NoSplash.splashFactory,
  animationDuration: Duration.zero,
  textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 24)),
  side: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? const BorderSide(color: SounderColors.text, width: 3)
        : const BorderSide(color: SounderColors.text, width: 1),
  ),
);
