/// kiri_check generators for the shorthand-expansion property tests. They
/// match the fast-check generators in `worker/test/support/arbitraries.ts`,
/// so both suites test the Initials_Validator on the same input space
/// (REQ-VALIDATOR-5, REQ-VALIDATOR-1, REQ-APPTEST-2).
///
/// Every generator meets its preconditions by construction: no kiri_check
/// filter is used. Generated strings are synthetic test data, not user text.
library;

import 'package:kiri_check/kiri_check.dart';
import 'package:morse_core/morse_core.dart';
import 'package:sounder/compose/sentence_tokens.dart';

import 'item_arbitraries.dart' show unknownLetterItem;

/// The 52 ASCII letters `A`-`Z` and `a`-`z` (REQ-VALIDATOR-1, E1).
final List<String> asciiLetters = List<String>.unmodifiable(<String>[
  for (var u = 0x41; u <= 0x5a; u++) String.fromCharCode(u),
  for (var u = 0x61; u <= 0x7a; u++) String.fromCharCode(u),
]);

/// The strip characters `. , ! ? ; : " ( )` (REQ-VALIDATOR-1 (c), E4).
const List<String> stripChars = <String>[
  '.',
  ',',
  '!',
  '?',
  ';',
  ':',
  '"',
  '(',
  ')',
];

/// The E2 whitespace characters U+0009..U+000D and U+0020
/// (REQ-VALIDATOR-1 (b), E2).
const List<String> e2Spaces = <String>['\t', '\n', '\u000b', '\f', '\r', ' '];

/// Most Tokens in a Token_List (REQ-VALIDATOR-1, REQ-EXPAND-4).
const int _maxTokens = 12;

/// Most letters in a Token (REQ-VALIDATOR-1, REQ-EXPAND-4).
const int _maxTokenLetters = 8;

/// Fixed caps for generated-valid candidates (design, Property test
/// configuration). With at most 12 Words of 8 token letters + 2 extra
/// letters + 2 leading and 2 trailing strip characters, and 11 separators of
/// at most 2 characters, the E2-trimmed Candidate is at most
/// 12 × 14 + 11 × 2 = 190 characters, within the 200 of REQ-VALIDATOR-1 (a)
/// and REQ-VALIDATOR-5.
const int _maxExtraLetters = 2;
const int _maxStripPerEnd = 2;
const int _maxSeparatorLength = 2;
const int _maxOuterSpaceLength = 2;

/// A string of [minLength] to [maxLength] characters drawn from [units]
/// (REQ-VALIDATOR-5).
Arbitrary<String> _stringOf(
  List<String> units, {
  int minLength = 0,
  required int maxLength,
}) => list<String>(
  constantFrom<String>(units),
  minLength: minLength,
  maxLength: maxLength,
).map((parts) => parts.join());

/// A Token: 1 to 8 ASCII letters in any case (REQ-VALIDATOR-1,
/// REQ-VALIDATOR-5).
Arbitrary<String> tokenArb() =>
    _stringOf(asciiLetters, minLength: 1, maxLength: _maxTokenLetters);

/// A Token_List: 1 to 12 Tokens (REQ-VALIDATOR-1, REQ-VALIDATOR-5).
Arbitrary<List<String>> tokenListArb() =>
    list<String>(tokenArb(), minLength: 1, maxLength: _maxTokens);

/// ASCII case of one letter: [letter] is an ASCII letter here (E1).
String _withCase(String letter, bool upper) {
  final u = letter.codeUnitAt(0);
  final lower = u >= 0x41 && u <= 0x5a ? u + 0x20 : u;
  return String.fromCharCode(upper ? lower - 0x20 : lower);
}

/// How one Word is built from its Token: the case of each Token letter
/// (one flag per possible Token letter), 0 to 2 extra ASCII letters, and 0
/// to 2 strip characters at each end (REQ-VALIDATOR-5).
typedef _WordShape = (List<bool>, String, String, String);

Arbitrary<_WordShape> _wordShapeArb() => combine4(
  list<bool>(
    boolean(),
    minLength: _maxTokenLetters,
    maxLength: _maxTokenLetters,
  ),
  _stringOf(asciiLetters, maxLength: _maxExtraLetters),
  _stringOf(stripChars, maxLength: _maxStripPerEnd),
  _stringOf(stripChars, maxLength: _maxStripPerEnd),
);

