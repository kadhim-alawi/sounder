import 'package:flutter/material.dart';
import 'package:morse_core/morse_core.dart';

import '../ui/sentence_display.dart';
import '../ui/sounder_button_style.dart';
import '../ui/sounder_colors.dart';

/// The full-screen view shown after a Speech_Failure: a notice that speech
/// failed, the Sentence text (Placeholders included) at 36 logical pixels,
/// or the chosen Candidate's text at 36 logical pixels when speaking a
/// Candidate failed (E21), and a labelled Close button at least 64 by 64.
/// It never closes by itself; only [onClose] (or the Key_Screen's Escape
/// and successful Speak handling) hides it. REQ-SPEAK-3, REQ-A11Y-1,
/// REQ-A11Y-2, REQ-A11Y-3, REQ-A11Y-4, REQ-A11Y-5, REQ-KEY-12, REQ-CHOICE-5.
class FallbackView extends StatelessWidget {
  /// Creates the Fallback_View. REQ-SPEAK-3, REQ-CHOICE-5.
  const FallbackView({
    super.key,
    required this.sentence,
    required this.onClose,
    this.candidateText,
  });

  /// The notice text shown above the Sentence. REQ-SPEAK-3, REQ-A11Y-5.
  static const String notice = 'Speech failed. Show this text instead.';

  /// The Sentence to show, oldest item first, when [candidateText] is
  /// `null`. REQ-SPEAK-3.
  final List<DecodedItem> sentence;

  /// The chosen Candidate's text to show in place of the Sentence, or
  /// `null` to show the Sentence. REQ-CHOICE-5.
  final String? candidateText;

  /// Called when the Close control is activated. REQ-SPEAK-3.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      child: Material(
        color: SounderColors.screenBackground,
        child: SafeArea(
          child: SizedBox.expand(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: const Text(
                      notice,
                      softWrap: true,
                      style: TextStyle(color: SounderColors.text, fontSize: 24),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (candidateText case final text?)
                    Text(
                      text,
                      softWrap: true,
                      style: const TextStyle(
                        color: SounderColors.text,
                        fontSize: 36,
                      ),
                    )
                  else
                    SentenceDisplay(sentence: sentence),
                  const SizedBox(height: 24),
                  FilledButton(
                    style: sounderButtonStyle(),
                    onPressed: onClose,
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
