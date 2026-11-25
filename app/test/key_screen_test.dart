// Widget tests for the Key_Screen. Every test drives the screen from a
// test-controlled Time_Base and never uses pumpAndSettle, because the
// Frame_Ticker schedules a frame every vsync (design D4).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sounder/speech/fallback_view.dart';
import 'package:sounder/speech/speech_service.dart';
import 'package:sounder/ui/key_screen.dart';
import 'package:sounder/compose/sentence_text.dart';
import 'package:sounder/ui/key_screen_controller.dart';
import 'package:sounder/ui/key_screen_state.dart';
import 'package:sounder/ui/on_screen_key.dart';
import 'package:sounder/ui/partial_display.dart';
import 'package:sounder/ui/sentence_display.dart';

import 'support/manual_time_base.dart';
import 'support/mock_speech_service.dart';

/// One frame at 60 Hz, in Microseconds.
const int frameStep = 16667;

/// Default Calibration Letter_Gap_Threshold: ⌈(250,000 + 700,000) / 2⌉.
const int letterGapThreshold = 475000;

/// The clock and speech mock shared by one widget test.
final class KeyScreenHarness {
  KeyScreenHarness(this.tester, this.clock, this.speech);

  final WidgetTester tester;
  final ManualTimeBase clock;
  final MockSpeechService speech;

  /// Advances [clock] to [targetUs] in [frameStep] steps, with one
  /// `tester.pump` per step. The last step lands exactly on [targetUs].
  /// [onFrame] runs after each pump with the frame's clock value.
  Future<void> frameTo(
    int targetUs, {
    void Function(int frameUs)? onFrame,
  }) async {
    while (clock.now < targetUs) {
      final next = clock.now + frameStep;
      clock.now = next < targetUs ? next : targetUs;
      await tester.pump(const Duration(microseconds: frameStep));
      onFrame?.call(clock.now);
    }
  }

  /// Sends a Space key-down at clock time [us].
  Future<void> spaceDown(int us) async {
    clock.now = us;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
  }

  /// Sends a Space key-up at clock time [us].
  Future<void> spaceUp(int us) async {
    clock.now = us;
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
  }

  /// Keys [count] dits of 100,000 µs with 100,000 µs gaps (inside the
  /// letter, below the Letter_Gap_Threshold), starting at [startUs].
  /// Returns the last release time.
  Future<int> keyDits(int startUs, int count) async {
    var at = startUs;
    for (var i = 0; i < count; i++) {
      await spaceDown(at);
      await spaceUp(at + 100000);
      await frameTo(at + 200000);
      at += 200000;
    }
    return at - 100000;
  }

  /// Keys `HI` starting at [startUs] and frames until the `I` is in the
  /// Sentence. H = `....`, then a 600,000 µs Letter_Gap (below the
  /// Word_Gap_Threshold of 2.0 × 700,000), then I = `..`.
  Future<void> keyHi(int startUs) async {
    final hRelease = await keyDits(startUs, 4);
    final iStart = hRelease + 600000;
    await frameTo(iStart);
    expect(sentenceText, 'H');
    final iRelease = await keyDits(iStart, 2);
    await frameTo(iRelease + 600000);
    expect(sentenceText, 'HI');
  }

