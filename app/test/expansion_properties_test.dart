/// Property-based tests for the shorthand-expansion rules in `lib/compose/`,
/// one `property(...)` per correctness property in the design. Each uses a
/// single `forAll` with `maxExamples: 200` and the fixed seed
/// `(600 + N) * 1000 + 3` for Property N (REQ-APPTEST-2, REQ-APPTEST-5).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:sounder/compose/initials_validator.dart';
import 'package:sounder/compose/narrowing.dart';
import 'package:sounder/compose/sentence_tokens.dart';

import 'support/expansion_arbitraries.dart';

/// Records the counterexample and seed so a failure can be reproduced. The
/// generated strings are synthetic, not user text (REQ-APPTEST-2).
void Function(Object?) report(int seed) =>
    (x) => printOnFailure('Falsifying example: $x, seed: $seed');

void main() {
  // Feature: shorthand-expansion, Property 1: Generated-valid candidates are accepted
  property('REQ-VALIDATOR-5, REQ-VALIDATOR-1, REQ-APPTEST-2: '
      'generated-valid candidates are accepted', () {
    forAll(
      validPairArb(),
      (pair) {
        // The fixed caps keep the trimmed Candidate within 200 code units.
        expect(
          trimE2(pair.candidate).length,
          lessThanOrEqualTo(maxCandidateLength),
          reason: '$pair',
        );
        expect(
          isValidCandidate(pair.tokens, pair.candidate),
          isTrue,
          reason: '$pair',
        );
      },
      maxExamples: 200,
      seed: 601003,
      onFalsify: report(601003),
    );
  });

  // Feature: shorthand-expansion, Property 2: Changing a first letter makes a candidate invalid
  property('REQ-VALIDATOR-6, REQ-VALIDATOR-1, REQ-APPTEST-2: '
      'changing a first letter makes a candidate invalid', () {
    forAll(
      firstLetterMutationArb(),
      (pair) {
        expect(
          isValidCandidate(pair.tokens, pair.candidate),
          isFalse,
          reason: '$pair',
        );
      },
      maxExamples: 200,
      seed: 602003,
      onFalsify: report(602003),
    );
  });

  // Feature: shorthand-expansion, Property 3: A different word count makes a candidate invalid
  property('REQ-VALIDATOR-7, REQ-VALIDATOR-1, REQ-APPTEST-2: '
      'a different word count makes a candidate invalid', () {
    forAll(
      wordCountMutationArb(),
      (pair) {
        expect(
          isValidCandidate(pair.tokens, pair.candidate),
          isFalse,
          reason: '$pair',
        );
      },
      maxExamples: 200,
      seed: 603003,
      onFalsify: report(603003),
    );
  });

  // Feature: shorthand-expansion, Property 7: Sentence_Tokens follow the words of the Sentence
  property('REQ-TOKENS-1, REQ-TOKENS-2, REQ-TOKENS-3: '
      'Sentence_Tokens follow the words of the Sentence', () {
    forAll(
      sentenceArb(),
      (sentence) {
        // The expected check comes from the words the generator built, in
        // the REQ-TOKENS-3 order, with the 12-word and 8-letter limits.
        final words = sentence.words;
        final TokensCheck expected;
        String? expectedMessage;
        if (words.isEmpty) {
          expected = const TokensEmpty();
        } else if (words.any((w) => w.any((item) => !item.$2))) {
          expected = const TokensBlocked(TokensBlock.nonLetter);
          expectedMessage = 'Expand needs letters only.';
        } else if (words.length > 12) {
          expected = const TokensBlocked(TokensBlock.tooManyWords);
          expectedMessage = 'Expand takes up to 12 words.';
        } else if (words.any((w) => w.length > 8)) {
          expected = const TokensBlocked(TokensBlock.wordTooLong);
          expectedMessage = 'Expand takes up to 8 letters a word.';
        } else {
          expected = TokensReady([
            for (final w in words) w.map((item) => item.$1.character!).join(),
          ]);
        }

        final actual = sentenceTokens(sentence.items);
        switch (expected) {
          case TokensEmpty():
            expect(actual, isA<TokensEmpty>(), reason: '$sentence');
          case TokensBlocked(:final reason):
            expect(actual, isA<TokensBlocked>(), reason: '$sentence');
            expect(
              (actual as TokensBlocked).reason,
              reason,
              reason: '$sentence',
            );
          case TokensReady(:final tokens):
            expect(actual, isA<TokensReady>(), reason: '$sentence');
            expect(
              (actual as TokensReady).tokens,
              orderedEquals(tokens),
              reason: '$sentence',
            );
        }
        expect(tokensMessageFor(actual), expectedMessage, reason: '$sentence');
      },
      maxExamples: 200,
      seed: 607003,
      onFalsify: report(607003),
    );
  });

  // Feature: shorthand-expansion, Property 8: Narrowing keeps exactly the valid candidates, in order
  property('REQ-NARROW-3, REQ-NARROW-1, REQ-APPTEST-2: '
      'narrowing keeps exactly the valid candidates, in order', () {
    forAll(
      narrowingCaseArb(),
      (c) {
        final candidates = c.candidates;
        final narrowed = narrowCandidates(candidates, c.check);
        switch (c.check) {
          case TokensEmpty() || TokensBlocked():
            // A disabled Expand clears the Candidate_List (REQ-NARROW-1).
            expect(narrowed, isEmpty, reason: '$c');
          case TokensReady(:final tokens):
            // Exactly the accepted items, in their original order.
            expect(
              narrowed,
              orderedEquals(
                candidates.where((x) => isValidCandidate(tokens, x)),
              ),
              reason: '$c',
            );
            // Every candidate built valid for these tokens is kept.
            expect(
              narrowed,
              containsAll(c.items.where((i) => i.$2).map((i) => i.$1)),
              reason: '$c',
            );
        }
        // An in-order sublist of the original, every item accepted
        // (REQ-NARROW-3).
        var from = 0;
        for (final x in narrowed) {
          final at = candidates.indexOf(x, from);
          expect(at, greaterThanOrEqualTo(0), reason: '$c');
          from = at + 1;
          final check = c.check as TokensReady;
          expect(isValidCandidate(check.tokens, x), isTrue, reason: '$c');
        }
      },
      maxExamples: 200,
      seed: 608003,
      onFalsify: report(608003),
    );
  });

  // Feature: shorthand-expansion, Property 9: Adding letters to tokens only narrows
  property('REQ-NARROW-4, REQ-APPTEST-2: '
      'adding letters to tokens only narrows', () {
    forAll(
      extendedTokensCaseArb(),
      (c) {
        // T′ is T with letters appended: same length, each Token of T′
        // starts with Token i of T, stays 1 to 8 letters, and one is longer.
        expect(c.extended.length, c.tokens.length, reason: '$c');
        for (var i = 0; i < c.tokens.length; i++) {
          expect(c.extended[i].startsWith(c.tokens[i]), isTrue, reason: '$c');
          expect(c.extended[i].length, inInclusiveRange(1, 8), reason: '$c');
        }
        expect(
          [for (var i = 0; i < c.tokens.length; i++) i]
              .any((i) => c.extended[i].length > c.tokens[i].length),
          isTrue,
          reason: '$c',
        );
        // Accepted for T′ implies accepted for T.
        if (isValidCandidate(c.extended, c.candidate)) {
          expect(isValidCandidate(c.tokens, c.candidate), isTrue, reason: '$c');
        }
        // The same through narrowing: what T′ keeps, T keeps too.
        final forT = narrowCandidates([c.candidate], TokensReady(c.tokens));
        final forExtended = narrowCandidates([
          c.candidate,
        ], TokensReady(c.extended));
        expect(forT, containsAll(forExtended), reason: '$c');
      },
      maxExamples: 200,
      seed: 609003,
      onFalsify: report(609003),
    );
  });

  // Feature: shorthand-expansion, Property 10: Narrowing is idempotent
  property('REQ-NARROW-5, REQ-APPTEST-2: '
      'narrowing twice gives the same list as narrowing once', () {
    forAll(
      narrowingCaseArb(),
      (c) {
        final once = narrowCandidates(c.candidates, c.check);
        final twice = narrowCandidates(once, c.check);
        expect(twice, orderedEquals(once), reason: '$c');
      },
      maxExamples: 200,
      seed: 610003,
      onFalsify: report(610003),
    );
  });
}
