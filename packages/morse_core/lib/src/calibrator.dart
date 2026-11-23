import 'calibration.dart';
import 'calibration_rejection.dart';
import 'calibration_result.dart';
import 'code_table.dart';
import 'debouncer.dart';
import 'internal/event_rules.dart';
import 'press.dart';
import 'rejection_reason.dart';
import 'switch_event.dart';
import 'timing_config.dart';

/// Measures a Calibration from an Event_Sequence keyed for a
/// Calibration_Word. REQ-CAL-1, REQ-CAL-6.
final class Calibrator {
  /// Creates a Calibrator that debounces with [config], or with
  /// [TimingConfig.defaults] when [config] is null. REQ-CAL-5.
  Calibrator([TimingConfig? config]) : config = config ?? TimingConfig.defaults;

  /// The Calibration_Word used when the caller supplies none. REQ-CAL-1.
  static const String defaultWord = 'PARIS';

  /// The Timing_Config whose Debounce_Time is applied before measuring.
  /// REQ-CAL-5, REQ-DEBOUNCE-2.
  final TimingConfig config;

  /// Calibrates from [events] keyed for [word].
  ///
  /// Returns exactly one result and never throws: an accepted
  /// [CalibrationResult] with a Calibration, or a rejected one with the
  /// first Rejection_Reason in REQ-CAL-12 order. [events] is only read.
  /// REQ-CAL-2, REQ-CAL-3, REQ-CAL-5 to REQ-CAL-13, REQ-CAL-20, REQ-CAL-30,
  /// REQ-CAL-31, REQ-EVENT-2, REQ-EVENT-5, REQ-EVENT-6.
  CalibrationResult calibrate(
    List<SwitchEvent> events, {
    String word = defaultWord,
  }) {
    // 1. Word check; the events are not looked at. REQ-CAL-3, REQ-CAL-21.
    final wordProblem = _wordProblem(word);
    if (wordProblem != null) {
      return _reject(RejectionReason.unsuitableWord, wordProblem);
    }

    // 2. Expected plan. Case folding comes from CodeTable. REQ-CAL-2,
    // REQ-CAL-20.
    final plan = _Plan.of(word);

    // 3. Event check. REQ-CAL-11, REQ-EVENT-5.
    final violation = firstEventViolation(events);
    if (violation != null) {
      return _reject(
        RejectionReason.invalidEvents,
        'Event ${violation.index} is invalid: ${violation.kind.phrase}.',
      );
    }

    // 4. Debounce. A Valid_Event_Sequence pairs into a valid Press list, so
    // this cannot throw. REQ-CAL-5.
    final presses = Debouncer(config).debounce(pairPresses(events));

    // 5. Count. REQ-CAL-8.
    final expected = plan.symbols.length;
    if (presses.length != expected) {
      return _reject(
        RejectionReason.wrongPressCount,
        'Expected $expected presses but received ${presses.length} '
        'after debounce.',
      );
    }

    // 6. Separation: presses, then gaps. REQ-CAL-9, REQ-CAL-10.
    final dits = <int>[];
    final dahs = <int>[];
    for (var i = 0; i < presses.length; i++) {
      (plan.symbols[i] == '.' ? dits : dahs).add(presses[i].duration);
    }
    final insideGaps = <int>[];
    final betweenGaps = <int>[];
    for (var j = 0; j + 1 < presses.length; j++) {
      final gap = _gap(presses[j], presses[j + 1]);
      (plan.gapIsBetweenLetters[j] ? betweenGaps : insideGaps).add(gap);
    }
    if (_max(dits) >= _min(dahs)) {
      return _reject(
        RejectionReason.pressesOverlap,
        'Short and long presses could not be told apart.',
      );
    }
    if (_max(insideGaps) >= _min(betweenGaps)) {
      return _reject(
        RejectionReason.gapsOverlap,
        'Pauses inside letters and pauses between letters could not be told '
        'apart.',
      );
    }

    // 7. Medians. REQ-CAL-6, REQ-CAL-7.
    final medians = [
      _median(dits),
      _median(dahs),
      _median(insideGaps),
      _median(betweenGaps),
    ];

    // 8. Zero check. REQ-CAL-30.
    if (medians.any((m) => m == 0)) {
      return _reject(
        RejectionReason.zeroDuration,
        'A press or pause was too short to measure.',
      );
    }

    // 9. Cap check: timestamps span 2^52, the Calibration holds 2^40.
    // REQ-CAL-14, REQ-CAL-31.
    if (medians.any((m) => m > _maxDuration)) {
      return _reject(
        RejectionReason.durationTooLong,
        'A press or pause was too long to measure.',
      );
    }

    // 10. Accept. Steps 6, 8 and 9 make the constructor total. REQ-CAL-31.
    return CalibrationResult.accepted(
      Calibration(
        ditLength: medians[0],
        dahLength: medians[1],
        symbolGap: medians[2],
        letterGap: medians[3],
      ),
    );
  }