/// The Word for [token] built by [shape] (REQ-VALIDATOR-5).
String _buildWord(String token, _WordShape shape) {
  final (upper, extra, lead, trail) = shape;
  final core = StringBuffer();
  for (var i = 0; i < token.length; i++) {
    core.write(_withCase(token[i], upper[i]));
  }
  return '$lead$core$extra$trail';
}

/// A Candidate that the Initials_Validator must accept for [tokens]: Word i
/// is Token i in any letter case plus 0 to 2 extra letters, with 0 to 2
/// strip characters at each end; Words are joined by 1 to 2 E2 whitespace
/// characters, with 0 to 2 E2 whitespace characters before and after. The
/// fixed caps keep the trimmed Candidate at or under 190 characters
/// (REQ-VALIDATOR-5, REQ-VALIDATOR-1, REQ-APPTEST-2).
Arbitrary<String> validCandidateArb(List<String> tokens) {
  final count = tokens.length;
  final separator = _stringOf(
    e2Spaces,
    minLength: 1,
    maxLength: _maxSeparatorLength,
  );
  final outer = _stringOf(e2Spaces, maxLength: _maxOuterSpaceLength);
  return combine4(
    list<_WordShape>(_wordShapeArb(), minLength: count, maxLength: count),
    // One separator per Word; the last one is unused, so the list length is
    // never 0 (REQ-VALIDATOR-5).
    list<String>(separator, minLength: count, maxLength: count),
    outer,
    outer,
  ).map((input) {
    final (shapes, separators, leading, trailing) = input;
    final body = StringBuffer(_buildWord(tokens[0], shapes[0]));
    for (var i = 1; i < count; i++) {
      body
        ..write(separators[i - 1])
        ..write(_buildWord(tokens[i], shapes[i]));
    }
    return '$leading$body$trailing';
  });
}

/// A Token_List with a Candidate for it (REQ-VALIDATOR-5, REQ-APPTEST-2).
final class TokensAndCandidate {
  const TokensAndCandidate(this.tokens, this.candidate);
  final List<String> tokens;
  final String candidate;

  /// Synthetic test data only; shows control characters as escapes so a
  /// counterexample is readable (REQ-APPTEST-2).
  @override
  String toString() =>
      'tokens: $tokens, candidate: "${_escapeSynthetic(candidate)}"';
}

/// [s] with control and non-ASCII code units shown as `\uXXXX`, so a
/// synthetic counterexample is readable (REQ-APPTEST-2).
String _escapeSynthetic(String s) => s.codeUnits
    .map(
      (u) => u < 0x20 || u > 0x7e
          ? '\\u${u.toRadixString(16).padLeft(4, '0')}'
          : String.fromCharCode(u),
    )
    .join();

/// A Token_List with a generated-valid Candidate for it (Property 1;
/// REQ-VALIDATOR-5, REQ-VALIDATOR-1, REQ-APPTEST-2).
Arbitrary<TokensAndCandidate> validPairArb() => tokenListArb().flatMap(
  (tokens) =>
      validCandidateArb(tokens)
          .map((candidate) => TokensAndCandidate(tokens, candidate)),
);

/// Index in [candidate] of the first character of Stripped_Word [wordIndex]:
/// skips E2 whitespace to the start of that Word, then its leading strip
/// characters. Only called on candidates from [validCandidateArb], where that
/// character is an ASCII letter (REQ-VALIDATOR-6, E2, E4).
int _strippedWordStart(String candidate, int wordIndex) {
  bool isE2(int i) => e2Spaces.contains(candidate[i]);
  var i = 0;
  var word = -1;
  while (i < candidate.length) {
    while (i < candidate.length && isE2(i)) {
      i++;
    }
    word++;
    if (word == wordIndex) break;
    while (i < candidate.length && !isE2(i)) {
      i++;
    }
  }
  while (i < candidate.length && stripChars.contains(candidate[i])) {
    i++;
  }
  return i;
}

