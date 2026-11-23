import 'dart:collection';

import 'calibration.dart';
import 'classifier.dart';
import 'decoded_item.dart';
import 'switch_event.dart';
import 'timing_config.dart';
import 'timing_input_error_kind.dart';
import 'timing_input_exception.dart';

/// Incremental decoder for the Key screen. Accepts presses, releases and
/// `advanceTo(now)` calls one at a time and exposes the completed
/// Decoded_Items and the Partial_Sequence of the letter being keyed.
///
/// The caller owns the clock; this class never reads time. It shares the
/// Classifier and `DecodedItem.fromSymbols` with the Batch_Decoder but runs
/// its own state machine (design Decision T6). REQ-LIVE-1, REQ-LIVE-11.
final class LiveDecoder {
  /// Creates a decoder for [calibration] and [config].
  ///
  /// Throws a [TimingInputException] of kind
  /// [TimingInputErrorKind.debounceTimeTooLong] when the Debounce_Time is
  /// greater than the Dit_Length or greater than the Symbol_Gap. A
  /// Debounce_Time equal to either is accepted. REQ-LIVE-1, REQ-TIMING-9.
  LiveDecoder(Calibration calibration, TimingConfig config)
    : classifier = Classifier(calibration, config),
      _debounceTime = config.debounceTime {
    if (config.debounceTime > calibration.ditLength ||
        config.debounceTime > calibration.symbolGap) {
      throw TimingInputException(TimingInputErrorKind.debounceTimeTooLong);
    }
  }

  /// The Classifier holding the Calibration, the Timing_Config and the three
  /// thresholds this decoder uses. REQ-LIVE-1, REQ-TIMING-1.
  final Classifier classifier;

  // Debounce_Time read from the Timing_Config. REQ-DEBOUNCE-2.
  final int _debounceTime;

  // Completed Decoded_Items; only ever appended to. REQ-LIVE-8.
  final List<DecodedItem> _items = <DecodedItem>[];
  late final List<DecodedItem> _itemsView = UnmodifiableListView(_items);

  // The Partial_Sequence. REQ-LIVE-2.
  final StringBuffer _partial = StringBuffer();

  // Switch is down. REQ-LIVE-3.
  bool _pressed = false;

  // Latest timestamp received by any call. REQ-LIVE-9, REQ-LIVE-10.
  int? _latest;

  // Press and release calls accepted so far; the index of an invalid
  // press or release call (design Decision T9). REQ-LIVE-9.
  int _eventCount = 0;

  // The Pending_Press: start is set while held or released but not yet
  // confirmed; end is set once released. REQ-LIVE-4, REQ-LIVE-5.
  int? _pendingStart;
  int? _pendingEnd;

  // Release timestamp of the last Press appended to the Partial_Sequence
  // (r in the design). REQ-LIVE-6, REQ-LIVE-7, REQ-LIVE-14.
  int? _lastKeptRelease;

  /// The completed Decoded_Items in time order, as an unmodifiable view that
  /// is only ever appended to. REQ-LIVE-2, REQ-LIVE-8.
  List<DecodedItem> get items => _itemsView;

  /// The confirmed Symbols of the letter being built, for example `.-`.
  /// Empty when no letter is in progress. REQ-LIVE-2, REQ-LIVE-4.
  String get partialSequence => _partial.toString();

  /// Whether the switch is currently pressed. REQ-LIVE-2, REQ-LIVE-3.
  bool get isPressed => _pressed;

  /// The latest timestamp received by any accepted call, or null before the
  /// first one. REQ-LIVE-9, REQ-LIVE-10.
  int? get latestTimestamp => _latest;

  /// Records a press at [timestamp].
  ///
  /// When the previous release was less than the Debounce_Time ago, the new
  /// Press merges with the previous one. Otherwise the previous Press is
  /// confirmed or discarded and the letter may complete first. Throws a
  /// [TimingInputException] and changes nothing for an out-of-range or
  /// decreasing timestamp, or a press while pressed.
  /// REQ-LIVE-3, REQ-LIVE-4, REQ-LIVE-5, REQ-LIVE-6, REQ-LIVE-9, REQ-EVENT-5.
  void press(int timestamp) {
    _checkTimestamp(timestamp, index: _eventCount);
    if (_pressed) {
      throw TimingInputException(
        TimingInputErrorKind.twoPressesInARow,
        index: _eventCount,
      );
    }

    final end = _pendingEnd;
    if (end != null && timestamp - end < _debounceTime) {
      // Merge: keep the pending start, reopen the press. REQ-LIVE-5.
      _pendingEnd = null;
    } else {
      _settle(timestamp);
      _pendingStart = timestamp;
      _pendingEnd = null;
    }
    _pressed = true;
    _latest = timestamp;
    _eventCount++;
  }

