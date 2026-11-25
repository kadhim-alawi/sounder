import 'package:flutter/widgets.dart';
import 'package:morse_core/morse_core.dart';

import '../compose/sentence_text.dart';
import 'sounder_colors.dart';

/// Shows the Sentence text at 36 logical pixels, wrapping onto further
/// lines with nothing truncated, clipped or elided. An Unknown_Letter_Item
/// shows as the Placeholder. Semantics: label "Sentence" with the text as
/// value, or label "Sentence is empty" when there is no text.
/// REQ-KEY-9, REQ-KEY-10, REQ-KEY-11, REQ-A11Y-1, REQ-A11Y-3, REQ-A11Y-4,
/// REQ-A11Y-5, REQ-SPEAK-3.
class SentenceDisplay extends StatelessWidget {
  /// Creates the Sentence display. REQ-KEY-9.
  const SentenceDisplay({super.key, required this.sentence});

  /// The display font size in logical pixels (at least 32). REQ-KEY-9.
  static const double fontSize = 36;

  /// The Decoded_Items of the Sentence, oldest first. REQ-KEY-10.
  final List<DecodedItem> sentence;

  @override
  Widget build(BuildContext context) {
    final text = sentenceText(sentence);
    return Semantics(
      container: true,
      label: text.isEmpty ? 'Sentence is empty' : 'Sentence',
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