/// A Property 1 pair whose Candidate has the first letter of Stripped_Word i
/// replaced by a different ASCII letter. Position i is a non-negative integer
/// modulo the Word count; the new letter is `(first + 1 + k) mod 26` with k
/// in 0..24, so it differs from the old one ignoring case by construction,
/// and it keeps the old letter's case. Token i starts with the old letter
/// ignoring case, so the new Stripped_Word i no longer starts with Token i.
/// Mirrors `firstLetterMutationArb` in `worker/test/support/arbitraries.ts`
/// (Property 2; REQ-VALIDATOR-6, REQ-VALIDATOR-1, REQ-APPTEST-2).
Arbitrary<TokensAndCandidate> firstLetterMutationArb() =>
    tokenListArb().flatMap(
      (tokens) =>
          combine3(
            validCandidateArb(tokens),
            integer(min: 0),
            integer(min: 0, max: 24),
          ).map((input) {
            final (valid, n, k) = input;
            final at = _strippedWordStart(valid, n % tokens.length);
            final u = valid.codeUnitAt(at);
            final upper = u >= 0x41 && u <= 0x5a;
            final first = upper ? u - 0x41 : u - 0x61;
            final replaced = (first + 1 + k) % 26;
            final letter = String.fromCharCode(
              (upper ? 0x41 : 0x61) + replaced,
            );
            return TokensAndCandidate(
              tokens,
              valid.substring(0, at) + letter + valid.substring(at + 1),
            );
          }),
    );

/// Most Words that [addWordsMutationArb] inserts (REQ-VALIDATOR-7).
const int _maxAddedWords = 3;

/// The Words of [candidate]: its maximal runs of non-E2 characters, in order
/// (REQ-VALIDATOR-1 (b), E2).
List<String> _splitE2Words(String candidate) {
  bool isE2(int i) => e2Spaces.contains(candidate[i]);
  final words = <String>[];
  var i = 0;
  while (i < candidate.length) {
    while (i < candidate.length && isE2(i)) {
      i++;
    }
    final start = i;
    while (i < candidate.length && !isE2(i)) {
      i++;
    }
    if (i > start) words.add(candidate.substring(start, i));
  }
  return words;
}

/// [words] joined by the given E2 [separators], with [leading] and
/// [trailing] E2 whitespace. [separators] has at least `words.length - 1`
/// entries (REQ-VALIDATOR-1 (b), E2).
String _joinE2Words(
  List<String> words,
  List<String> separators,
  String leading,
  String trailing,
) {
  final body = StringBuffer();
  for (var i = 0; i < words.length; i++) {
    if (i > 0) body.write(separators[i - 1]);
    body.write(words[i]);
  }
  return '$leading$body$trailing';
}

/// 1 to 2 E2 whitespace characters between two Words (REQ-VALIDATOR-1 (b)).
Arbitrary<String> _separatorArb() =>
    _stringOf(e2Spaces, minLength: 1, maxLength: _maxSeparatorLength);

/// 0 to 2 E2 whitespace characters at one end (REQ-VALIDATOR-1 (a)).
Arbitrary<String> _outerSpaceArb() =>
    _stringOf(e2Spaces, maxLength: _maxOuterSpaceLength);

/// A Property 1 pair with at least 1 and at most all of its Words removed.
/// A removal mask is drawn for every Word and one Word, chosen by a
/// non-negative integer modulo the Word count, is always removed, so the
/// Word count is below the Token count by construction. Removing every Word
/// leaves an E2-only Candidate, which must also be rejected. Mirrors
/// `removeWordsMutationArb` in `worker/test/support/arbitraries.ts`
/// (Property 3; REQ-VALIDATOR-7, REQ-VALIDATOR-1, REQ-APPTEST-2).
Arbitrary<TokensAndCandidate> removeWordsMutationArb() =>
    tokenListArb().flatMap(
      (tokens) =>
          combine6(
            validCandidateArb(tokens),
            list<bool>(
              boolean(),
              minLength: tokens.length,
              maxLength: tokens.length,
            ),
            integer(min: 0),
            list<String>(
              _separatorArb(),
              minLength: tokens.length,
              maxLength: tokens.length,
            ),
            _outerSpaceArb(),
            _outerSpaceArb(),
          ).map((input) {
            final (valid, remove, n, separators, leading, trailing) = input;
            final words = _splitE2Words(valid);
            final forced = n % words.length;
            final kept = <String>[
              for (var i = 0; i < words.length; i++)
                if (i != forced && !remove[i]) words[i],
            ];
            return TokensAndCandidate(
              tokens,
              _joinE2Words(kept, separators, leading, trailing),
            );
          }),
    );

