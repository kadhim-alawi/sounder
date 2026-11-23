import '../press.dart';
import '../switch_event.dart';
import '../switch_event_kind.dart';
import '../timing_input_error_kind.dart';
import '../timing_input_exception.dart';

// Internal helpers shared by BatchDecoder and Calibrator (design Decision
// T5). Not exported from lib/morse_core.dart. Both functions only read the
// list they are given. REQ-EVENT-6.

/// Returns the first violation of the Valid_Event_Sequence rules in
/// [events], or null when [events] is a Valid_Event_Sequence. Never throws.
///
/// Scans the events in index order and returns at the lowest index where a
/// rule breaks. At one index the kinds are checked in this order: timestamp
/// out of range, starts with release (index 0), two presses in a row, two
/// releases in a row, decreasing timestamp. Ends with press is reported only
/// when no earlier rule breaks, with the index of the last event. The list is
/// only read, never changed. REQ-EVENT-3, REQ-EVENT-5, REQ-EVENT-6.
TimingInputException? firstEventViolation(List<SwitchEvent> events) {
  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    if (e.timestamp < SwitchEvent.minTimestamp ||
        e.timestamp > SwitchEvent.maxTimestamp) {
      return TimingInputException(
        TimingInputErrorKind.timestampOutOfRange,
        index: i,
      );
    }
    if (i == 0) {
      if (e.kind == SwitchEventKind.release) {
        return TimingInputException(
          TimingInputErrorKind.startsWithRelease,
          index: i,
        );
      }
      continue;
    }
    final previous = events[i - 1];
    if (e.kind == SwitchEventKind.press &&
        previous.kind == SwitchEventKind.press) {
      return TimingInputException(
        TimingInputErrorKind.twoPressesInARow,
        index: i,
      );
    }
    if (e.kind == SwitchEventKind.release &&
        previous.kind == SwitchEventKind.release) {
      return TimingInputException(
        TimingInputErrorKind.twoReleasesInARow,
        index: i,
      );
    }
    if (e.timestamp < previous.timestamp) {
      return TimingInputException(
        TimingInputErrorKind.decreasingTimestamp,
        index: i,
      );
    }
  }
  if (events.isNotEmpty && events.last.kind == SwitchEventKind.press) {
    return TimingInputException(
      TimingInputErrorKind.endsWithPress,
      index: events.length - 1,
    );
  }
  return null;
}

/// Pairs a Valid_Event_Sequence into Presses: event 2n is the press and
/// event 2n + 1 the release of Press n. The caller must check [events] with
/// [firstEventViolation] first. Returns a new list; [events] is not changed.
/// REQ-BATCH-1, REQ-CAL-5, REQ-EVENT-6.
List<Press> pairPresses(List<SwitchEvent> events) => [
  for (var i = 0; i + 1 < events.length; i += 2)
    Press(events[i].timestamp, events[i + 1].timestamp),
];
