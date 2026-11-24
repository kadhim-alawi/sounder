import 'package:morse_core/morse_core.dart';

import 'composer.dart';

/// Default Dit_Length in Microseconds until the calibrate screen exists (K2).
/// App default, not a decoder constant. REQ-KEY-6.
const int defaultDitLength = 100000;

/// Default Dah_Length in Microseconds (K2). REQ-KEY-6.
const int defaultDahLength = 300000;

/// Default Symbol_Gap in Microseconds (K2). REQ-KEY-6.
const int defaultSymbolGap = 250000;

/// Default Letter_Gap in Microseconds (K2). REQ-KEY-6.
const int defaultLetterGap = 700000;

/// One Live_Decoder plus the Spell mode Composer, with the timestamp clamp
/// and the item forwarding rules of the Key_Screen (design D2, D5).
///
/// Pure Dart: reads no clock, starts no timer and performs no I/O; the caller
/// passes every timestamp. REQ-KEY-4, REQ-KEY-6, REQ-KEY-7, REQ-COMPOSE-1,
/// REQ-COMPOSE-2, REQ-COMPOSE-3, REQ-COMPOSE-4.
final class KeySession {
  /// Creates a session with the default Calibration (Dit_Length 100,000,
  /// Dah_Length 300,000, Symbol_Gap 250,000, Letter_Gap 700,000
  /// Microseconds) and [TimingConfig.defaults]. REQ-KEY-6.
  KeySession()
    : this.withDecoder(
        LiveDecoder(
          Calibration(
            ditLength: defaultDitLength,
            dahLength: defaultDahLength,
            symbolGap: defaultSymbolGap,
            letterGap: defaultLetterGap,
          ),
          TimingConfig.defaults,
        ),
      );

  /// Creates a session around [decoder], for tests. The decoder should be
  /// new, with no items yet. REQ-KEY-6, REQ-COMPOSE-2.
  KeySession.withDecoder(LiveDecoder decoder)
    : _decoder = decoder,
      _forwarded = decoder.items.length;

  final LiveDecoder _decoder;
  final Composer _composer = Composer();

  // Number of decoder items already passed to the Composer. REQ-COMPOSE-2.
  int _forwarded;

  /// Records a press at [t], clamped to the decoder's latest timestamp.
  /// Returns false and changes nothing when the decoder rejects the call.
  /// REQ-KEY-4, REQ-KEY-7, REQ-COMPOSE-2.
  bool press(int t) => _run(t, _decoder.press);

  /// Records a release at [t], clamped to the decoder's latest timestamp.
  /// Returns false and changes nothing when the decoder rejects the call.
  /// REQ-KEY-4, REQ-KEY-7, REQ-COMPOSE-2.
  bool release(int t) => _run(t, _decoder.release);

  /// Advances the decoder to [t], clamped to its latest timestamp, and
  /// forwards any completed items to the Composer. A rejected call changes
  /// nothing. REQ-KEY-4, REQ-KEY-5, REQ-KEY-7, REQ-COMPOSE-2.
  void advanceTo(int t) {
    _run(t, _decoder.advanceTo);
  }

  /// Removes the last item of the Sentence. Never touches the decoder or its
  /// Partial_Sequence. REQ-COMPOSE-3.
  void undo() => _composer.undo();

  /// Makes the Sentence empty. Never touches the decoder or its
  /// Partial_Sequence. REQ-COMPOSE-4.
  void clear() => _composer.clear();

  /// The Sentence, as an unmodifiable list. REQ-COMPOSE-2, REQ-COMPOSE-5.
  List<DecodedItem> get sentence => _composer.sentence;

  /// The decoder's Partial_Sequence, for example `.-`. REQ-KEY-10.
  String get partialSequence => _decoder.partialSequence;

  /// Whether the switch is currently pressed. REQ-KEY-8.
  bool get isPressed => _decoder.isPressed;

  // Clamps [t] (D2), calls the decoder, discards a Timing_Input_Error, and
  // forwards new items once each, in order. REQ-KEY-4, REQ-KEY-7,
  // REQ-COMPOSE-2.
  bool _run(int t, void Function(int) call) {
    final latest = _decoder.latestTimestamp;
    final clamped = latest != null && latest > t ? latest : t;
    try {
      call(clamped);
    } on TimingInputException {
      return false;
    }
    final items = _decoder.items;
    for (var i = _forwarded; i < items.length; i++) {
      _composer.append(items[i]);
    }
    _forwarded = items.length;
    return true;
  }
}