  /// Records a release at [timestamp]. No Symbol is confirmed here; the next
  /// `advanceTo` or press call confirms it once the Debounce_Time has passed.
  /// Throws a [TimingInputException] and changes nothing for an out-of-range
  /// or decreasing timestamp, or a release while not pressed.
  /// REQ-LIVE-3, REQ-LIVE-4, REQ-LIVE-9, REQ-EVENT-5.
  void release(int timestamp) {
    _checkTimestamp(timestamp, index: _eventCount);
    if (!_pressed) {
      throw TimingInputException(
        _eventCount == 0
            ? TimingInputErrorKind.startsWithRelease
            : TimingInputErrorKind.twoReleasesInARow,
        index: _eventCount,
      );
    }

    _pendingEnd = timestamp;
    _pressed = false;
    _latest = timestamp;
    _eventCount++;
  }

  /// Tells the decoder that the time is now [now].
  ///
  /// While pressed, only records [now] as the latest timestamp. Otherwise
  /// confirms or discards a released Press once the Debounce_Time has passed,
  /// and completes the letter after a Letter_Gap_Threshold of silence. Never
  /// appends a Word_Space. Throws a [TimingInputException] with no index and
  /// changes nothing for an out-of-range or decreasing [now].
  /// REQ-LIVE-4, REQ-LIVE-6, REQ-LIVE-7, REQ-LIVE-10, REQ-LIVE-14,
  /// REQ-EVENT-5.
  void advanceTo(int now) {
    _checkTimestamp(now);
    if (!_pressed) _settle(now);
    _latest = now;
  }

  // Validation shared by all calls; runs before any field changes.
  // REQ-LIVE-9, REQ-EVENT-5.
  void _checkTimestamp(int timestamp, {int? index}) {
    if (timestamp < SwitchEvent.minTimestamp ||
        timestamp > SwitchEvent.maxTimestamp) {
      throw TimingInputException(
        TimingInputErrorKind.timestampOutOfRange,
        index: index,
      );
    }
    final latest = _latest;
    if (latest != null && timestamp < latest) {
      throw TimingInputException(
        TimingInputErrorKind.decreasingTimestamp,
        index: index,
      );
    }
  }

  // Confirms or discards the released Pending_Press once the Debounce_Time
  // has passed, then completes the letter if the silence, or the Gap to the
  // Pending_Press, reaches the Letter_Gap_Threshold (design Decision T7).
  // REQ-LIVE-4, REQ-LIVE-6, REQ-LIVE-14.
  void _settle(int now) {
    final start = _pendingStart;
    final end = _pendingEnd;
    if (start != null && end != null && now - end >= _debounceTime) {
      if (end - start >= _debounceTime) {
        _appendKept(start, end);
      }
      _pendingStart = null;
      _pendingEnd = null;
    }

    final r = _lastKeptRelease;
    if (_partial.isEmpty || r == null) return;
    final pendingStart = _pendingStart;
    final gapEnd = pendingStart ?? now;
    if (gapEnd - r >= classifier.letterGapThreshold) _flush();
  }

  // Appends the Symbol of a confirmed Press, first completing the letter on
  // a between-letters Gap and adding a Word_Space on a between-words Gap.
  // REQ-LIVE-4, REQ-LIVE-6, REQ-LIVE-7.
  void _appendKept(int start, int end) {
    final r = _lastKeptRelease;
    if (r != null) {
      final gap = start - r;
      if (_partial.isNotEmpty && gap >= classifier.letterGapThreshold) {
        _flush();
      }
      if (_partial.isEmpty &&
          _items.isNotEmpty &&
          gap >= classifier.wordGapThreshold) {
        _items.add(const DecodedItem.wordSpace());
      }
    }
    _partial.write(classifier.classifyPress(end - start).code);
    _lastKeptRelease = end;
  }

  // Appends the Partial_Sequence as a letter and clears it.
  // REQ-LIVE-6, REQ-BATCH-2, REQ-BATCH-3.
  void _flush() {
    _items.add(DecodedItem.fromSymbols(_partial.toString()));
    _partial.clear();
  }
}