  // Largest value a Calibration accepts, 2^40 Microseconds. REQ-CAL-14.
  static const int _maxDuration = 1 << 40;

  // Most UTF-16 code units in a Calibration_Word. REQ-CAL-3.
  static const int _maxWordLength = 16;

  static const CodeTable _table = CodeTable();

  static CalibrationResult _reject(RejectionReason reason, String message) =>
      CalibrationResult.rejected(CalibrationRejection(reason, message));

  // The message for the first failed REQ-CAL-3 rule, or null when [word]
  // is suitable. Characters are UTF-16 code units.
  static String? _wordProblem(String word) {
    if (word.isEmpty) return 'The calibration word is empty.';
    if (word.length > _maxWordLength) {
      return 'The calibration word has more than $_maxWordLength characters.';
    }
    final codes = StringBuffer();
    var hasLongCode = false;
    for (final unit in word.codeUnits) {
      final character = String.fromCharCode(unit);
      final code = character == ' ' ? null : _table.codeFor(character);
      if (code == null) {
        return 'The calibration word contains a space or a character that '
            'has no Morse code.';
      }
      codes.write(code);
      if (code.length >= 2) hasLongCode = true;
    }
    if (word.length < 2) {
      return 'The calibration word has fewer than two characters.';
    }
    final all = codes.toString();
    if (!all.contains('.')) {
      return 'The calibration word has no short press.';
    }
    if (!all.contains('-')) {
      return 'The calibration word has no long press.';
    }
    if (!hasLongCode) {
      return 'The calibration word has no character with two or more '
          'symbols.';
    }
    return null;
  }

  static int _gap(Press previous, Press next) =>
      next.pressedAt - previous.releasedAt;

  static int _max(List<int> values) =>
      values.reduce((a, b) => a > b ? a : b);

  static int _min(List<int> values) =>
      values.reduce((a, b) => a < b ? a : b);

  // Middle value; for an even count, the mean of the two middle values
  // rounded half up, computed without forming their sum. REQ-CAL-7.
  static int _median(List<int> values) {
    final sorted = List<int>.of(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    final a = sorted[mid - 1];
    final b = sorted[mid];
    return a + (b - a + 1) ~/ 2;
  }
}

// The expected Symbol of every Press and the class of every Gap for a
// suitable Calibration_Word. REQ-CAL-2, REQ-CAL-4.
final class _Plan {
  _Plan(this.symbols, this.gapIsBetweenLetters);

  factory _Plan.of(String word) {
    const table = CodeTable();
    final symbols = StringBuffer();
    final between = <bool>[];
    for (final unit in word.codeUnits) {
      final code = table.codeFor(String.fromCharCode(unit))!;
      for (var k = 0; k < code.length; k++) {
        // Gap before this Symbol: between letters when it starts a
        // character after the first.
        if (symbols.isNotEmpty) between.add(k == 0);
        symbols.write(code[k]);
      }
    }
    return _Plan(symbols.toString(), between);
  }

  final String symbols;
  final List<bool> gapIsBetweenLetters;
}