  /// Sends a non-repeat Enter key-down and key-up (one Speak_Action),
  /// pumping one frame after each.
  Future<void> pressEnter() async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(microseconds: frameStep));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(microseconds: frameStep));
  }

  /// Keys one letter from [code] (`.` and `-`) starting at [startUs], with
  /// 100,000 µs dits, 300,000 µs dahs and 100,000 µs gaps inside the
  /// letter, then renders one frame 600,000 µs after the last release so the
  /// letter completes. Returns that frame time: a letter keyed from it stays
  /// in the same word; one keyed 1,400,000 µs later starts a new word (gap
  /// of 2,000,000 µs, above the Word_Gap_Threshold of 1,400,000).
  Future<int> keyLetter(int startUs, String code) async {
    var at = startUs;
    var lastRelease = startUs;
    for (final symbol in code.split('')) {
      await spaceDown(at);
      lastRelease = at + (symbol == '-' ? 300000 : 100000);
      await spaceUp(lastRelease);
      at = lastRelease + 100000;
    }
    clock.now = lastRelease + 600000;
    await tester.pump(const Duration(microseconds: frameStep));
    return clock.now;
  }

  /// Keys one dit at [startUs] and renders one frame 50,000 µs after the
  /// release, so the Partial_Sequence is `.` and the letter is not done.
  Future<void> startPartialDit(int startUs) async {
    await spaceDown(startUs);
    await spaceUp(startUs + 100000);
    clock.now = startUs + 150000;
    await tester.pump(const Duration(microseconds: frameStep));
  }

  /// The text the Key_Screen's Partial_Sequence display currently shows.
  String get partialText {
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(PartialDisplay),
        matching: find.byType(Text),
      ),
    );
    return text.data ?? '';
  }

  /// The label text on the On_Screen_Key: "Pressed" or "Released".
  String get keyLabel {
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(OnScreenKey),
        matching: find.byType(Text),
      ),
    );
    return text.data ?? '';
  }

  /// Whether the Fallback_View is shown.
  bool get fallbackShown => find.byType(FallbackView).evaluate().isNotEmpty;

  /// The current published Key_Screen state.
  KeyScreenState get state =>
      ProviderScope.containerOf(tester.element(find.byType(KeyScreen)))
          .read(keyScreenControllerProvider);

  /// The text the Key_Screen's own Sentence display currently shows. The
  /// Fallback_View has a second SentenceDisplay drawn above it in the Stack,
  /// so the first one in tree order is the Key_Screen's.
  String get sentenceText {
    final text = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(SentenceDisplay).first,
            matching: find.byType(Text),
          )
          .first,
    );
    return text.data ?? '';
  }
}

/// Pumps the Key_Screen with [ManualTimeBase] and [MockSpeechService]
/// overrides, with the clock starting at [startUs].
Future<KeyScreenHarness> pumpKeyScreen(
  WidgetTester tester, {
  int startUs = 0,
  MockSpeechService? speech,
}) async {
  final clock = ManualTimeBase(startUs);
  final mock = speech ?? MockSpeechService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        timeBaseProvider.overrideWithValue(clock),
        speechServiceProvider.overrideWithValue(mock),
      ],
      child: const MaterialApp(home: KeyScreen()),
    ),
  );
  // One more frame so the Frame_Ticker has ticked and autofocus applied.
  await tester.pump(const Duration(microseconds: frameStep));
  return KeyScreenHarness(tester, clock, mock);
}

