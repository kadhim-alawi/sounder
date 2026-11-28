import 'package:flutter/material.dart';

import 'sounder_colors.dart';

/// The Thinking_Indicator: the static text `Thinking…` (ending in U+2026)
/// in a live region, so screen readers announce it once when it appears.
/// No spinner and no animation: nothing on screen moves by itself.
/// REQ-WAIT-1, REQ-KEY-12.
class ThinkingIndicator extends StatelessWidget {
  /// Creates the Thinking_Indicator. REQ-WAIT-1.
  const ThinkingIndicator({super.key});

  /// The exact indicator text. REQ-WAIT-1.
  static const String text = 'Thinking\u2026';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: const Text(
        text,
        style: TextStyle(color: SounderColors.text, fontSize: 24),
      ),
    );
  }
}