/// A Property 1 pair with 1 to 3 Words inserted at any positions. Each added
/// Word is 1 to 8 ASCII letters, so it is a non-empty Word and the Word count
/// is above the Token count by construction. Each position is a non-negative
/// integer modulo the current Word count + 1. The result may exceed 200
/// characters, which is also invalid. Mirrors `addWordsMutationArb` in
/// `worker/test/support/arbitraries.ts` (Property 3; REQ-VALIDATOR-7,
/// REQ-VALIDATOR-1, REQ-APPTEST-2).
Arbitrary<TokensAndCandidate> addWordsMutationArb() => tokenListArb().flatMap(
  (tokens) =>
      combine5(
        validCandidateArb(tokens),
        list<(String, int)>(
          combine2(tokenArb(), integer(min: 0)),
          minLength: 1,
          maxLength: _maxAddedWords,
        ),
        list<String>(
          _separatorArb(),
          minLength: tokens.length + _maxAddedWords,
          maxLength: tokens.length + _maxAddedWords,
        ),
        _outerSpaceArb(),
        _outerSpaceArb(),
      ).map((input) {
        final (valid, added, separators, leading, trailing) = input;
        final words = _splitE2Words(valid);
        for (final (word, n) in added) {
          words.insert(n % (words.length + 1), word);
        }
        return TokensAndCandidate(
          tokens,
          _joinE2Words(words, separators, leading, trailing),
        );
      }),
);

/// A Property 1 pair whose Word count differs from its Token count, by
/// removing or adding Words. Mirrors `wordCountMutationArb` in
/// `worker/test/support/arbitraries.ts` (Property 3; REQ-VALIDATOR-7,
/// REQ-VALIDATOR-1, REQ-APPTEST-2).
Arbitrary<TokensAndCandidate> wordCountMutationArb() => boolean().flatMap(
  (add) => add ? addWordsMutationArb() : removeWordsMutationArb(),
);

/// The uppercase ASCII letters `A`-`Z`: the Letter_Items that are letters
/// (REQ-TOKENS-1, E16).
final List<String> _upperLetters = List<String>.unmodifiable(<String>[
  for (var u = 0x41; u <= 0x5a; u++) String.fromCharCode(u),
]);

/// The code-table characters that are not ASCII letters: digits and
/// punctuation. A Letter_Item for one of them is a non-letter
/// (REQ-TOKENS-2, E16).
final List<String> _digitAndPunctuation = List<String>.unmodifiable(
  const CodeTable().codes.keys.where((c) => !_upperLetters.contains(c)),
);

/// Most words in a generated Sentence: 2 more than the 12 a Token_List may
/// hold, so `tooManyWords` is reached (REQ-TOKENS-2, REQ-TOKENS-3).
const int _maxSentenceWords = 14;

/// Most items in a generated word: 2 more than the 8 letters a Token may
/// hold, so `wordTooLong` is reached (REQ-TOKENS-2, REQ-TOKENS-3).
const int _maxWordItems = 10;

/// Most Word_Spaces at one end of a generated Sentence (E16).
const int _maxOuterWordSpaces = 2;

/// Most Word_Spaces between two generated words (E16).
const int _maxWordSpacesBetween = 3;

/// One generated item of a word with whether it is a letter: `true` for an
/// ASCII Letter_Item, `false` for an Unknown_Letter_Item or a digit or
/// punctuation Letter_Item (REQ-TOKENS-2, E16).
typedef SentenceItem = (DecodedItem, bool);

/// An ASCII Letter_Item (REQ-TOKENS-1).
Arbitrary<SentenceItem> _letterSentenceItem() =>
    constantFrom<String>(_upperLetters)
        .map((c) => (DecodedItem.letter(c), true));

