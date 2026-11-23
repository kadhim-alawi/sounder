/// Which of the three Decoded_Item forms a `DecodedItem` is.
/// REQ-BATCH-2, REQ-BATCH-3, REQ-BATCH-4.
enum DecodedItemKind {
  /// A Letter_Item: a Symbol sequence CodeTable knows. REQ-BATCH-2.
  letter,

  /// An Unknown_Letter_Item: a Symbol sequence CodeTable does not know.
  /// REQ-BATCH-3.
  unknownLetter,

  /// A Word_Space between two words. REQ-BATCH-1.
  wordSpace,
}
