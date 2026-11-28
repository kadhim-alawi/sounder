import 'package:flutter/material.dart';

import 'sounder_button_style.dart';

/// The Candidate_List: one Candidate_Button per Candidate, numbered 1 to 4
/// in list order. Each button shows its number and the full Candidate text
/// at 32 logical pixels, wrapping with no truncation, is at least 64 by 64
/// logical pixels, and has the semantic label `n. text`. Buttons use the
/// shared Sounder style (no splash, overlay or animation). The widget only
/// reports which button was activated; the Key_Screen decides what to speak.
/// Lay it out with a bounded width, as it stretches its buttons to fill it.
/// REQ-CHOICE-2, REQ-CHOICE-3, REQ-A11Y-3, REQ-A11Y-4, REQ-KEY-12.
class CandidateList extends StatelessWidget {
  /// Creates the Candidate_List for [candidates]. REQ-CHOICE-2.
  const CandidateList({
    super.key,
    required this.candidates,
    required this.onChoose,
  });

  /// The Candidates to show, 0 to 4, in list order. REQ-CHOICE-1.
  final List<String> candidates;

  /// Called with the 1-based number of the activated Candidate_Button.
  /// REQ-CHOICE-3.
  final ValueChanged<int> onChoose;

  @override
  Widget build(BuildContext context) {
    final style = sounderButtonStyle().copyWith(
      alignment: Alignment.centerLeft,
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 32)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < candidates.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          FilledButton(
            style: style,
            onPressed: () => onChoose(i + 1),
            child: Semantics(
              label: '${i + 1}. ${candidates[i]}',
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${i + 1}'),
                  const SizedBox(width: 16),
                  Expanded(child: Text(candidates[i], softWrap: true)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