/// A non-letter: an Unknown_Letter_Item, as `item_arbitraries.dart` builds
/// it, or a digit or punctuation Letter_Item (REQ-TOKENS-2, E16).
Arbitrary<SentenceItem> _nonLetterSentenceItem() => oneOf(<Arbitrary<dynamic>>[
  unknownLetterItem().map<SentenceItem>((item) => (item, false)),
  constantFrom<String>(_digitAndPunctuation)
      .map<SentenceItem>((c) => (DecodedItem.letter(c), false)),
]).cast<SentenceItem>();

/// The length of a generated word: mostly 1 to 8, sometimes 9 or 10, so
/// Sentences within the limits stay common (REQ-TOKENS-2).
Arbitrary<int> _wordLengthArb() => frequency(<(int, Arbitrary<dynamic>)>[
  (9, integer(min: 1, max: _maxTokenLetters)),
  (1, integer(min: _maxTokenLetters + 1, max: _maxWordItems)),
]).cast<int>();

/// A word of 1 to 10 items drawn from [item] (REQ-TOKENS-1, E16).
Arbitrary<List<SentenceItem>> _wordArb(Arbitrary<SentenceItem> item) =>
    _wordLengthArb().flatMap(
      (length) =>
          list<SentenceItem>(item, minLength: length, maxLength: length),
    );

/// A generated Sentence: the Decoded_Items and the words they were built
/// from, so the test can state the expected Sentence_Tokens without
/// splitting [items] again (REQ-TOKENS-1, REQ-TOKENS-2, REQ-TOKENS-3).
final class GeneratedSentence {
  const GeneratedSentence(this.items, this.words);

  /// The Sentence: the words with Word_Spaces around and between them.
  final List<DecodedItem> items;

  /// The words in order, each 1 to 10 items with their letter flags.
  final List<List<SentenceItem>> words;

  /// Synthetic test data only: words joined by `_` for each Word_Space, an
  /// Unknown_Letter_Item shown as `#` (REQ-APPTEST-2).
  @override
  String toString() => items
      .map(
        (item) => switch (item.kind) {
          DecodedItemKind.letter => item.character!,
          DecodedItemKind.unknownLetter => '#',
          DecodedItemKind.wordSpace => '_',
        },
      )
      .join();
}

/// A Sentence of 0 to 14 words of 1 to 10 items, with 1 to 3 Word_Spaces
/// between words and 0 to 2 at each end. Three in four Sentences hold only
/// ASCII Letter_Items; in the rest, about one item in four is a non-letter
/// (an Unknown_Letter_Item, a digit or a punctuation Letter_Item), so every
/// TokensCheck outcome is common. With no words the Sentence is 0 to 4
/// Word_Spaces (Property 7; REQ-TOKENS-1, REQ-TOKENS-2, REQ-TOKENS-3, E16).
Arbitrary<GeneratedSentence> sentenceArb() {
  final mixedItem = frequency(<(int, Arbitrary<dynamic>)>[
    (3, _letterSentenceItem()),
    (1, _nonLetterSentenceItem()),
  ]).cast<SentenceItem>();
  final words = frequency(<(int, Arbitrary<dynamic>)>[
    (
      3,
      list<List<SentenceItem>>(
        _wordArb(_letterSentenceItem()),
        maxLength: _maxSentenceWords,
      ),
    ),
    (
      1,
      list<List<SentenceItem>>(
        _wordArb(mixedItem),
        maxLength: _maxSentenceWords,
      ),
    ),
  ]).cast<List<List<SentenceItem>>>();
  return combine4(
    words,
    list<int>(
      integer(min: 1, max: _maxWordSpacesBetween),
      minLength: _maxSentenceWords,
      maxLength: _maxSentenceWords,
    ),
    integer(min: 0, max: _maxOuterWordSpaces),
    integer(min: 0, max: _maxOuterWordSpaces),
  ).map((input) {
    final (words, between, leading, trailing) = input;
    const space = DecodedItem.wordSpace();
    final items = <DecodedItem>[
      for (var i = 0; i < leading; i++) space,
      for (var w = 0; w < words.length; w++) ...[
        if (w > 0)
          for (var i = 0; i < between[w]; i++) space,
        for (final (item, _) in words[w]) item,
      ],
      for (var i = 0; i < trailing; i++) space,
    ];
    return GeneratedSentence(
      List<DecodedItem>.unmodifiable(items),
      List<List<SentenceItem>>.unmodifiable(words),
    );
  });
}

