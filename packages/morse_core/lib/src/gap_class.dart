/// The class of a Gap between two presses. REQ-TIMING-4.
enum GapClass {
  /// A Gap between two Symbols of the same letter. REQ-TIMING-4.
  insideLetter,

  /// A Gap that ends a letter but not a word. REQ-TIMING-4.
  betweenLetters,

  /// A Gap that ends a word. REQ-TIMING-4.
  betweenWords,
}
