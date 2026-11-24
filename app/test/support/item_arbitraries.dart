/// kiri_check generators of Decoded_Items for the key-screen property
/// tests. REQ-COMPOSE-6, REQ-CI-2.
library;

import 'package:kiri_check/kiri_check.dart';
import 'package:morse_core/morse_core.dart';

/// The uppercase characters of the morse_core code table. REQ-COMPOSE-6.
final List<String> _tableCharacters = List<String>.unmodifiable(
  const CodeTable().codes.keys,
);

/// A fixed prefix of eight dits. Every table code has at most six symbols,
/// so any sequence that starts with this prefix is unknown, and no filter is
/// needed. REQ-COMPOSE-6.
const String unknownPrefix = '........';

/// One Letter_Item for a code-table character. REQ-COMPOSE-6.
Arbitrary<DecodedItem> letterItem() =>
    constantFrom<String>(_tableCharacters).map((c) => DecodedItem.letter(c));

/// One Unknown_Letter_Item: [unknownPrefix] followed by 0 to 6 random
/// symbols. REQ-COMPOSE-6.
Arbitrary<DecodedItem> unknownLetterItem() => list<String>(
  constantFrom<String>(const <String>['.', '-']),
  maxLength: 6,
).map((symbols) => DecodedItem.unknownLetter(unknownPrefix + symbols.join()));

/// One Decoded_Item: mostly Letter_Items, with Unknown_Letter_Items and
/// Word_Spaces common. REQ-COMPOSE-6.
Arbitrary<DecodedItem> decodedItem() => frequency(<(int, Arbitrary<dynamic>)>[
  (6, letterItem()),
  (2, unknownLetterItem()),
  (2, constant<DecodedItem>(const DecodedItem.wordSpace())),
]).cast<DecodedItem>();

/// A list of 0 to [maxLength] Decoded_Items. REQ-COMPOSE-6.
Arbitrary<List<DecodedItem>> itemList({required int maxLength}) =>
    list<DecodedItem>(decodedItem(), minLength: 0, maxLength: maxLength);

/// A Partial_Sequence-like string of 0 to [maxLength] `.` and `-`
/// characters. REQ-KEY-10.
Arbitrary<String> symbolString({int maxLength = 20}) => list<String>(
  constantFrom<String>(const <String>['.', '-']),
  minLength: 0,
  maxLength: maxLength,
).map((symbols) => symbols.join());

/// One Composer operation in a generated sequence. REQ-COMPOSE-2,
/// REQ-COMPOSE-3, REQ-COMPOSE-4.
sealed class ComposerOp {
  const ComposerOp();
}

/// Append one Decoded_Item. REQ-COMPOSE-2.
final class AppendOp extends ComposerOp {
  const AppendOp(this.item);
  final DecodedItem item;
  @override
  String toString() => 'append($item)';
}

/// Undo the last item. REQ-COMPOSE-3.
final class UndoOp extends ComposerOp {
  const UndoOp();
  @override
  String toString() => 'undo';
}

/// Clear the Sentence. REQ-COMPOSE-4.
final class ClearOp extends ComposerOp {
  const ClearOp();
  @override
  String toString() => 'clear';
}

/// One Composer operation: mostly appends, so Sentences grow, with Undo
/// common and Clear rarer. REQ-COMPOSE-2, REQ-COMPOSE-3, REQ-COMPOSE-4.
Arbitrary<ComposerOp> composerOp() => frequency(<(int, Arbitrary<dynamic>)>[
  (6, decodedItem().map<ComposerOp>((item) => AppendOp(item))),
  (3, constant<ComposerOp>(const UndoOp())),
  (1, constant<ComposerOp>(const ClearOp())),
]).cast<ComposerOp>();

/// A list of 0 to [maxLength] Composer operations. REQ-COMPOSE-2,
/// REQ-COMPOSE-3, REQ-COMPOSE-4.
Arbitrary<List<ComposerOp>> composerOps({required int maxLength}) =>
    list<ComposerOp>(composerOp(), minLength: 0, maxLength: maxLength);

/// Largest timestamp drawn for a generated session call, in Microseconds.
/// REQ-KEY-4.
const int maxSessionTimestamp = 20000000;

/// One KeySession call in a generated sequence. REQ-KEY-4, REQ-KEY-7,
/// REQ-COMPOSE-2, REQ-COMPOSE-3, REQ-COMPOSE-4.
sealed class SessionCall {
  const SessionCall();
}

/// `press(t)`. REQ-KEY-4, REQ-KEY-7.
final class PressCall extends SessionCall {
  const PressCall(this.t);
  final int t;
  @override
  String toString() => 'press($t)';
}

/// `release(t)`. REQ-KEY-4, REQ-KEY-7.
final class ReleaseCall extends SessionCall {
  const ReleaseCall(this.t);
  final int t;
  @override
  String toString() => 'release($t)';
}

/// `advanceTo(t)`. REQ-KEY-4, REQ-COMPOSE-2.
final class AdvanceCall extends SessionCall {
  const AdvanceCall(this.t);
  final int t;
  @override
  String toString() => 'advanceTo($t)';
}

/// `undo()`. REQ-COMPOSE-3.
final class UndoCall extends SessionCall {
  const UndoCall();
  @override
  String toString() => 'undo';
}

/// `clear()`. REQ-COMPOSE-4.
final class ClearCall extends SessionCall {
  const ClearCall();
  @override
  String toString() => 'clear';
}

/// One KeySession call: press, release or advanceTo with an independent
/// timestamp from 0 to [maxSessionTimestamp] (so timestamps can go
/// backwards and presses and releases can repeat), undo or clear.
/// REQ-KEY-4, REQ-KEY-7, REQ-COMPOSE-2, REQ-COMPOSE-3, REQ-COMPOSE-4.
Arbitrary<SessionCall> sessionCall() {
  Arbitrary<int> stamp() => integer(min: 0, max: maxSessionTimestamp);
  return oneOf(<Arbitrary<dynamic>>[
    stamp().map<SessionCall>((t) => PressCall(t)),
    stamp().map<SessionCall>((t) => ReleaseCall(t)),
    stamp().map<SessionCall>((t) => AdvanceCall(t)),
    constant<SessionCall>(const UndoCall()),
    constant<SessionCall>(const ClearCall()),
  ]).cast<SessionCall>();
}

/// A list of 0 to [maxLength] KeySession calls. REQ-KEY-4, REQ-KEY-7,
/// REQ-COMPOSE-2.
Arbitrary<List<SessionCall>> sessionCalls({required int maxLength}) =>
    list<SessionCall>(sessionCall(), minLength: 0, maxLength: maxLength);