/// Most Candidates in a generated Candidate_List (Property 8; REQ-NARROW-3).
const int _maxCandidateListLength = 6;

/// Most characters in an arbitrary candidate string (Property 8).
const int _maxArbitraryCandidateLength = 40;

/// Characters for arbitrary candidate strings: ASCII letters, E2
/// whitespace, strip characters, and characters the Initials_Validator does
/// not strip (digits, `-`, `'`, a non-ASCII letter and an emoji surrogate
/// half pair), so both accepted and rejected strings occur (REQ-NARROW-3).
final List<String> _arbitraryCandidateUnits = List<String>.unmodifiable(
  <String>[
    ...asciiLetters,
    ...e2Spaces,
    ...stripChars,
    '0',
    '7',
    '-',
    "'",
    '\u00e9',
    '\u{1F600}',
  ],
);

/// An arbitrary string of 0 to 40 characters (Property 8; REQ-NARROW-3).
Arbitrary<String> _arbitraryCandidateArb() => _stringOf(
  _arbitraryCandidateUnits,
  maxLength: _maxArbitraryCandidateLength,
);

/// One generated Candidate with whether it was built valid for the Token_List
/// the Candidate_List was made for (REQ-NARROW-3).
typedef GeneratedCandidate = (String, bool);

/// A Candidate_List of 0 to 6 strings for [tokens]: each is a
/// generated-valid Candidate for [tokens] (tagged `true`), a generated-valid
/// Candidate for another Token_List, or an arbitrary string (both tagged
/// `false`; either may still be accepted by chance). Mirrors the design's
/// Property 8 input (REQ-NARROW-3, REQ-NARROW-1, REQ-APPTEST-2).
Arbitrary<List<GeneratedCandidate>> candidateListArb(List<String> tokens) {
  final item = frequency(<(int, Arbitrary<dynamic>)>[
    (
      2,
      validCandidateArb(tokens)
          .map<GeneratedCandidate>((candidate) => (candidate, true)),
    ),
    (
      1,
      validPairArb().map<GeneratedCandidate>((pair) => (pair.candidate, false)),
    ),
    (
      1,
      _arbitraryCandidateArb().map<GeneratedCandidate>(
        (candidate) => (candidate, false),
      ),
    ),
  ]).cast<GeneratedCandidate>();
  return list<GeneratedCandidate>(item, maxLength: _maxCandidateListLength);
}

/// A TokensCheck for [tokens]: three in four are `TokensReady(tokens)`; the
/// rest are `TokensEmpty` or `TokensBlocked` for any reason (Property 8;
/// REQ-NARROW-1, REQ-TOKENS-2).
Arbitrary<TokensCheck> tokensCheckArb(List<String> tokens) =>
    frequency(<(int, Arbitrary<dynamic>)>[
      (3, constantFrom<TokensCheck>(<TokensCheck>[TokensReady(tokens)])),
      (
        1,
        constantFrom<TokensCheck>(<TokensCheck>[
          const TokensEmpty(),
          for (final reason in TokensBlock.values) TokensBlocked(reason),
        ]),
      ),
    ]).cast<TokensCheck>();

/// A Candidate_List with a TokensCheck, both made for one Token_List
/// (Property 8; REQ-NARROW-3, REQ-NARROW-1).
final class NarrowingCase {
  const NarrowingCase(this.tokens, this.check, this.items);

  /// The Token_List both generators were made for.
  final List<String> tokens;

  /// The TokensCheck passed to `narrowCandidates`.
  final TokensCheck check;

  /// The Candidate_List with each item's generated-valid tag.
  final List<GeneratedCandidate> items;

  /// The Candidate_List passed to `narrowCandidates`.
  List<String> get candidates =>
      List<String>.unmodifiable(items.map((item) => item.$1));

