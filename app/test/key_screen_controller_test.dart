import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sounder/compose/sentence_text.dart';
import 'package:sounder/speech/speech_service.dart';
import 'package:sounder/ui/key_screen_controller.dart';
import 'package:sounder/ui/key_screen_state.dart';

import 'support/manual_time_base.dart';
import 'support/mock_speech_service.dart';

void main() {
  late ManualTimeBase clock;
  late MockSpeechService speech;
  late ProviderContainer container;

  KeyScreenController controller() =>
      container.read(keyScreenControllerProvider.notifier);
  KeyScreenState current() => container.read(keyScreenControllerProvider);

  // Keys one 100 ms dit starting at [t] Microseconds.
  void dit(int t) {
    clock.now = t;
    controller().press(Duration.zero);
    clock.now = t + 100000;
    controller().release(Duration.zero);
  }

  void frameAt(int t) {
    clock.now = t;
    controller().frame(Duration.zero);
  }

  // Keys `E` (one dit) and lets the letter complete.
  void keyE(int t) {
    dit(t);
    frameAt(t + 800000);
  }

  setUp(() {
    clock = ManualTimeBase();
    speech = MockSpeechService();
    container = ProviderContainer(
      overrides: [
        timeBaseProvider.overrideWithValue(clock),
        speechServiceProvider.overrideWithValue(speech),
      ],
    );
    addTearDown(container.dispose);
  });

  test(
    'REQ-KEY-4, REQ-KEY-5, REQ-COMPOSE-2: a dit and a later frame give E',
    () {
      keyE(1000000);
      expect(sentenceText(current().sentence), 'E');
      expect(current().partialSequence, '');
      expect(current().isPressed, isFalse);
    },
  );

  test('REQ-KEY-8: press and release publish the switch state', () {
    clock.now = 1000000;
    controller().press(Duration.zero);
    expect(current().isPressed, isTrue);
    clock.now = 1100000;
    controller().release(Duration.zero);
    expect(current().isPressed, isFalse);
  });

  test('REQ-KEY-7: a second press while held changes nothing', () {
    clock.now = 1000000;
    controller().press(Duration.zero);
    final before = current();
    clock.now = 1050000;
    controller().press(Duration.zero);
    expect(identical(current(), before), isTrue);
  });

  test('REQ-KEY-12: an idle frame publishes no new state', () {
    keyE(1000000);
    final before = current();
    var notified = 0;
    container.listen(keyScreenControllerProvider, (_, _) => notified++);
    frameAt(2000000);
    frameAt(3000000);
    expect(notified, 0);
    expect(identical(current(), before), isTrue);
  });

  test(
    'REQ-COMPOSE-3, REQ-COMPOSE-4: undo and clear keep the Partial_Sequence',
    () {
      keyE(1000000);
      keyE(2000000);
      dit(3000000);
      frameAt(3150000);
      expect(current().partialSequence, '.');
      controller().undo();
      expect(sentenceText(current().sentence), 'E');
      expect(current().partialSequence, '.');
      controller().clear();
      expect(current().sentence, isEmpty);
      expect(current().partialSequence, '.');
    },
  );

  test(
    'REQ-SPEAK-2: an empty Speak_Text makes no Speech_Service call',
    () async {
      await controller().speak();
      expect(speech.spoken, isEmpty);
      expect(current().fallbackVisible, isFalse);
    },
  );

  test('REQ-SPEAK-1, REQ-COMPOSE-5: one call with the Speak_Text, Sentence '
      'unchanged', () async {
    keyE(1000000);
    dit(2000000);
    final before = current().sentence;
    await controller().speak();
    expect(speech.spoken, ['E']);
    expect(current().sentence, before);
  });

  test('REQ-SPEAK-3, REQ-SPEAK-5: failed shows the Fallback_View, completed '
      'hides it, superseded leaves it', () async {
    keyE(1000000);
    speech.result = SpeechResult.failed;
    await controller().speak();
    expect(current().fallbackVisible, isTrue);
    speech.result = SpeechResult.superseded;
    await controller().speak();
    expect(current().fallbackVisible, isTrue);
    speech.result = SpeechResult.completed;
    await controller().speak();
    expect(current().fallbackVisible, isFalse);
    expect(speech.spoken, ['E', 'E', 'E']);
    expect(sentenceText(current().sentence), 'E');
  });

  test('REQ-SPEAK-3, REQ-SPEAK-4: closeFallback hides the Fallback_View and '
      'is a no-op when hidden', () async {
    keyE(1000000);
    final hidden = current();
    controller().closeFallback();
    expect(identical(current(), hidden), isTrue);
    speech.result = SpeechResult.failed;
    await controller().speak();
    controller().closeFallback();
    expect(current().fallbackVisible, isFalse);
    expect(sentenceText(current().sentence), 'E');
    expect(speech.spoken, ['E']);
  });
}
