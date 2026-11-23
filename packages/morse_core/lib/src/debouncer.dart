import 'press.dart';
import 'timing_config.dart';
import 'timing_input_error_kind.dart';
import 'timing_input_exception.dart';

/// Removes switch bounce from a time-ordered Press list, using the
/// Debounce_Time of its Timing_Config. REQ-DEBOUNCE-4.
final class Debouncer {
  /// Creates a Debouncer that reads the Debounce_Time only from [config].
  /// REQ-DEBOUNCE-2.
  const Debouncer(this.config);

  /// The Timing_Config that supplies the Debounce_Time. REQ-DEBOUNCE-2.
  final TimingConfig config;

  /// Debounces [presses]: first merges every run of Presses whose Gaps are
  /// shorter than the Debounce_Time, then drops every merged Press shorter
  /// than the Debounce_Time. A Gap equal to the Debounce_Time does not merge,
  /// and nothing merges after a drop.
  ///
  /// Returns a new unmodifiable list in time order; [presses] is not changed.
  ///
  /// Throws a [TimingInputException] of kind
  /// [TimingInputErrorKind.releaseBeforePress] or
  /// [TimingInputErrorKind.pressOverlapsPrevious], with the index of the
  /// first invalid Press, before any result is built. REQ-DEBOUNCE-4,
  /// REQ-DEBOUNCE-5, REQ-DEBOUNCE-6, REQ-DEBOUNCE-20.
  List<Press> debounce(List<Press> presses) {
    _validate(presses);
    if (presses.isEmpty) return List<Press>.unmodifiable(const <Press>[]);

    final d = config.debounceTime;
    final kept = <Press>[];

    void close(int start, int end) {
      // Drop: keep only merged Presses lasting at least d. REQ-DEBOUNCE-5.
      if (end - start >= d) kept.add(Press(start, end));
    }

    // Merge: extend the current run while the Gap is shorter than d.
    // REQ-DEBOUNCE-4.
    var start = presses.first.pressedAt;
    var end = presses.first.releasedAt;
    for (var i = 1; i < presses.length; i++) {
      final p = presses[i];
      if (p.pressedAt - end < d) {
        end = p.releasedAt;
      } else {
        close(start, end);
        start = p.pressedAt;
        end = p.releasedAt;
      }
    }
    close(start, end);

    return List<Press>.unmodifiable(kept);
  }

  // Throws for the lowest invalid index; at one index releaseBeforePress
  // wins. REQ-DEBOUNCE-20.
  static void _validate(List<Press> presses) {
    for (var i = 0; i < presses.length; i++) {
      final p = presses[i];
      if (p.releasedAt < p.pressedAt) {
        throw TimingInputException(
          TimingInputErrorKind.releaseBeforePress,
          index: i,
        );
      }
      if (i > 0 && p.pressedAt < presses[i - 1].releasedAt) {
        throw TimingInputException(
          TimingInputErrorKind.pressOverlapsPrevious,
          index: i,
        );
      }
    }
  }
}
