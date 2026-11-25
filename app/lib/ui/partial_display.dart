import 'package:flutter/widgets.dart';

import '../compose/sentence_text.dart';
import 'sounder_colors.dart';

/// Shows the Partial_Sequence at 36 logical pixels as `·` for each dit and
/// `–` for each dah, in keyed order, wrapping with nothing cut off; empty
/// when the Partial_Sequence is empty. Semantics: label "Current letter"
/// with the glyphs as value, or label "Current letter is empty".
/// REQ-KEY-9, REQ-KEY-10, REQ-A11Y-1, REQ-A11Y-3, REQ-A11Y-5.
class PartialDisplay extends StatelessWidget {
  /// Creates the Partial_Sequence display. REQ-KEY-10.
  const PartialDisplay({super.key, required this.partialSequence});

  /// The display font size in logical pixels (at least 32). REQ-KEY-9.
  static const double fontSize = 36;

  /// The Live_Decoder Partial_Sequence as `.` and `-`. REQ-KEY-10.
  final String partialSequence;

  @override
  Widget build(BuildContext context) {
    final text = partialGlyphs(partialSequence);
    return Semantics(
      container: true,
      label: text.isEmpty ? 'Current letter is empty' : 'Current letter',
      value: text.isEmpty ? null : text,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        child: Text(
          text,
          softWrap: true,
          style: const TextStyle(
            color: SounderColors.text,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }
}
