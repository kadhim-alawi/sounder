import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../compose/key_session.dart';
import '../compose/sentence_text.dart';
import '../input/time_base.dart';
import '../speech/flutter_tts_speech_service.dart';
import '../speech/speech_service.dart';
import 'key_screen_state.dart';

/// The one Time_Base for every Live_Decoder timestamp. Tests override it
/// with a test-controlled clock (design D3). REQ-KEY-4.
final timeBaseProvider = Provider<TimeBase>((ref) => const PlatformTimeBase());

/// The Speech_Service used for Speak_Actions. Tests override it with a mock
/// defined under `app/test/` (REQ-CI-3). REQ-SPEAK-1.
final speechServiceProvider = Provider<SpeechService>(
  (ref) => FlutterTtsSpeechService(),
);

/// The Key_Screen controller and its published [KeyScreenState].
/// REQ-KEY-6, REQ-KEY-12.
final keyScreenControllerProvider =
    NotifierProvider<KeyScreenController, KeyScreenState>(
      KeyScreenController.new,
    );

/// Wraps one [KeySession] and publishes immutable [KeyScreenState]
/// snapshots (design D5). Every timestamp goes through the [TimeBase]
/// (REQ-KEY-4). Only [speak] calls the Speech_Service (REQ-SPEAK-2), and only
/// [undo] and [clear] change the Sentence apart from decoded items
/// (REQ-COMPOSE-5). Nothing here prints or logs the Sentence.
/// REQ-KEY-4, REQ-KEY-5, REQ-KEY-7, REQ-KEY-8, REQ-KEY-12, REQ-COMPOSE-2,
/// REQ-COMPOSE-3, REQ-COMPOSE-4, REQ-COMPOSE-5, REQ-SPEAK-1, REQ-SPEAK-2,
/// REQ-SPEAK-3, REQ-SPEAK-4, REQ-SPEAK-5.
final class KeyScreenController extends Notifier<KeyScreenState> {
  late KeySession _session;

  /// Creates the one Live_Decoder with the default Calibration through a new
  /// [KeySession] and returns the empty state. REQ-KEY-6.
  @override
  KeyScreenState build() {
    _session = KeySession();
    return KeyScreenState.initial();
  }

  /// A switch press at [platformTime]. A rejected press changes nothing and
  /// shows no error. REQ-KEY-1, REQ-KEY-3, REQ-KEY-4, REQ-KEY-7, REQ-KEY-8.
  void press(Duration platformTime) {
    if (_session.press(_stamp(platformTime))) _publish();
  }

  /// A switch release at [platformTime]. A rejected release changes nothing
  /// and shows no error. REQ-KEY-1, REQ-KEY-3, REQ-KEY-4, REQ-KEY-7,
  /// REQ-KEY-8.
  void release(Duration platformTime) {
    if (_session.release(_stamp(platformTime))) _publish();
  }

  /// One Frame_Ticker frame at [platformTime]. Publishes a new state only
  /// when the Partial_Sequence, the Sentence length or the switch state
  /// changed, so an idle frame causes no rebuild. REQ-KEY-4, REQ-KEY-5,
  /// REQ-KEY-12, REQ-COMPOSE-2.
  void frame(Duration platformTime) {
    _session.advanceTo(_stamp(platformTime));
    final current = state;
    if (_session.partialSequence != current.partialSequence ||
        _session.sentence.length != current.sentence.length ||
        _session.isPressed != current.isPressed) {
      _publish();
    }
  }

  /// A Speak_Action. With an empty Speak_Text it makes no Speech_Service
  /// call. Otherwise it makes exactly one call: `failed` shows the
  /// Fallback_View, `completed` hides it, `superseded` leaves it as it is.
  /// The Sentence is never changed. REQ-SPEAK-1, REQ-SPEAK-2, REQ-SPEAK-3,
  /// REQ-SPEAK-5, REQ-COMPOSE-5.
  Future<void> speak() async {
    final text = speakText(_session.sentence);
    if (text.isEmpty) return;
    final result = await ref.read(speechServiceProvider).speak(text);
    if (!ref.mounted) return;
    switch (result) {
      case SpeechResult.failed:
        state = state.copyWith(fallbackVisible: true);
      case SpeechResult.completed:
        state = state.copyWith(fallbackVisible: false);
      case SpeechResult.superseded:
        break;
    }
  }

  /// Removes the last Decoded_Item of the Sentence; the Partial_Sequence is
  /// unchanged. REQ-COMPOSE-3.
  void undo() {
    _session.undo();
    _publish();
  }

  /// Makes the Sentence empty; the Partial_Sequence is unchanged.
  /// REQ-COMPOSE-4.
  void clear() {
    _session.clear();
    _publish();
  }

  /// Hides the Fallback_View with the Sentence unchanged. Does nothing when
  /// it is hidden. Used by the Close control and the Escape key.
  /// REQ-SPEAK-3, REQ-SPEAK-4, REQ-COMPOSE-5.
  void closeFallback() {
    if (!state.fallbackVisible) return;
    state = state.copyWith(fallbackVisible: false);
  }

  int _stamp(Duration platformTime) =>
      ref.read(timeBaseProvider).stamp(platformTime);

  void _publish() {
    state = state.copyWith(
      sentence: _session.sentence,
      partialSequence: _session.partialSequence,
      isPressed: _session.isPressed,
    );
  }
}
