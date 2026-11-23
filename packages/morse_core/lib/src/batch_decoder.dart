import 'calibration.dart';
import 'classifier.dart';
import 'debouncer.dart';
import 'decoded_item.dart';
import 'gap_class.dart';
import 'internal/event_rules.dart';
import 'switch_event.dart';
import 'timing_config.dart';
import 'timing_input_error_kind.dart';
import 'timing_input_exception.dart';

/// Decodes a whole Event_Sequence into letters, unknown letters and word
/// spaces, using thresholds from the user's Calibration. REQ-BATCH-1.
final class BatchDecoder {
  /// Creates a decoder for [calibration] and [config].
  ///
  /// Throws a [TimingInputException] of kind
  /// [TimingInputErrorKind.debounceTimeTooLong] when the Debounce_Time is
  /// greater than the Dit_Length or greater than the Symbol_Gap. A
  /// Debounce_Time equal to either is accepted. REQ-TIMING-9.
  BatchDecoder(Calibration calibration, TimingConfig config)
    : classifier = Classifier(calibration, config),
      _debouncer = Debouncer(config) {
    if (config.debounceTime > calibration.ditLength ||
        config.debounceTime > calibration.symbolGap) {
      throw TimingInputException(TimingInputErrorKind.debounceTimeTooLong);
    }
  }

  /// The Classifier holding the Calibration, the Timing_Config and the three
  /// thresholds this decoder uses. REQ-BATCH-1, REQ-TIMING-1.
  final Classifier classifier;

  // Applies the merge-then-drop rule with the configured Debounce_Time.
  // REQ-DEBOUNCE-4, REQ-DEBOUNCE-5.
  final Debouncer _debouncer;

  /// Decodes [events] and returns an unmodifiable list of Decoded_Items in
  /// time order.
  ///
  /// Checks the raw events before any debounce and throws the single
  /// [TimingInputException] for the lowest broken index when [events] is not
  /// a Valid_Event_Sequence. Otherwise debounces the Presses, classifies each
  /// Press and Gap, and groups Symbols into letters. A Word_Space is placed
  /// only between two letters, so the list is empty or starts and ends with
  /// a letter. Unknown Symbol sequences become Unknown_Letter_Items and
  /// decoding continues. [events] is only read, never changed.
  /// REQ-BATCH-1, REQ-BATCH-2, REQ-BATCH-3, REQ-BATCH-4, REQ-EVENT-2,
  /// REQ-EVENT-3, REQ-EVENT-5, REQ-EVENT-6.
  List<DecodedItem> decode(List<SwitchEvent> events) {
    final violation = firstEventViolation(events);
    if (violation != null) throw violation;

    // A Valid_Event_Sequence pairs into a valid Press list, so the
    // Debouncer cannot throw here.
    final kept = _debouncer.debounce(pairPresses(events));

    final output = <DecodedItem>[];
    final letter = StringBuffer();
    for (var i = 0; i < kept.length; i++) {
      if (i > 0) {
        final gap = kept[i].pressedAt - kept[i - 1].releasedAt;
        switch (classifier.classifyGap(gap)) {
          case GapClass.insideLetter:
            break;
          case GapClass.betweenLetters:
            _flush(letter, output);
          case GapClass.betweenWords:
            _flush(letter, output);
            output.add(const DecodedItem.wordSpace());
        }
      }
      letter.write(classifier.classifyPress(kept[i].duration).code);
    }
    _flush(letter, output);
    return List.unmodifiable(output);
  }

  // Appends the letter built so far, if any, and clears it.
  // REQ-BATCH-2, REQ-BATCH-3.
  static void _flush(StringBuffer letter, List<DecodedItem> output) {
    if (letter.isEmpty) return;
    output.add(DecodedItem.fromSymbols(letter.toString()));
    letter.clear();
  }
}
