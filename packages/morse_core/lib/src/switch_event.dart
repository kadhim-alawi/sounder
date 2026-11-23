import 'switch_event_kind.dart';

/// One press or release of the switch, with a timestamp in Microseconds.
///
/// Only differences between timestamps are used, so any value from
/// [minTimestamp] to [maxTimestamp] is accepted, including zero and negative
/// values. REQ-EVENT-1.
final class SwitchEvent {
  /// Creates an event of [kind] at [timestamp]. Never throws; the range is
  /// checked by the consumers (REQ-EVENT-5). REQ-EVENT-1.
  const SwitchEvent(this.kind, this.timestamp);

  /// Creates a press event at [timestamp]. REQ-EVENT-1.
  const SwitchEvent.press(int timestamp)
      : this(SwitchEventKind.press, timestamp);

  /// Creates a release event at [timestamp]. REQ-EVENT-1.
  const SwitchEvent.release(int timestamp)
      : this(SwitchEventKind.release, timestamp);

  /// Smallest accepted timestamp, −2^52 Microseconds. REQ-EVENT-1.
  static const int minTimestamp = -4503599627370496;

  /// Largest accepted timestamp, 2^52 Microseconds. REQ-EVENT-1.
  static const int maxTimestamp = 4503599627370496;

  /// Whether the switch closed or opened. REQ-EVENT-1.
  final SwitchEventKind kind;

  /// The time of the event in Microseconds. REQ-EVENT-1.
  final int timestamp;

  /// Value equality on [kind] and [timestamp]. REQ-EVENT-6.
  @override
  bool operator ==(Object other) =>
      other is SwitchEvent &&
      other.kind == kind &&
      other.timestamp == timestamp;

  /// Hash consistent with `==`. REQ-EVENT-6.
  @override
  int get hashCode => Object.hash(kind, timestamp);

  /// The kind and timestamp, for test output. Timestamps are not user text.
  /// REQ-EVENT-1.
  @override
  String toString() => 'SwitchEvent(${kind.name}, $timestamp)';
}
