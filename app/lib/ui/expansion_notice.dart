import 'package:flutter/material.dart';

import 'sounder_button_style.dart';
import 'sounder_colors.dart';

/// The exact Expansion_Notice text. It promises only what Sounder does
/// (requirements S5). REQ-NOTICE-1.
const String expansionNoticeText =
    'Expand sends the letters you typed to Cloudflare Workers AI to suggest '
    'sentences. Sounder stores nothing.';

/// The one-time Expansion_Notice: an inline panel (no route, no modal
/// barrier) with [expansionNoticeText] at 24 px and `Send` and `Cancel`
/// buttons. It never closes by itself; only [onSend] and [onCancel] (or the
/// Key_Screen's ArrowDown and Escape handling, E18) close it.
/// REQ-NOTICE-1, REQ-NOTICE-2, REQ-NOTICE-3, REQ-A11Y-2, REQ-KEY-12.
class ExpansionNotice extends StatelessWidget {
  /// Creates the Expansion_Notice. REQ-NOTICE-1.
  const ExpansionNotice({
    super.key,
    required this.onSend,
    required this.onCancel,
  });

  /// Called when Send is activated. REQ-NOTICE-2.
  final VoidCallback onSend;

  /// Called when Cancel is activated. REQ-NOTICE-3.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final style = sounderButtonStyle();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          expansionNoticeText,
          softWrap: true,
          style: TextStyle(color: SounderColors.text, fontSize: 24),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            FilledButton(
              style: style,
              onPressed: onSend,
              child: const Text('Send'),
            ),
            FilledButton(
              style: style,
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}
