import 'code_table.dart';
import 'decoded_item_kind.dart';

/// One Decoded_Item: a Letter_Item, an Unknown_Letter_Item or a Word_Space,
/// discriminated by [kind]. REQ-BATCH-1, REQ-BATCH-2, REQ-BATCH-3.
final class DecodedItem {
  /// A Letter_Item for the uppercase [character]. REQ-BATCH-2.
  const DecodedItem.letter(String this.character)
      : kind = DecodedItemKind.letter,
        symbols = null;

  /// An Unknown_Letter_Item with a non-empty Symbol sequence [symbols] of
  /// `.` and `-`. REQ-BATCH-3.
  const DecodedItem.unknownLetter(String this.symbols)
      : kind = DecodedItemKind.unknownLetter,
        character = null;

  /// A Word_Space. REQ-BATCH-1.
  const DecodedItem.wordSpace()
      : kind = DecodedItemKind.wordSpace,
        character = null,
        symbols = null;

  /// A Letter_Item if CodeTable knows [symbols], else an
  /// Unknown_Letter_Item. Shared by BatchDecoder and LiveDecoder.
  /// REQ-BATCH-2, REQ-BATCH-3, REQ-LIVE-6.
  factory DecodedItem.fromSymbols(String symbols) {
    final character = _table.characterFor(symbols);
    return character == null
        ? DecodedItem.unknownLetter(symbols)
        : DecodedItem.letter(character);
  }

  // The 43 ITU-R M.1677-1 codes. REQ-BATCH-2.
  static const CodeTable _table = CodeTable();

  /// Which form this item is. REQ-BATCH-2, REQ-BATCH-3.
  final DecodedItemKind kind;

  /// Uppercase character, Letter_Items only; null otherwise. REQ-BATCH-2.
  final String? character;

  /// Symbol sequence, Unknown_Letter_Items only; null otherwise.
  /// REQ-BATCH-3.
  final String? symbols;

  /// Value equality on [kind], [character] and [symbols]. REQ-LIVE-11.
  @override
  bool operator ==(Object other) =>
      other is DecodedItem &&
      other.kind == kind &&
      other.character == character &&
      other.symbols == symbols;

  /// Hash consistent with `==`. REQ-LIVE-11.
  @override
  int get hashCode => Object.hash(kind, character, symbols);

  /// The kind only, never the character or symbols, so decoded user text
  /// cannot reach a log (T12). REQ-ENGINE-5.
  @override
  String toString() => 'DecodedItem(${kind.name})';
}
