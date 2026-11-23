import 'timing_input_error_kind.dart';

/// The Timing_Input_Error raised by the Timing_Engine for invalid input.
///
/// It implements `Exception` because it reports bad input a caller is
/// expected to catch. Its [message] is built from [kind] and [index] alone,
/// so no timestamp, duration, Symbol or character can reach it.
/// REQ-EVENT-3, REQ-EVENT-4, REQ-ENGINE-5.
final class TimingInputException implements Exception {
  /// Creates the error of [kind], with the zero-based [index] of the event or
  /// Press involved, if any. REQ-EVENT-3, REQ-EVENT-4.
  TimingInputException(this.kind, {this.index});

  /// The broken rule, as a value tests can compare. REQ-EVENT-3.
  final TimingInputErrorKind kind;

  /// Zero-based event or Press index, where one is involved; otherwise null.
  /// REQ-EVENT-3, REQ-DEBOUNCE-20.
  final int? index;

  /// The English message, for example `"Event 4: two presses in a row."`,
  /// `"Press 2: press is released before it is pressed."` or
  /// `"Invalid timing: debounce time is negative."`. REQ-EVENT-4,
  /// REQ-ENGINE-5.
  String get message {
    final i = index;
    if (i == null) return 'Invalid timing: ${kind.phrase}.';
    final noun = _pressIndexKinds.contains(kind) ? 'Press' : 'Event';
    return '$noun $i: ${kind.phrase}.';
  }

  /// Returns [message] only. REQ-ENGINE-5.
  @override
  String toString() => message;
}

// Kinds raised by the Debouncer, whose index counts Presses, not events.
// REQ-DEBOUNCE-20.
const Set<TimingInputErrorKind> _pressIndexKinds = {
  TimingInputErrorKind.releaseBeforePress,
  TimingInputErrorKind.pressOverlapsPrevious,
};