  /// Synthetic test data only (REQ-APPTEST-2).
  @override
  String toString() {
    final check = switch (this.check) {
      TokensEmpty() => 'TokensEmpty',
      TokensBlocked(:final reason) => 'TokensBlocked(${reason.name})',
      TokensReady(:final tokens) => 'TokensReady($tokens)',
    };
    final candidates = items
        .map((item) => '"${_escapeSynthetic(item.$1)}"${item.$2 ? '*' : ''}')
        .join(', ');
    return 'check: $check, candidates: [$candidates]';
  }
}

/// A Token_List with a Candidate_List and a TokensCheck for it (Property 8;
/// REQ-NARROW-3, REQ-NARROW-1, REQ-APPTEST-2).
Arbitrary<NarrowingCase> narrowingCaseArb() => tokenListArb().flatMap(
  (tokens) => combine2(
    tokensCheckArb(tokens),
    candidateListArb(tokens),
  ).map((input) => NarrowingCase(tokens, input.$1, input.$2)),
);

/// One Token of T with the letters appended to it in T′ (Property 9;
/// REQ-NARROW-4).
typedef _TokenExtension = (String, String);

/// A Token of [minLength] to [maxLength] letters with 0 to
/// `8 - token.length` appended letters, or at least [minAppended] when that
/// is above 0, so the extended Token stays at most 8 letters by construction
/// (Property 9; REQ-NARROW-4).
Arbitrary<_TokenExtension> _tokenExtensionArb({
  required int maxLength,
  required int minAppended,
}) => _stringOf(asciiLetters, minLength: 1, maxLength: maxLength).flatMap(
  (token) => _stringOf(
    asciiLetters,
    minLength: minAppended,
    maxLength: _maxTokenLetters - token.length,
  ).map((appended) => (token, appended)),
);

/// A Token_List T, a Token_List T′ made from T by appending letters, and a
/// Candidate (Property 9; REQ-NARROW-4, REQ-APPTEST-2).
final class ExtendedTokensCase {
  const ExtendedTokensCase(this.tokens, this.extended, this.candidate);

  /// T: 1 to 12 Tokens of 1 to 8 letters.
  final List<String> tokens;

  /// T′: Token i of T with 0 or more letters appended, each at most 8
  /// letters, at least one Token longer than in T.
  final List<String> extended;

  /// The Candidate checked against T′ and T.
  final String candidate;

  /// Synthetic test data only (REQ-APPTEST-2).
  @override
  String toString() =>
      'tokens: $tokens, extended: $extended, '
      'candidate: "${_escapeSynthetic(candidate)}"';
}

/// A Token_List T, a T′ made from T by appending 1 or more ASCII letters to
/// 1 or more Tokens with each staying at most 8 letters, and a Candidate.
/// One Token, at a position chosen by a non-negative integer modulo the
/// Token count, starts with 1 to 7 letters and gets 1 or more appended
/// letters, so T′ differs from T by construction; the other 0 to 11 Tokens
/// get 0 or more. The Candidate is mostly generated-valid for T′ (as in
/// Property 1), so the premise is often true; otherwise it is
/// generated-valid for T or an arbitrary string (Property 9; REQ-NARROW-4,
/// REQ-APPTEST-2).
Arbitrary<ExtendedTokensCase> extendedTokensCaseArb() =>
    combine3(
      list<_TokenExtension>(
        _tokenExtensionArb(maxLength: _maxTokenLetters, minAppended: 0),
        maxLength: _maxTokens - 1,
      ),
      _tokenExtensionArb(maxLength: _maxTokenLetters - 1, minAppended: 1),
      integer(min: 0),
    ).flatMap((input) {
      final (others, forced, n) = input;
      final pairs = <_TokenExtension>[...others]
        ..insert(n % (others.length + 1), forced);
      final tokens = List<String>.unmodifiable(pairs.map((p) => p.$1));
      final extended = List<String>.unmodifiable(
        pairs.map((p) => '${p.$1}${p.$2}'),
      );
      return frequency(<(int, Arbitrary<dynamic>)>[
            (3, validCandidateArb(extended)),
            (1, validCandidateArb(tokens)),
            (1, _arbitraryCandidateArb()),
          ])
          .cast<String>()
          .map((candidate) => ExtendedTokensCase(tokens, extended, candidate));
    });