void main() {
  const t = 1000000;

  testWidgets(
    'REQ-CI-2, REQ-KEY-1, REQ-KEY-4: a 100 ms Space dit decodes as E',
    (tester) async {
      final h = await pumpKeyScreen(tester, startUs: t);
      await h.spaceDown(t);
      await h.spaceUp(t + 100000);
      await h.frameTo(t + 900000);
      expect(h.sentenceText, 'E');
    },
  );

  testWidgets(
    'REQ-KEY-5: the letter appears in the first frame at or above the '
    'Letter_Gap_Threshold after release',
    (tester) async {
      final h = await pumpKeyScreen(tester, startUs: t);
      const release = t + 100000;
      const due = release + letterGapThreshold;
      await h.spaceDown(t);
      await h.spaceUp(release);

      int? lastBelow;
      int? firstAtOrAbove;
      await h.frameTo(
        t + 900000,
        onFrame: (frameUs) {
          if (frameUs < due) {
            lastBelow = frameUs;
            expect(h.sentenceText, '', reason: 'frame at $frameUs');
          } else {
            firstAtOrAbove ??= frameUs;
            expect(h.sentenceText, 'E', reason: 'frame at $frameUs');
          }
        },
      );
      expect(lastBelow, isNotNull);
      expect(firstAtOrAbove, isNotNull);
    },
  );

  testWidgets(
    'REQ-CI-2, REQ-SPEAK-1, REQ-COMPOSE-5: keying HI then Enter makes '
    'exactly one speech call with HI and leaves the Sentence unchanged',
    (tester) async {
      final h = await pumpKeyScreen(tester, startUs: t);
      await h.keyHi(t);
      expect(h.speech.spoken, isEmpty);

      await h.pressEnter();

      expect(h.speech.spoken, ['HI']);
      expect(h.sentenceText, 'HI');
    },
  );

  testWidgets(
    'REQ-CI-2, REQ-SPEAK-3, REQ-SPEAK-4, REQ-COMPOSE-5: Escape closes the '
    'Fallback_View with its Close button focused and leaves the Sentence '
    'unchanged',
    (tester) async {
      final h = await pumpKeyScreen(
        tester,
        startUs: t,
        speech: MockSpeechService(result: SpeechResult.failed),
      );
      await h.keyHi(t);

      await h.pressEnter();
      expect(h.speech.spoken, ['HI']);
      expect(find.byType(FallbackView), findsOneWidget);
      expect(find.text(FallbackView.notice), findsOneWidget);

      // Focus the Fallback_View's Close button without tapping it.
      final closeText = find.descendant(
        of: find.byType(FallbackView),
        matching: find.text('Close'),
      );
      expect(closeText, findsOneWidget);
      final closeFocus = Focus.of(tester.element(closeText));
      closeFocus.requestFocus();
      await tester.pump(const Duration(microseconds: frameStep));
      expect(closeFocus.hasPrimaryFocus, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(microseconds: frameStep));

      expect(find.byType(FallbackView), findsNothing);
      expect(h.sentenceText, 'HI');
      expect(h.speech.spoken, ['HI']);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(microseconds: frameStep));
    },
  );

  testWidgets(
    'REQ-CI-2, REQ-SPEAK-5, REQ-COMPOSE-5: a successful Speak_Action hides '
    'the Fallback_View and leaves the Sentence unchanged',
    (tester) async {
      final h = await pumpKeyScreen(
        tester,
        startUs: t,
        speech: MockSpeechService(result: SpeechResult.failed),
      );
      await h.keyHi(t);

      await h.pressEnter();
      expect(h.speech.spoken, ['HI']);
      expect(find.byType(FallbackView), findsOneWidget);

      h.speech.result = SpeechResult.completed;

      // Focus the Fallback_View's Close button, as in the Escape test, so
      // the Enter below reaches the Key_Screen with Close focused.
      final closeText = find.descendant(
        of: find.byType(FallbackView),
        matching: find.text('Close'),
      );
      expect(closeText, findsOneWidget);
      final closeFocus = Focus.of(tester.element(closeText));
      closeFocus.requestFocus();
      await tester.pump(const Duration(microseconds: frameStep));
      expect(closeFocus.hasPrimaryFocus, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(microseconds: frameStep));

      expect(h.speech.spoken, ['HI', 'HI']);
      expect(find.byType(FallbackView), findsNothing);
      expect(h.sentenceText, 'HI');

      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(microseconds: frameStep));
    },
  );

  remainingKeyScreenTests();
}

/// Sets the test viewport to [width] by [height] logical pixels.
void setViewport(WidgetTester tester, double width, [double height = 1200]) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

/// The on-screen Speak, Undo, Clear or Close button with [label].
Finder button(String label) => find.widgetWithText(FilledButton, label);

/// Checks that the control found by [finder] lies fully within [width] and
/// has a hit-test area of at least 48 by 48. REQ-A11Y-2, REQ-A11Y-4.
void expectControlFits(WidgetTester tester, Finder finder, double width) {
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0), reason: '$finder left');
  expect(rect.right, lessThanOrEqualTo(width), reason: '$finder right');
  expect(rect.width, greaterThanOrEqualTo(48), reason: '$finder width');
  expect(rect.height, greaterThanOrEqualTo(48), reason: '$finder height');
  // The centre of the control hit-tests to the control itself.
  final result = HitTestResult();
  tester.binding.hitTestInView(result, rect.center, tester.view.viewId);
  final target = tester.renderObject(finder);
  expect(
    result.path.any((entry) => entry.target == target),
    isTrue,
    reason: '$finder hit test',
  );
}

