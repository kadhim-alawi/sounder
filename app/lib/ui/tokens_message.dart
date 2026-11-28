import 'package:flutter/material.dart';

import '../compose/sentence_tokens.dart';
import 'sounder_colors.dart';

/// The Tokens_Message line: why Expand is not offered for a non-empty
/// Sentence, as static 24 px text. Shows nothing for an empty Sentence or
/// when Expand is offered (E17). It never closes on a timer; it changes only
/// when [check] changes (E22). REQ-TOKENS-3, REQ-KEY-12.
class TokensMessage extends StatelessWidget {
  /// Creates the Tokens_Message for [check]. REQ-TOKENS-3.
  const TokensMessage({super.key, required this.check});

  /// The Sentence_Tokens check of the current Sentence. REQ-TOKENS-2,
  /// REQ-TOKENS-3.
  final TokensCheck check;

  @override
  Widget build(BuildContext context) {
    final message = tokensMessageFor(check);
    if (message == null) return const SizedBox.shrink();
    return Text(
      message,
      softWrap: true,
      style: const TextStyle(color: SounderColors.text, fontSize: 24),
    );
  }
}
