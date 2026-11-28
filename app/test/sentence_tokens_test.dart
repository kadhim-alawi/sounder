import 'package:flutter_test/flutter_test.dart';
import 'package:morse_core/morse_core.dart';
import 'package:sounder/compose/sentence_tokens.dart';

const _unknown = DecodedItem.unknownLetter('........-');
const _space = DecodedItem.wordSpace();

List<DecodedItem> _letters(String word) =>
    [for (final c in word.split('')) DecodedItem.letter(c)];

List<DecodedItem> _sentence(List<String> words) => [
      for (final (i, w) in words.indexed) ...[
        if (i > 0) _space,
        ..._letters(w),
      ],
    ];

void main() {
  group('sentenceTokens', () {
    test('REQ-TOKENS-2: an empty or all-space Sentence is TokensEmpty', () {
      expect(sentenceTokens(const []), isA<TokensEmpty>());
      expect(sentenceTokens(const [_space, _space]), isA<TokensEmpty>());
      expect(tokensMessageFor(sentenceTokens(const [])), isNull);
    });

    test('REQ-TOKENS-1: words split on runs of Word_Spaces, in order', () {
      final items = [
        _space,
        ..._letters('I'),
        _space,
        _space,
        ..._letters('WANT'),
        _space,
      ];
      final check = sentenceTokens(items);
      expect(check, isA<TokensReady>());
      expect((check as TokensReady).tokens, ['I', 'WANT']);
      expect(tokensMessageFor(check), isNull);
    });

    test('REQ-TOKENS-3: a Placeholder or a digit blocks as nonLetter', () {
      final withUnknown = [..._letters('HI'), _unknown];
      final withDigit = _sentence(['A', '5']);
      for (final items in [withUnknown, withDigit]) {
        final check = sentenceTokens(items);
        expect((check as TokensBlocked).reason, TokensBlock.nonLetter);
        expect(tokensMessageFor(check), 'Expand needs letters only.');
      }
    });

    test('REQ-TOKENS-3: 13 words blocks as tooManyWords; 12 is ready', () {
      expect(sentenceTokens(_sentence(List.filled(12, 'A'))),
          isA<TokensReady>());
      final check = sentenceTokens(_sentence(List.filled(13, 'A')));
      expect((check as TokensBlocked).reason, TokensBlock.tooManyWords);
      expect(tokensMessageFor(check), 'Expand takes up to 12 words.');
    });

    test('REQ-TOKENS-3: a 9-letter word blocks as wordTooLong; 8 is ready',
        () {
      expect(sentenceTokens(_letters('ABCDEFGH')), isA<TokensReady>());
      final check = sentenceTokens(_letters('ABCDEFGHI'));
      expect((check as TokensBlocked).reason, TokensBlock.wordTooLong);
      expect(tokensMessageFor(check), 'Expand takes up to 8 letters a word.');
    });

    test('REQ-TOKENS-3: reasons are checked in order', () {
      final all = [..._sentence(List.filled(13, 'ABCDEFGHI')), _unknown];
      expect((sentenceTokens(all) as TokensBlocked).reason,
          TokensBlock.nonLetter);
      final longAndMany = _sentence(List.filled(13, 'ABCDEFGHI'));
      expect((sentenceTokens(longAndMany) as TokensBlocked).reason,
          TokensBlock.tooManyWords);
    });
  });
}
