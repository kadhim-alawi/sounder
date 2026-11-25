/// [SpeechService] backed by the `flutter_tts` plugin. REQ-SPEAK-1,
/// REQ-SPEAK-2, REQ-SPEAK-3.
library;

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'speech_service.dart';

/// Speaks through the platform voice using `flutter_tts` 4.2.5. REQ-SPEAK-1,
/// REQ-SPEAK-2, REQ-SPEAK-3, REQ-CI-3.
///
/// On web the plugin drops a `speak` call while an utterance is playing
/// (design R5). So while busy, a new [speak] call supersedes the previous one,
/// keeps its text in one pending slot and calls `stop()`; the pending text is
/// spoken when the plugin reports the cancel, the `interrupted` or `canceled`
/// error, or completion (design D7). Any other error code, an empty voice
/// list or a throw is a Speech_Failure (design D6).
///
/// The text is held only in the pending slot until it is passed to the
/// plugin, and is never printed or logged.
final class FlutterTtsSpeechService implements SpeechService {
  /// Creates the service. [tts] lets tests substitute the plugin object; by
  /// default a new `FlutterTts` is used. REQ-SPEAK-1.
  FlutterTtsSpeechService({FlutterTts? tts}) : _tts = tts ?? FlutterTts() {
    _tts.setCompletionHandler(_onCompletion);
    _tts.setCancelHandler(_onCancel);
    _tts.setErrorHandler(_onError);
  }

  /// Web Speech error codes produced by our own `stop()` (design D6).
  static const Set<String> _stopErrorCodes = {'interrupted', 'canceled'};

  final FlutterTts _tts;

  /// True from the plugin `speak` call until the utterance ends.
  bool _busy = false;

  /// True after `stop()` was called and before the plugin reported the end.
  bool _stopping = false;

  /// The text waiting to be spoken after the current utterance stops.
  String? _pending;

  /// Completes the [speak] call that owns the current or pending utterance.
  Completer<SpeechResult>? _completer;

  /// Requests the voice list so that Chrome starts filling it (design L2).
  /// Errors are ignored here; [speak] checks again. REQ-SPEAK-2.
  @override
  Future<void> init() async {
    try {
      await _tts.getVoices;
    } on Object {
      // A missing voice list is reported by speak as a Speech_Failure.
    }
  }

  /// Speaks [text] and reports how it ended (design D6, D7). REQ-SPEAK-1,
  /// REQ-SPEAK-3.
  @override
  Future<SpeechResult> speak(String text) async {
    final dynamic voices;
    try {
      voices = await _tts.getVoices;
    } on Object {
      return SpeechResult.failed;
    }
    if (voices is! List || voices.isEmpty) return SpeechResult.failed;

    final completer = Completer<SpeechResult>();
    if (_busy) {
      _completeWith(SpeechResult.superseded);
      _completer = completer;
      _pending = text;
      if (!_stopping) {
        _stopping = true;
        unawaited(_stopQuietly());
      }
    } else {
      _completer = completer;
      unawaited(_start(text));
    }
    return completer.future;
  }

  /// Passes [text] to the plugin. A throw is a Speech_Failure.
  Future<void> _start(String text) async {
    _busy = true;
    _stopping = false;
    try {
      await _tts.speak(text);
    } on Object {
      _finish(SpeechResult.failed);
    }
  }

  /// Calls `stop()`. If it throws, the pending text cannot be started safely,
  /// so the pending call fails.
  Future<void> _stopQuietly() async {
    try {
      await _tts.stop();
    } on Object {
      _pending = null;
      _finish(SpeechResult.failed);
    }
  }

  void _onCompletion() {
    if (!_busy) return;
    if (!_startPending()) _finish(SpeechResult.completed);
  }

  void _onCancel() {
    if (!_busy) return;
    if (!_startPending()) _finish(SpeechResult.superseded);
  }

  void _onError(dynamic message) {
    if (!_busy) return;
    if (_stopErrorCodes.contains(message?.toString())) {
      _onCancel();
    } else {
      _pending = null;
      _finish(SpeechResult.failed);
    }
  }

  /// Starts the pending text if there is one, clearing the slot. Returns
  /// whether it did.
  bool _startPending() {
    final next = _pending;
    if (next == null) return false;
    _pending = null;
    unawaited(_start(next));
    return true;
  }

  void _finish(SpeechResult result) {
    _busy = false;
    _stopping = false;
    _completeWith(result);
  }

  void _completeWith(SpeechResult result) {
    final c = _completer;
    _completer = null;
    if (c != null && !c.isCompleted) c.complete(result);
  }
}
