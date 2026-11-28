import 'package:flutter/material.dart';

import 'sounder_colors.dart';

/// The Failure_Message text. REQ-FAIL-1.
const String failureMessageText =
    'No suggestions. Add letters or speak what you typed.';

/// The Failure_Message: static 24 px text in a live region, so screen
/// readers announce it once when it appears. It has no timer; the
/// Key_Screen removes it only when the Sentence changes or on the next
/// Expand_Action (E22). REQ-FAIL-1, REQ-FAIL-2, REQ-KEY-12.
class FailureMessage extends StatelessWidget {
  /// Creates the Failure_Message. REQ-FAIL-1.
  const FailureMessage({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: const Text(
        failureMessageText,
        softWrap: true,
        style: TextStyle(color: SounderColors.text, fontSize: 24),
      ),
    );
  }
}
