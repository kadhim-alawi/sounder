import 'package:flutter/material.dart';

import 'sounder_button_style.dart';

/// The Speak, Undo and Clear buttons in a `Wrap`, so they move onto a new
/// line instead of overflowing at narrow widths. Each is at least 64 by 64
/// logical pixels and labelled with its action, with no splash, overlay or
/// animation (design D9). REQ-COMPOSE-3, REQ-COMPOSE-4, REQ-COMPOSE-5,
/// REQ-A11Y-1, REQ-A11Y-2, REQ-A11Y-4, REQ-KEY-12.
class ActionBar extends StatelessWidget {
  /// Creates the action bar. REQ-COMPOSE-5.
  const ActionBar({
    super.key,
    required this.onSpeak,
    required this.onUndo,
    required this.onClear,
  });

  /// Called when Speak is activated (a Speak_Action). REQ-SPEAK-1.
  final VoidCallback onSpeak;

  /// Called when Undo is activated. REQ-COMPOSE-3.
  final VoidCallback onUndo;

  /// Called when Clear is activated. REQ-COMPOSE-4.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final style = sounderButtonStyle();
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        FilledButton(
          style: style,
          onPressed: onSpeak,
          child: const Text('Speak'),
        ),
        FilledButton(
          style: style,
          onPressed: onUndo,
          child: const Text('Undo'),
        ),
        FilledButton(
          style: style,
          onPressed: onClear,
          child: const Text('Clear'),
        ),
      ],
    );
  }
}
