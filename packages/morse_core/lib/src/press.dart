/// One press Switch_Event and the release that follows it, in Microseconds.
/// REQ-DEBOUNCE-4.
final class Press {
  /// Creates a Press from [pressedAt] to [releasedAt]. Never throws; the
  /// Debouncer validates order (REQ-DEBOUNCE-20). REQ-DEBOUNCE-4.
  const Press(this.pressedAt, this.releasedAt);

  /// The press timestamp in Microseconds. REQ-DEBOUNCE-4.
  final int pressedAt;

  /// The release timestamp in Microseconds. REQ-DEBOUNCE-4.
  final int releasedAt;

  /// The release timestamp minus the press timestamp. REQ-DEBOUNCE-5.
  int get duration => releasedAt - pressedAt;

  /// Value equality on both timestamps. REQ-DEBOUNCE-6, REQ-DEBOUNCE-8.
  @override
  bool operator ==(Object other) =>
      other is Press &&
      other.pressedAt == pressedAt &&
      other.releasedAt == releasedAt;

  /// Hash consistent with `==`. REQ-DEBOUNCE-6.
  @override
  int get hashCode => Object.hash(pressedAt, releasedAt);

  /// Both timestamps, for test output. Timestamps are not user text.
  /// REQ-DEBOUNCE-4.
  @override
  String toString() => 'Press($pressedAt, $releasedAt)';
}
