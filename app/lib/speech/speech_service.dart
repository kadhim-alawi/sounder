/// The speech output interface used by the Key_Screen. REQ-SPEAK-1,
/// REQ-SPEAK-2, REQ-SPEAK-3.
library;

/// The outcome of one [SpeechService.speak] call. REQ-SPEAK-3, REQ-SPEAK-5.
enum SpeechResult {
  /// The platform voice finished speaking the text. REQ-SPEAK-5.
  completed,

  /// Speaking did not start or did not complete: no voice was available, the
  /// plugin threw, or the plugin reported an error (design D6). REQ-SPEAK-3.
  failed,

  /// A later [SpeechService.speak] call replaced this one before it finished
  /// (design D7). Neither a success nor a failure. REQ-SPEAK-1.
  superseded,
}

/// Speaks text it is given and never speaks on its own. REQ-SPEAK-1,
/// REQ-SPEAK-2.
abstract interface class SpeechService {
  /// Prepares the platform voice, for example by requesting the voice list
  /// early (design R5, L2). Speaks nothing. REQ-SPEAK-2.
  Future<void> init();

  /// Speaks [text] once and reports how it ended. Called only for a
  /// Speak_Action with a non-empty Speak_Text. REQ-SPEAK-1, REQ-SPEAK-3.
  Future<SpeechResult> speak(String text);
}
