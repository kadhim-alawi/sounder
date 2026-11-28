import 'package:morse_core/morse_core.dart';

/// Most words a Token_List may hold. REQ-TOKENS-2.
const int maxTokenWords = 12;

/// Most letters a Token may hold. REQ-TOKENS-2.
const int maxTokenLetters = 8;

/// The result of building the Sentence_Tokens from the Sentence: empty,
/// blocked for one reason, or ready with a Token_List. Pure Dart.
/// REQ-TOKENS-1, REQ-TOKENS-2, REQ-COMPOSE-1.
sealed class TokensCheck {
  /// Base constructor. REQ-TOKENS-2.
  const TokensCheck();
}

/// The Sentence has no words: Expand is disabled and no Tokens_Message is
/// shown (E17). REQ-TOKENS-2.
final class TokensEmpty extends TokensCheck {
  /// The empty check. REQ-TOKENS-2.
  const TokensEmpty();
}

/// Why Expand is not offered for a non-empty Sentence, in the order the
/// reasons are checked. REQ-TOKENS-2, REQ-TOKENS-3.
enum TokensBlock {
  /// A word holds a non-letter: an Unknown_Letter_Item, a digit or a
  /// punctuation character (E16). REQ-TOKENS-2, REQ-TOKENS-3.
  nonLetter,

  /// The Sentence has more than [maxTokenWords] words. REQ-TOKENS-2,
  /// REQ-TOKENS-3.
  tooManyWords,

  /// A word has more than [maxTokenLetters] letters. REQ-TOKENS-2,
  /// REQ-TOKENS-3.
  wordTooLong,
}

/// The Sentence is non-empty but Expand is disabled for [reason].
/// REQ-TOKENS-2, REQ-TOKENS-3.
final class TokensBlocked extends TokensCheck {
  /// A blocked check for [reason]. REQ-TOKENS-2.
  const TokensBlocked(this.reason);

  /// The first failing reason, in [TokensBlock] order. REQ-TOKENS-3.
  final TokensBlock reason;
}

/// Expand is offered with [tokens], the Sentence_Tokens. REQ-TOKENS-1.
final class TokensReady extends TokensCheck {
  /// A ready check for [tokens]. REQ-TOKENS-1.
  const TokensReady(this.tokens);

  /// The words of the Sentence in order, each 1 to [maxTokenLetters] ASCII
  /// letters, 1 to [maxTokenWords] of them. Unmodifiable. REQ-TOKENS-1.
  final List<String> tokens;
}

/// Builds the Sentence_Tokens from [items]. A word is a maximal run of
/// non-Word_Space items, so leading, trailing and repeated Word_Spaces make
/// no empty words (E16). No words gives [TokensEmpty]. Otherwise the checks
/// run in order: any non-letter (an Unknown_Letter_Item, or a Letter_Item
/// that is not one ASCII letter, E1), then more than [maxTokenWords] words,
/// then a word over [maxTokenLetters] letters. Pure Dart. REQ-TOKENS-1,
/// REQ-TOKENS-2, REQ-TOKENS-3, REQ-COMPOSE-1.
TokensCheck sentenceTokens(List<DecodedItem> items) {
  final words = <String>[];
  final word = StringBuffer();
  var hasNonLetter = false;
  var inWord = false;
  for (final item in items) {
    switch (item.kind) {
      case DecodedItemKind.wordSpace:
        if (inWord) {
          words.add(word.toString());
          word.clear();
          inWord = false;
        }
      case DecodedItemKind.unknownLetter:
        inWord = true;
        hasNonLetter = true;
      case DecodedItemKind.letter:
        inWord = true;
        final character = item.character!;
        if (_isAsciiLetter(character)) {
          word.write(character);
        } else {
          hasNonLetter = true;
        }
    }
  }
  if (inWord) {
    words.add(word.toString());
  }

  if (words.isEmpty) {
    return const TokensEmpty();
  }
  if (hasNonLetter) {
    return const TokensBlocked(TokensBlock.nonLetter);
  }
  if (words.length > maxTokenWords) {
    return const TokensBlocked(TokensBlock.tooManyWords);
  }
  if (words.any((w) => w.length > maxTokenLetters)) {
    return const TokensBlocked(TokensBlock.wordTooLong);
  }
  return TokensReady(List.unmodifiable(words));
}

/// The Tokens_Message for [check]: one exact message per [TokensBlock]
/// reason, and null for [TokensEmpty] and [TokensReady] (E17).
/// REQ-TOKENS-3.
String? tokensMessageFor(TokensCheck check) => switch (check) {
      TokensBlocked(reason: TokensBlock.nonLetter) =>
        'Expand needs letters only.',
      TokensBlocked(reason: TokensBlock.tooManyWords) =>
        'Expand takes up to 12 words.',
      TokensBlocked(reason: TokensBlock.wordTooLong) =>
        'Expand takes up to 8 letters a word.',
      TokensEmpty() || TokensReady() => null,
    };

/// True when [s] is exactly one ASCII letter, A-Z or a-z (E1).
/// REQ-TOKENS-2.
bool _isAsciiLetter(String s) {
  if (s.length != 1) return false;
  final c = s.codeUnitAt(0);
  return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
}
