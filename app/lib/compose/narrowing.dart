import 'initials_validator.dart';
import 'sentence_tokens.dart';

/// Narrows a shown Candidate_List after the Sentence changes. Returns an
/// empty list unless [check] is [TokensReady]; otherwise returns, in their
/// original order, only the [candidates] that the Dart_Validator
/// ([isValidCandidate]) accepts for `check.tokens`. An empty result means the
/// Candidate_List is cleared. The result is unmodifiable and [candidates] is
/// not changed. Pure Dart: no I/O, clock or logging. REQ-NARROW-1,
/// REQ-COMPOSE-1.
List<String> narrowCandidates(List<String> candidates, TokensCheck check) =>
    switch (check) {
      TokensReady(:final tokens) => List.unmodifiable(
          candidates.where((c) => isValidCandidate(tokens, c)),
        ),
      TokensEmpty() || TokensBlocked() => const <String>[],
    };