/// The widget tests from the design's widget-test table not covered by
/// tasks 5.6 to 5.9.
void remainingKeyScreenTests() {
  const t = 1000000;

  testWidgets(
    'REQ-KEY-1: Space with the Undo button focused makes a press and does '
    'not activate Undo',
    (tester) async {
      final h = await pumpKeyScreen(tester, startUs: t);
      final next = await h.keyLetter(t, '.');
      expect(h.sentenceText, 'E');

      final undoFocus = Focus.of(tester.element(find.text('Undo')));
      undoFocus.requestFocus();
      await tester.pump(const Duration(microseconds: frameStep));
      expect(undoFocus.hasPrimaryFocus, isTrue);

      await h.spaceDown(next);
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.keyLabel, 'Pressed');
      expect(h.sentenceText, 'E', reason: 'Undo must not be activated');

      await h.spaceUp(next + 100000);
      await h.frameTo(next + 900000);
      expect(h.sentenceText, 'EE');
      expect(undoFocus.hasPrimaryFocus, isTrue);
    },
  );

  testWidgets(
    'REQ-KEY-2: repeat events for Space, Enter and Escape change nothing',
    (tester) async {
      final h = await pumpKeyScreen(
        tester,
        startUs: t,
        speech: MockSpeechService(result: SpeechResult.failed),
      );
      final next = await h.keyLetter(t, '.');

      void expectUnchanged(KeyScreenState before, int calls) {
        final now = h.state;
        expect(sentenceText(now.sentence), sentenceText(before.sentence));
        expect(now.partialSequence, before.partialSequence);
        expect(now.isPressed, before.isPressed);
        expect(now.fallbackVisible, before.fallbackVisible);
        expect(h.speech.spoken.length, calls);
      }

      // Space held: repeats make no second press and no release.
      await h.spaceDown(next);
      await tester.pump(const Duration(microseconds: frameStep));
      var before = h.state;
      for (var i = 0; i < 3; i++) {
        h.clock.now += 50000;
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
        await tester.pump(const Duration(microseconds: frameStep));
      }
      expectUnchanged(before, 0);
      expect(h.keyLabel, 'Pressed');
      await h.spaceUp(h.clock.now + 10000);
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.keyLabel, 'Released');

      // Enter held: one Speak_Action for the key-down, none for repeats.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.speech.spoken, ['E']);
      expect(h.fallbackShown, isTrue);
      before = h.state;
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(microseconds: frameStep));
      }
      expectUnchanged(before, 1);

      // Escape held: its key-down closes the Fallback_View, a new Enter
      // shows it again, and Escape repeats must not close it.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.fallbackShown, isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.fallbackShown, isTrue);
      expect(h.speech.spoken, ['E', 'E']);
      before = h.state;
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(microseconds: frameStep));
      }
      expectUnchanged(before, 2);
      expect(h.fallbackShown, isTrue);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.sentenceText, 'E');
    },
  );

  testWidgets(
    'REQ-KEY-3: a pointer moved off the On_Screen_Key and then lifted '
    'releases the switch',
    (tester) async {
      final h = await pumpKeyScreen(tester, startUs: t);
      final key = find.byType(OnScreenKey);

      h.clock.now = t;
      final gesture = await tester.startGesture(tester.getCenter(key));
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.keyLabel, 'Pressed');

      h.clock.now = t + 50000;
      await gesture.moveTo(const Offset(1, 1));
      await tester.pump(const Duration(microseconds: frameStep));
      expect(tester.getRect(key).contains(const Offset(1, 1)), isFalse);
      expect(h.keyLabel, 'Pressed');

      h.clock.now = t + 100000;
      await gesture.up();
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.keyLabel, 'Released');

      await h.frameTo(t + 900000);
      expect(h.sentenceText, 'E');
    },
  );

  testWidgets('REQ-KEY-3: a cancelled pointer releases the switch', (
    tester,
  ) async {
    final h = await pumpKeyScreen(tester, startUs: t);
    h.clock.now = t;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(OnScreenKey)),
    );
    await tester.pump(const Duration(microseconds: frameStep));
    expect(h.keyLabel, 'Pressed');

    h.clock.now = t + 100000;
    await gesture.cancel();
    await tester.pump(const Duration(microseconds: frameStep));
    expect(h.keyLabel, 'Released');
  });

  testWidgets(
    'REQ-KEY-7, REQ-KEY-8: a pointer press while Space holds the switch is '
    'discarded, and the pressed state shows after one frame',
    (tester) async {
      final h = await pumpKeyScreen(tester, startUs: t);

      await h.spaceDown(t);
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.keyLabel, 'Pressed');

      h.clock.now = t + 20000;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(OnScreenKey)),
      );
      await tester.pump(const Duration(microseconds: frameStep));
      expect(tester.takeException(), isNull);
      expect(h.keyLabel, 'Pressed');
      expect(h.partialText, '');

      // No source tracking (K3): the pointer release ends the press.
      h.clock.now = t + 100000;
      await gesture.up();
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.keyLabel, 'Released');

      // The Space release is now a second release and is discarded.
      await h.spaceUp(t + 150000);
      await tester.pump(const Duration(microseconds: frameStep));
      expect(tester.takeException(), isNull);
      expect(h.keyLabel, 'Released');

      await h.frameTo(t + 900000);
      expect(h.sentenceText, 'E', reason: 'one 100 ms press, one dit');
      expect(h.partialText, '');
    },
  );

  for (final width in [320.0, 1920.0]) {
    testWidgets(
      'REQ-KEY-9, REQ-A11Y-4: a 200-item Sentence wraps in full at width '
      '${width.toInt()} with no overflow and every control in view',
      (tester) async {
        setViewport(tester, width);
        final h = await pumpKeyScreen(tester, startUs: t);

        // 40 words of EEEE (160 letters, 39 Word_Spaces) and one
        // Unknown_Letter_Item: 200 Decoded_Items.
        var at = t;
        for (var w = 0; w < 40; w++) {
          if (w > 0) at += 1400000;
          for (var l = 0; l < 4; l++) {
            at = await h.keyLetter(at, '.');
          }
        }
        at = await h.keyLetter(at, '........');

        final expected = '${List.filled(40, 'EEEE').join(' ')}$placeholder';
        expect(h.state.sentence.length, 200);
        expect(h.sentenceText, expected);
        expect(tester.takeException(), isNull);

        final sentence = find.byType(SentenceDisplay).first;
        final text = tester.widget<Text>(
          find.descendant(of: sentence, matching: find.byType(Text)),
        );
        expect(text.maxLines, isNull);
        expect(text.overflow, isNull);
        expect(text.style!.fontSize, greaterThanOrEqualTo(32));
        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: find.byType(PartialDisplay),
                  matching: find.byType(Text),
                ),
              )
              .style!
              .fontSize,
          greaterThanOrEqualTo(32),
        );

        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: sentence, matching: find.byType(RichText)),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.size.width, lessThanOrEqualTo(width));
        // Wrapped onto more than one line.
        expect(paragraph.size.height, greaterThan(2 * 32));
        final rect = tester.getRect(sentence);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));

        // No horizontal scrolling anywhere on the Key_Screen.
        final horizontal = find.byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.horizontal,
        );
        expect(horizontal, findsNothing);

        for (final control in [
          find.byType(OnScreenKey),
          button('Speak'),
          button('Undo'),
          button('Clear'),
        ]) {
          final r = tester.getRect(control);
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(width));
        }
      },
    );
  }

  testWidgets(
    'REQ-KEY-11: an Unknown_Letter_Item shows as exactly one Placeholder at '
    'its position',
    (tester) async {
      final h = await pumpKeyScreen(tester, startUs: t);
      var at = await h.keyLetter(t, '.');
      at = await h.keyLetter(at, '........');
      await h.keyLetter(at, '-');

      expect(h.sentenceText, 'E${placeholder}T');
      expect(placeholder.allMatches(h.sentenceText).length, 1);
    },
  );

  testWidgets(
    'REQ-KEY-12: 600 idle frames leave the state unchanged and rebuild '
    'nothing',
    (tester) async {
      final h = await pumpKeyScreen(tester, startUs: t);
      final next = await h.keyLetter(t, '.');
      await h.frameTo(next + 100000);

      final stateBefore = h.state;
      final sentenceWidget = tester.widget(find.byType(SentenceDisplay));
      final partialWidget = tester.widget(find.byType(PartialDisplay));
      final keyWidget = tester.widget(find.byType(OnScreenKey));

      final target = h.clock.now + 600 * frameStep;
      var frames = 0;
      await h.frameTo(target, onFrame: (_) => frames++);
      expect(frames, 600);

      expect(identical(h.state, stateBefore), isTrue);
      expect(
        identical(tester.widget(find.byType(SentenceDisplay)), sentenceWidget),
        isTrue,
      );
      expect(
        identical(tester.widget(find.byType(PartialDisplay)), partialWidget),
        isTrue,
      );
      expect(
        identical(tester.widget(find.byType(OnScreenKey)), keyWidget),
        isTrue,
      );
      expect(h.sentenceText, 'E');
    },
  );

  testWidgets(
    'REQ-SPEAK-2: an empty Speak_Text makes no speech call and shows no '
    'Fallback_View',
    (tester) async {
      final h = await pumpKeyScreen(
        tester,
        startUs: t,
        speech: MockSpeechService(result: SpeechResult.failed),
      );

      // Empty Sentence: Enter and the Speak button.
      await h.pressEnter();
      await tester.tap(button('Speak'));
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.speech.spoken, isEmpty);
      expect(h.fallbackShown, isFalse);
      expect(h.sentenceText, '');

      // Only Placeholders and a Word_Space.
      var at = await h.keyLetter(t, '........');
      at = await h.keyLetter(at + 1400000, '........');
      expect(h.sentenceText, '$placeholder $placeholder');

      await h.pressEnter();
      await tester.tap(button('Speak'));
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.speech.spoken, isEmpty);
      expect(h.fallbackShown, isFalse);
      expect(h.sentenceText, '$placeholder $placeholder');
    },
  );

  testWidgets(
    'REQ-SPEAK-3, REQ-COMPOSE-5: the Fallback_View stays through 10 s of '
    'frames and Close hides it with the Sentence unchanged',
    (tester) async {
      final h = await pumpKeyScreen(
        tester,
        startUs: t,
        speech: MockSpeechService(result: SpeechResult.failed),
      );
      await h.keyHi(t);
      await h.pressEnter();
      expect(h.speech.spoken, ['HI']);
      expect(h.fallbackShown, isTrue);
      expect(find.text(FallbackView.notice), findsOneWidget);

      final fallbackSentence = find.descendant(
        of: find.byType(FallbackView),
        matching: find.byType(SentenceDisplay),
      );
      final fallbackText = tester.widget<Text>(
        find.descendant(of: fallbackSentence, matching: find.byType(Text)),
      );
      expect(fallbackText.data, 'HI');
      expect(fallbackText.style!.fontSize, greaterThanOrEqualTo(32));

      await h.frameTo(h.clock.now + 10000000);
      expect(h.fallbackShown, isTrue);
      expect(h.sentenceText, 'HI');

      await tester.tap(button('Close'));
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.fallbackShown, isFalse);
      expect(h.sentenceText, 'HI');
      expect(h.speech.spoken, ['HI']);
    },
  );

  testWidgets(
    'REQ-COMPOSE-3, REQ-COMPOSE-4: the Undo and Clear buttons change only '
    'the Sentence and leave the Partial_Sequence',
    (tester) async {
      final h = await pumpKeyScreen(tester, startUs: t);
      var at = await h.keyLetter(t, '.');
      at = await h.keyLetter(at, '-');
      expect(h.sentenceText, 'ET');
      await h.startPartialDit(at);
      expect(h.partialText, '\u00B7');

      await tester.tap(button('Undo'));
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.sentenceText, 'E');
      expect(h.partialText, '\u00B7');

      await tester.tap(button('Clear'));
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.sentenceText, '');
      expect(h.partialText, '\u00B7');

      // Undo on an empty Sentence raises nothing.
      await tester.tap(button('Undo'));
      await tester.pump(const Duration(microseconds: frameStep));
      expect(tester.takeException(), isNull);
      expect(h.sentenceText, '');
      expect(h.partialText, '\u00B7');

      // Clear on an empty Sentence raises nothing.
      await tester.tap(button('Clear'));
      await tester.pump(const Duration(microseconds: frameStep));
      expect(tester.takeException(), isNull);
      expect(h.sentenceText, '');
      expect(h.partialText, '\u00B7');
    },
  );

  for (final width in [320.0, 1024.0, 1920.0]) {
    testWidgets('REQ-A11Y-1, REQ-A11Y-2, REQ-A11Y-5: labels, 48 px targets and '
        'non-colour cues at width ${width.toInt()}', (tester) async {
      setViewport(tester, width);
      final semantics = tester.ensureSemantics();
      final h = await pumpKeyScreen(
        tester,
        startUs: t,
        speech: MockSpeechService(result: SpeechResult.failed),
      );
      final key = find.byType(OnScreenKey);
      final sentence = find.byType(SentenceDisplay).first;
      final partial = find.byType(PartialDisplay);

      // REQ-A11Y-1: labels and values, empty fields labelled.
      expect(
        tester.getSemantics(key),
        isSemantics(label: 'Morse key', value: 'released', isButton: true),
      );
      expect(
        tester.getSemantics(sentence),
        isSemantics(label: 'Sentence is empty'),
      );
      expect(
        tester.getSemantics(partial),
        isSemantics(label: 'Current letter is empty'),
      );
      for (final label in ['Speak', 'Undo', 'Clear']) {
        expect(
          tester.getSemantics(button(label)),
          isSemantics(label: label, isButton: true),
        );
      }

      // REQ-A11Y-2: hit areas of at least 48 by 48, within the width.
      for (final control in [
        key,
        button('Speak'),
        button('Undo'),
        button('Clear'),
      ]) {
        expectControlFits(tester, control, width);
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      // REQ-A11Y-5: released versus pressed by text and border width.
      double borderWidth() {
        final box = tester.widget<DecoratedBox>(
          find.descendant(of: key, matching: find.byType(DecoratedBox)),
        );
        return ((box.decoration as BoxDecoration).border! as Border).top.width;
      }

      expect(h.keyLabel, 'Released');
      final releasedBorder = borderWidth();
      await h.spaceDown(t);
      await tester.pump(const Duration(microseconds: frameStep));
      expect(h.keyLabel, 'Pressed');
      expect(borderWidth(), isNot(releasedBorder));
      expect(
        tester.getSemantics(key),
        isSemantics(label: 'Morse key', value: 'pressed'),
      );
      await h.spaceUp(t + 100000);
      await h.frameTo(t + 900000);
      expect(h.keyLabel, 'Released');

      // Sentence with text; Partial_Sequence shown as a glyph.
      expect(
        tester.getSemantics(sentence),
        isSemantics(label: 'Sentence', value: 'E'),
      );
      await h.startPartialDit(t + 1000000);
      expect(h.partialText, '\u00B7');
      expect(
        tester.getSemantics(partial),
        isSemantics(label: 'Current letter', value: '\u00B7'),
      );

      // Speech_Failure: notice text and the Close control.
      await h.pressEnter();
      expect(h.fallbackShown, isTrue);
      expect(find.text(FallbackView.notice), findsOneWidget);
      expect(
        tester.getSemantics(button('Close')),
        isSemantics(label: 'Close', isButton: true),
      );
      expectControlFits(tester, button('Close'), width);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      semantics.dispose();
    });
  }
}
