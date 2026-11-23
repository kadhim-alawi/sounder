/// One classified press: a dit or a dah. REQ-TIMING-3.
enum MorseSymbol {
  /// A short press, `.`. REQ-TIMING-3.
  dit('.'),

  /// A long press, `-`. REQ-TIMING-3.
  dah('-');

  /// Creates a symbol with its [code] character. REQ-TIMING-3.
  const MorseSymbol(this.code);

  /// `.` or `-`, as in CodeTable. REQ-TIMING-3.
  final String code;
}
