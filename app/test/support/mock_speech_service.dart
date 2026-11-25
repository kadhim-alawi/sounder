/// A test-only Speech_Service mock. REQ-CI-2, REQ-CI-3.
library;

import 'package:sounder/speech/speech_service.dart';

/// Records every [speak] text and returns a settable [SpeechResult].
/// Lives only under `app/test/` and its name begins with `Mock`. REQ-CI-3.
///
/// It speaks nothing and logs nothing. REQ-CI-2, REQ-CI-3.
final class MockSpeechService implements SpeechService {
  /// Creates a mock that answers every [speak] with [result]. REQ-CI-2.
  MockSpeechService({this.result = SpeechResult.completed});

  /// The result returned by the next and later [speak] calls. REQ-CI-2.
  SpeechResult result;

  /// The text of every [speak] call, in call order. REQ-CI-2.
  final List<String> spoken = <String>[];

  /// How many times [init] was called. REQ-CI-2.
  int initCalls = 0;

  /// Counts the call and does nothing else. REQ-CI-2.
  @override
  Future<void> init() async {
    initCalls++;
  }

  /// Records [text] and returns [result]. REQ-CI-2.
  @override
  Future<SpeechResult> speak(String text) async {
    spoken.add(text);
    return result;
  }
}
