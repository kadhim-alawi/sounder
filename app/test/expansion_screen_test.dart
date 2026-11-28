// Widget tests for the Expand flow on the Key_Screen. Every test drives the
// screen from a test-controlled Time_Base and never uses pumpAndSettle,
// because the Frame_Ticker schedules a frame every vsync (key-screen D4).
// The Expansion_Client and the notice store are mocks; no request leaves
// the test (REQ-APPTEST-4).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sounder/compose/expansion_client.dart';
import 'package:sounder/compose/sentence_text.dart';
import 'package:sounder/speech/fallback_view.dart';
import 'package:sounder/speech/speech_service.dart';
import 'package:sounder/ui/candidate_list.dart';
import 'package:sounder/ui/expansion_notice.dart';
import 'package:sounder/ui/failure_message.dart';
import 'package:sounder/ui/sentence_display.dart';
import 'package:sounder/ui/tokens_message.dart';
import 'package:sounder/ui/key_screen.dart';
import 'package:sounder/ui/key_screen_controller.dart';
import 'package:sounder/ui/key_screen_state.dart';
import 'package:sounder/ui/thinking_indicator.dart';

import 'support/expansion_mocks.dart';
import 'support/manual_time_base.dart';
import 'support/mock_speech_service.dart';

/// One frame at 60 Hz, in Microseconds.
const int frameStep = 16667;

/// The exact REQ-NOTICE-1 text, written out here rather than taken from
/// [expansionNoticeText], so the test checks the wording itself.
const String noticeText =
    'Expand sends the letters you typed to Cloudflare Workers AI to suggest '
    'sentences. Sounder stores nothing.';

/// The clock and mocks shared by one widget test.
final class ExpansionHarness {
  ExpansionHarness(
    this.tester,
    this.clock,
    this.client,
    this.store,
    this.speech,
  );

  final WidgetTester tester;
  final ManualTimeBase clock;
  final MockExpansionClient client;
  final MockNoticeStore store;
  final MockSpeechService speech;

  /// Renders one frame.
  Future<void> frame() => tester.pump(const Duration(microseconds: frameStep));

  /// Keys one letter from [code] (`.` and `-`) at [startUs] with 100,000 µs
  /// dits, 300,000 µs dahs and 100,000 µs gaps, then renders one frame
  /// 600,000 µs after the last release so the letter completes. Returns that
  /// frame time; a letter keyed 1,400,000 µs later starts a new word.
  Future<int> keyLetter(int startUs, String code) async {
    var at = startUs;
    var lastRelease = startUs;
    for (final symbol in code.split('')) {
      clock.now = at;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      lastRelease = at + (symbol == '-' ? 300000 : 100000);
      clock.now = lastRelease;
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      at = lastRelease + 100000;
    }
    clock.now = lastRelease + 600000;
    await frame();
    return clock.now;
  }

  /// Keys the two-word Sentence `E T` starting at [startUs]. Returns the
  /// frame time after `T`: a letter keyed from it joins the word `T`.
  Future<int> keyET(int startUs) async {
    final next = await keyLetter(startUs, '.');
    final end = await keyLetter(next + 1400000, '-');
    expect(sentence, 'E T');
    return end;
  }

  /// One non-repeat key-down and key-up of [key], with a frame after each.
  Future<void> pressKey(LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await frame();
    await tester.sendKeyUpEvent(key);
    await frame();
  }

  /// Taps the on-screen button labelled [label] and renders one frame.
  Future<void> tapButton(String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await frame();
  }

  /// Whether the Expansion_Notice is on screen.
  bool get noticeShown => find.byType(ExpansionNotice).evaluate().isNotEmpty;

  /// The current published Key_Screen state.
  KeyScreenState get state =>
      ProviderScope.containerOf(tester.element(find.byType(KeyScreen)))
          .read(keyScreenControllerProvider);

  /// The Sentence as display text.
  String get sentence => sentenceText(state.sentence);
}

/// Pumps the Key_Screen with mock overrides on a 1024 by 1200 viewport, so
/// the whole expansion area is in view.
Future<ExpansionHarness> pumpExpansionScreen(
  WidgetTester tester, {
  required MockNoticeStore store,
  int startUs = 1000000,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1024, 1200);
  addTearDown(tester.view.reset);
  final clock = ManualTimeBase(startUs);
  final client = MockExpansionClient();
  final speech = MockSpeechService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        timeBaseProvider.overrideWithValue(clock),
        speechServiceProvider.overrideWithValue(speech),
        expansionClientProvider.overrideWithValue(client),
        noticeStoreProvider.overrideWithValue(store),
      ],
      child: const MaterialApp(home: KeyScreen()),
    ),
  );
  // One more frame so the Frame_Ticker has ticked, autofocus applied and the
  // Notice_Acceptance read has finished.
  await tester.pump(const Duration(microseconds: frameStep));
  return ExpansionHarness(tester, clock, client, store, speech);
}

void main() {
  const t = 1000000;

  testWidgets(
    'REQ-NOTICE-1, REQ-APPTEST-3: Expand with no stored acceptance shows the '
    'exact notice text with Send and Cancel and sends no request',
    (tester) async {
      final h = await pumpExpansionScreen(tester, store: MockNoticeStore());
      await h.keyET(t);
      expect(h.noticeShown, isFalse);

      await h.tapButton('Expand');

      expect(find.text(noticeText), findsOneWidget);
      expect(expansionNoticeText, noticeText);
      expect(find.widgetWithText(FilledButton, 'Send'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Cancel'), findsOneWidget);
      expect(h.client.calls, isEmpty);
      expect(find.byType(ThinkingIndicator), findsNothing);

      // The notice never closes by itself and still sends nothing.
      for (var i = 0; i < 120; i++) {
        h.clock.now += frameStep;
        await h.frame();
      }
      expect(find.text(noticeText), findsOneWidget);
      expect(h.client.calls, isEmpty);
      expect(h.store.acceptCalls, 0);
    },
  );

  testWidgets(
    'REQ-NOTICE-2, REQ-APPTEST-3: the Send button closes the notice, stores '
    'the acceptance and sends one request for the Sentence_Tokens',
    (tester) async {
      final h = await pumpExpansionScreen(tester, store: MockNoticeStore());
      await h.keyET(t);
      await h.tapButton('Expand');
      expect(h.noticeShown, isTrue);

      await h.tapButton('Send');

      expect(h.noticeShown, isFalse);
      expect(h.client.calls, [
        ['E', 'T'],
      ]);
      expect(h.store.acceptCalls, 1);
      expect(h.store.accepted, isTrue);
      expect(find.byType(ThinkingIndicator), findsOneWidget);
      expect(h.sentence, 'E T');
    },
  );

  testWidgets(
    'REQ-NOTICE-2, REQ-TOKENS-4, REQ-APPTEST-3: ArrowDown opens the notice, '
    'a second ArrowDown sends one request and stores the acceptance',
    (tester) async {
      final h = await pumpExpansionScreen(tester, store: MockNoticeStore());
      await h.keyET(t);

      await h.pressKey(LogicalKeyboardKey.arrowDown);
      expect(find.text(noticeText), findsOneWidget);
      expect(h.client.calls, isEmpty);

      await h.pressKey(LogicalKeyboardKey.arrowDown);

      expect(h.noticeShown, isFalse);
      expect(h.client.calls, [
        ['E', 'T'],
      ]);
      expect(h.store.acceptCalls, 1);
      expect(h.sentence, 'E T');
    },
  );

  for (final how in ['button', 'Escape']) {
    testWidgets(
      'REQ-NOTICE-3, REQ-APPTEST-3: Cancel by $how closes the notice, sends '
      'nothing, stores nothing and keeps the Sentence',
      (tester) async {
        final h = await pumpExpansionScreen(tester, store: MockNoticeStore());
        await h.keyET(t);
        await h.tapButton('Expand');
        expect(h.noticeShown, isTrue);

        if (how == 'button') {
          await h.tapButton('Cancel');
        } else {
          await h.pressKey(LogicalKeyboardKey.escape);
        }

        expect(h.noticeShown, isFalse);
        expect(h.client.calls, isEmpty);
        expect(h.store.acceptCalls, 0);
        expect(h.store.accepted, isFalse);
        expect(find.byType(ThinkingIndicator), findsNothing);
        expect(h.sentence, 'E T');

        // Nothing was stored, so the next Expand shows the notice again.
        await h.tapButton('Expand');
        expect(find.text(noticeText), findsOneWidget);
        expect(h.client.calls, isEmpty);
      },
    );
  }

  testWidgets(
    'REQ-NOTICE-4, REQ-APPTEST-3: a stored acceptance skips the notice and '
    'Expand sends one request at once',
    (tester) async {
      final h = await pumpExpansionScreen(
        tester,
        store: MockNoticeStore(accepted: true),
      );
      expect(h.store.readCalls, 1);
      await h.keyET(t);

      await h.tapButton('Expand');

      expect(h.noticeShown, isFalse);
      expect(find.text(noticeText), findsNothing);
      expect(h.client.calls, [
        ['E', 'T'],
      ]);
      expect(h.store.acceptCalls, 0);
      expect(find.byType(ThinkingIndicator), findsOneWidget);
    },
  );

  testWidgets(
    'REQ-NOTICE-5, REQ-APPTEST-3: a store that throws on read and write '
    'shows the notice each time and still sends for an activated Send',
    (tester) async {
      final h = await pumpExpansionScreen(
        tester,
        store: MockNoticeStore(
          accepted: true,
          readError: StateError('read failed'),
          writeError: StateError('write failed'),
        ),
      );
      expect(h.store.readCalls, 1);
      expect(tester.takeException(), isNull);
      await h.keyET(t);

      // A failed read counts as not stored.
      await h.tapButton('Expand');
      expect(find.text(noticeText), findsOneWidget);
      expect(h.client.calls, isEmpty);

      // Send still sends although the write fails.
      await h.tapButton('Send');
      expect(h.noticeShown, isFalse);
      expect(h.store.acceptCalls, 1);
      expect(h.client.calls, [
        ['E', 'T'],
      ]);
      expect(tester.takeException(), isNull);

      h.client.reply(0, ['Eat toast']);
      await h.frame();
      expect(h.state.candidates, ['Eat toast']);

      // The failed write left the acceptance not stored: the notice again.
      await h.tapButton('Expand');
      expect(find.text(noticeText), findsOneWidget);
      expect(h.client.calls, hasLength(1));

      await h.pressKey(LogicalKeyboardKey.arrowDown);
      expect(h.noticeShown, isFalse);
      expect(h.store.acceptCalls, 2);
      expect(h.client.calls, [
        ['E', 'T'],
        ['E', 'T'],
      ]);
    },
  );

  // Task 12.8: waiting, stale replies and narrowing.

  /// Pumps the screen with a stored acceptance, keys `E T` and presses
  /// Expand, so call 0 is the Pending_Request. Returns the harness and the
  /// frame time after `T`.
  Future<(ExpansionHarness, int)> pumpPending(WidgetTester tester) async {
    final h = await pumpExpansionScreen(
      tester,
      store: MockNoticeStore(accepted: true),
    );
    final afterT = await h.keyET(t);
    await h.tapButton('Expand');
    expect(h.client.calls, [
      ['E', 'T'],
    ]);
    expect(h.state.thinking, isTrue);
    return (h, afterT);
  }

  testWidgets(
    'REQ-WAIT-1, REQ-WAIT-2, REQ-APPTEST-3: a Pending_Request shows the '
    'static Thinking… text in a live region and no modal barrier',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await pumpExpansionScreen(
        tester,
        store: MockNoticeStore(accepted: true),
      );
      await h.keyET(t);
      final barriersBefore = find.byType(ModalBarrier).evaluate().length;
      expect(find.byType(ThinkingIndicator), findsNothing);

      await h.tapButton('Expand');

      expect(find.text('Thinking\u2026'), findsOneWidget);
      expect(ThinkingIndicator.text, 'Thinking\u2026');
      expect(
        tester.getSemantics(find.byType(ThinkingIndicator)),
        containsSemantics(label: 'Thinking\u2026', isLiveRegion: true),
      );
      expect(find.byType(ModalBarrier).evaluate().length, barriersBefore);

      // Static: frames pass and the text stays the same, with no request
      // added.
      for (var i = 0; i < 60; i++) {
        h.clock.now += frameStep;
        await h.frame();
      }
      expect(find.text('Thinking\u2026'), findsOneWidget);
      expect(h.client.calls, hasLength(1));
      semantics.dispose();
    },
  );

  testWidgets(
    'REQ-WAIT-2, REQ-WAIT-4, REQ-APPTEST-3: Space keys a letter while a '
    'request is pending, and the new letter abandons the request',
    (tester) async {
      final (h, afterT) = await pumpPending(tester);

      h.clock.now = afterT;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await h.frame();
      expect(h.state.isPressed, isTrue);
      expect(h.state.thinking, isTrue);

      h.clock.now = afterT + 100000;
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      h.clock.now = afterT + 150000;
      await h.frame();
      expect(h.state.isPressed, isFalse);
      expect(h.state.partialSequence, '.');
      // A Partial_Sequence alone does not change the Sentence.
      expect(h.state.thinking, isTrue);
      expect(h.sentence, 'E T');

      h.clock.now += 600000;
      await h.frame();

      expect(h.sentence, 'E TE');
      expect(h.state.thinking, isFalse);
      expect(find.byType(ThinkingIndicator), findsNothing);
      expect(h.client.calls, hasLength(1));
    },
  );

  testWidgets(
    'REQ-WAIT-2, REQ-WAIT-4, REQ-APPTEST-3: Undo while pending removes the '
    'last item and abandons the request; its late reply is ignored',
    (tester) async {
      final (h, _) = await pumpPending(tester);

      await h.tapButton('Undo');

      expect(h.sentence, 'E ');
      expect(find.byType(ThinkingIndicator), findsNothing);

      h.client.reply(0, ['Eat toast']);
      await h.frame();
      expect(h.state.candidates, isEmpty);
      expect(h.state.thinking, isFalse);
      expect(h.state.failureVisible, isFalse);
      expect(h.sentence, 'E ');
    },
  );

  testWidgets(
    'REQ-WAIT-2, REQ-WAIT-4, REQ-APPTEST-3: Clear while pending empties the '
    'Sentence and abandons the request; its late failure is ignored',
    (tester) async {
      final (h, _) = await pumpPending(tester);

      await h.tapButton('Clear');

      expect(h.sentence, '');
      expect(find.byType(ThinkingIndicator), findsNothing);

      h.client.fail(0, ExpansionFailureKind.timeout);
      await h.frame();
      expect(h.state.failureVisible, isFalse);
      expect(h.state.candidates, isEmpty);
      expect(h.state.thinking, isFalse);
    },
  );

  testWidgets(
    'REQ-WAIT-2, REQ-APPTEST-3: Speak while pending speaks the typed text '
    'once and keeps the request, whose reply still arrives',
    (tester) async {
      final (h, _) = await pumpPending(tester);

      await h.tapButton('Speak');

      expect(h.speech.spoken, ['E T']);
      expect(h.state.thinking, isTrue);
      expect(h.sentence, 'E T');
      expect(h.client.calls, hasLength(1));

      h.client.reply(0, ['Eat toast']);
      await h.frame();
      expect(h.state.candidates, ['Eat toast']);
      expect(h.state.thinking, isFalse);
      // A reply arriving speaks nothing.
      expect(h.speech.spoken, ['E T']);
    },
  );

  testWidgets(
    'REQ-WAIT-4, REQ-NARROW-2, REQ-APPTEST-3: a Sentence change abandons '
    'the pending request and its reply never reaches the screen',
    (tester) async {
      final (h, afterT) = await pumpPending(tester);

      // Add O to the word T: the Sentence changes to E TO.
      await h.keyLetter(afterT, '---');
      expect(h.sentence, 'E TO');
      expect(find.byType(ThinkingIndicator), findsNothing);

      h.client.reply(0, ['Eat toast', 'Every time']);
      await h.frame();
      expect(h.state.candidates, isEmpty);
      expect(h.state.thinking, isFalse);
      expect(h.state.failureVisible, isFalse);

      // A new Expand sends the new tokens; the old reply cannot touch it.
      await h.tapButton('Expand');
      expect(h.client.calls, [
        ['E', 'T'],
        ['E', 'TO'],
      ]);
      expect(h.state.thinking, isTrue);
      h.client.reply(1, ['Eat toast']);
      await h.frame();
      expect(h.state.candidates, ['Eat toast']);
    },
  );

  testWidgets(
    'REQ-WAIT-6, REQ-NARROW-2, REQ-APPTEST-3: a second Expand supersedes '
    'the first; the first reply is ignored and the second is shown',
    (tester) async {
      final (h, _) = await pumpPending(tester);

      await h.pressKey(LogicalKeyboardKey.arrowDown);
      expect(h.client.calls, [
        ['E', 'T'],
        ['E', 'T'],
      ]);
      expect(find.byType(ThinkingIndicator), findsOneWidget);

      h.client.reply(0, ['Eat toast']);
      await h.frame();
      expect(h.state.candidates, isEmpty);
      expect(h.state.thinking, isTrue);
      expect(h.state.failureVisible, isFalse);

      h.client.reply(1, ['Every time']);
      await h.frame();
      expect(h.state.candidates, ['Every time']);
      expect(h.state.thinking, isFalse);
    },
  );

  testWidgets(
    'REQ-NARROW-2, REQ-APPTEST-3: a stale reply leaves the Candidate_List, '
    'the Thinking_Indicator and the Failure_Message as they are',
    (tester) async {
      final (h, _) = await pumpPending(tester);
      h.client.reply(0, ['Eat toast', 'Every time']);
      await h.frame();
      expect(h.state.candidates, ['Eat toast', 'Every time']);

      // Calls 1 and 2; 2 is the newest. Shown Candidates stay meanwhile.
      await h.tapButton('Expand');
      await h.tapButton('Expand');
      expect(h.client.calls, hasLength(3));
      expect(h.state.candidates, ['Eat toast', 'Every time']);

      // A stale failure: nothing changes.
      h.client.fail(1, ExpansionFailureKind.timeout);
      await h.frame();
      expect(h.state.candidates, ['Eat toast', 'Every time']);
      expect(h.state.thinking, isTrue);
      expect(h.state.failureVisible, isFalse);

      // The newest request fails: the Failure_Message shows.
      h.client.fail(2, ExpansionFailureKind.timeout);
      await h.frame();
      expect(h.state.failureVisible, isTrue);
      expect(h.state.candidates, isEmpty);
      expect(h.state.thinking, isFalse);

      // Calls 3 and 4; 4 fails, then a stale reply for 3 arrives.
      await h.tapButton('Expand');
      await h.tapButton('Expand');
      h.client.fail(4, ExpansionFailureKind.timeout);
      await h.frame();
      expect(h.state.failureVisible, isTrue);
      h.client.reply(3, ['Eat toast']);
      await h.frame();
      expect(h.state.failureVisible, isTrue);
      expect(h.state.candidates, isEmpty);
      expect(h.state.thinking, isFalse);
    },
  );

  testWidgets('REQ-NARROW-1, REQ-APPTEST-3: adding a letter narrows the '
      'Candidate_List in order and sends no request', (tester) async {
    final (h, afterT) = await pumpPending(tester);
    h.client.reply(0, ['Eat toast', 'Every time', 'Eat tomatoes']);
    await h.frame();
    expect(h.state.candidates, ['Eat toast', 'Every time', 'Eat tomatoes']);

    // E T -> E TO keeps the two Candidates whose second word starts TO.
    final afterO = await h.keyLetter(afterT, '---');
    expect(h.sentence, 'E TO');
    expect(h.state.candidates, ['Eat toast', 'Eat tomatoes']);
    expect(find.textContaining('Every time'), findsNothing);
    expect(find.textContaining('Eat toast'), findsOneWidget);

    // E TO -> E TOA keeps one.
    final afterA = await h.keyLetter(afterO, '.-');
    expect(h.sentence, 'E TOA');
    expect(h.state.candidates, ['Eat toast']);

    // E TOA -> E TOAX keeps none: the list is cleared, no failure shown.
    await h.keyLetter(afterA, '-..-');
    expect(h.sentence, 'E TOAX');
    expect(h.state.candidates, isEmpty);
    expect(h.state.failureVisible, isFalse);
    expect(h.client.calls, hasLength(1));
  });

  testWidgets(
    'REQ-NARROW-1, REQ-APPTEST-3: a Sentence that disables Expand clears '
    'the Candidate_List',
    (tester) async {
      final (h, _) = await pumpPending(tester);
      h.client.reply(0, ['Eat toast']);
      await h.frame();
      expect(h.state.candidates, ['Eat toast']);

      await h.tapButton('Clear');

      expect(h.sentence, '');
      expect(h.state.candidates, isEmpty);
      expect(find.textContaining('Eat toast'), findsNothing);
    },
  );

  // Task 12.9: choosing, failure and the Tokens_Message.

  /// Pumps the pending screen for `E T` and answers call 0 with
  /// [candidates]. Returns the harness and the frame time after `T`.
  Future<(ExpansionHarness, int)> pumpCandidates(
    WidgetTester tester,
    List<String> candidates,
  ) async {
    final (h, afterT) = await pumpPending(tester);
    h.client.reply(0, candidates);
    await h.frame();
    return (h, afterT);
  }

  /// The Candidate_Button whose Candidate text is [text].
  Finder candidateButton(String text) => find.descendant(
    of: find.byType(CandidateList),
    matching: find.widgetWithText(FilledButton, text),
  );

  /// The RichText that renders the Text widget showing [text] inside
  /// [scope].
  Finder richTextOf(Finder scope, String text) => find.descendant(
    of: find.descendant(of: scope, matching: find.text(text)),
    matching: find.byType(RichText),
  );

  testWidgets(
    'REQ-CHOICE-3, REQ-APPTEST-3: clicking a Candidate_Button speaks that '
    'Candidate once and leaves the Sentence and the Candidate_List unchanged',
    (tester) async {
      final (h, _) = await pumpCandidates(tester, ['Eat toast', 'Every time']);
      expect(h.speech.spoken, isEmpty);

      await tester.tap(candidateButton('Every time'));
      await h.frame();

      expect(h.speech.spoken, ['Every time']);
      expect(h.sentence, 'E T');
      expect(h.state.candidates, ['Eat toast', 'Every time']);
      expect(find.byType(FallbackView), findsNothing);

      // The same Candidate can be spoken again (E20).
      await tester.tap(candidateButton('Eat toast'));
      await h.frame();
      expect(h.speech.spoken, ['Every time', 'Eat toast']);
      expect(h.sentence, 'E T');
      expect(h.state.candidates, ['Eat toast', 'Every time']);
    },
  );

  testWidgets(
    'REQ-CHOICE-3, REQ-CHOICE-6, REQ-APPTEST-3: number keys on the digit '
    'row and the numpad speak their Candidate once; a number with no '
    'Candidate speaks nothing',
    (tester) async {
      final (h, _) = await pumpCandidates(tester, ['Eat toast', 'Every time']);

      await h.pressKey(LogicalKeyboardKey.digit1);
      expect(h.speech.spoken, ['Eat toast']);

      await h.pressKey(LogicalKeyboardKey.numpad2);
      expect(h.speech.spoken, ['Eat toast', 'Every time']);

      await h.pressKey(LogicalKeyboardKey.digit3);
      await h.pressKey(LogicalKeyboardKey.numpad4);
      expect(h.speech.spoken, ['Eat toast', 'Every time']);

      expect(h.sentence, 'E T');
      expect(h.state.candidates, ['Eat toast', 'Every time']);
    },
  );

  testWidgets(
    'REQ-CHOICE-4, REQ-APPTEST-3: Enter while Candidates are shown speaks '
    'the typed text, not a Candidate',
    (tester) async {
      final (h, _) = await pumpCandidates(tester, ['Eat toast']);

      await h.pressKey(LogicalKeyboardKey.enter);

      expect(h.speech.spoken, ['E T']);
      expect(h.sentence, 'E T');
      expect(h.state.candidates, ['Eat toast']);
    },
  );

  testWidgets(
    'REQ-CHOICE-5, REQ-APPTEST-3: a Speech_Failure for a chosen Candidate '
    'shows the Fallback_View with the Candidate text instead of the Sentence',
    (tester) async {
      final (h, _) = await pumpCandidates(tester, ['Eat toast', 'Every time']);
      h.speech.result = SpeechResult.failed;

      await tester.tap(candidateButton('Every time'));
      await h.frame();

      expect(h.speech.spoken, ['Every time']);
      final fallback = find.byType(FallbackView);
      expect(fallback, findsOneWidget);
      expect(find.text(FallbackView.notice), findsOneWidget);
      expect(
        find.descendant(of: fallback, matching: find.text('Every time')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: fallback, matching: find.byType(SentenceDisplay)),
        findsNothing,
      );
      final text = tester.widget<Text>(
        find.descendant(of: fallback, matching: find.text('Every time')),
      );
      expect(text.style!.fontSize, greaterThanOrEqualTo(32));
      expect(h.sentence, 'E T');

      // Close works as in key-screen REQ-SPEAK-3; the list stays.
      await tester.tap(
        find.descendant(
          of: fallback,
          matching: find.widgetWithText(FilledButton, 'Close'),
        ),
      );
      await h.frame();
      expect(find.byType(FallbackView), findsNothing);
      expect(h.state.candidates, ['Eat toast', 'Every time']);

      // A failed Speak_Action afterwards shows the Sentence again.
      await h.pressKey(LogicalKeyboardKey.enter);
      expect(h.speech.spoken, ['Every time', 'E T']);
      expect(
        find.descendant(
          of: find.byType(FallbackView),
          matching: find.byType(SentenceDisplay),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'REQ-CHOICE-6, REQ-APPTEST-3: a reply arriving and the Candidate_List '
    'narrowing make no Speech_Service call',
    (tester) async {
      final (h, afterT) = await pumpCandidates(tester, [
        'Eat toast',
        'Every time',
      ]);
      expect(h.state.candidates, ['Eat toast', 'Every time']);
      expect(h.speech.spoken, isEmpty);

      await h.keyLetter(afterT, '---');
      expect(h.state.candidates, ['Eat toast']);
      for (var i = 0; i < 30; i++) {
        h.clock.now += frameStep;
        await h.frame();
      }
      expect(h.speech.spoken, isEmpty);
    },
  );

  testWidgets(
    'REQ-CHOICE-1, REQ-APPTEST-3: locally invalid Candidates are dropped and '
    'the first 4 valid ones are shown in order',
    (tester) async {
      final (h, _) = await pumpCandidates(tester, [
        'Eat toast',
        'Bad toast',
        'Eat',
        'Every time',
        'Eat the toast',
        'Eat tea',
        'Even then',
        'Eggs today',
      ]);

      expect(h.state.candidates, [
        'Eat toast',
        'Every time',
        'Eat tea',
        'Even then',
      ]);
      expect(
        find.descendant(
          of: find.byType(CandidateList),
          matching: find.byType(FilledButton),
        ),
        findsNWidgets(4),
      );
      for (final dropped in ['Bad toast', 'Eat', 'Eat the toast']) {
        expect(find.text(dropped), findsNothing);
      }
      expect(find.text('Eggs today'), findsNothing);
      expect(h.state.failureVisible, isFalse);
    },
  );

  testWidgets(
    'REQ-CHOICE-2, REQ-APPTEST-3: Candidate_Buttons at 320 px wide are at '
    'least 48 by 48, use 32 px text that wraps in full, and carry the number '
    'and text as their semantic label',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (h, _) = await pumpPending(tester);
      tester.view.physicalSize = const Size(320, 2400);
      await h.frame();
      const long = 'Everything tastes';
      h.client.reply(0, [long, 'Eat toast']);
      await h.frame();
      expect(tester.takeException(), isNull);

      final labels = <String, String>{
        long: '1. $long',
        'Eat toast':
            '2. '
            'Eat toast',
      };
      for (final MapEntry(key: text, value: label) in labels.entries) {
        final button = candidateButton(text);
        final size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, lessThanOrEqualTo(320));

        final rich = tester.widget<RichText>(richTextOf(button, text));
        expect(rich.text.style!.fontSize, greaterThanOrEqualTo(32));
        expect(rich.softWrap, isTrue);
        expect(rich.maxLines, isNull);
        expect(rich.overflow, isNot(TextOverflow.ellipsis));
        expect(rich.text.toPlainText(), text);

        expect(
          tester.getSemantics(button),
          containsSemantics(label: label, isButton: true),
        );
      }

      // The long Candidate is wider than the line, so it wraps onto more
      // than one line and is not cut off.
      final paragraph = tester.renderObject<RenderParagraph>(
        richTextOf(candidateButton(long), long),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.height, greaterThan(32 * 1.5));
      semantics.dispose();
    },
  );

  for (final (name, answer) in <(String, void Function(MockExpansionClient))>[
    ('a timeout', (c) => c.fail(0, ExpansionFailureKind.timeout)),
    ('a non-200 status', (c) => c.fail(0, ExpansionFailureKind.status)),
    ('an empty list', (c) => c.reply(0, const <String>[])),
    ('a list empty after validation', (c) => c.reply(0, ['Bad one'])),
  ]) {
    testWidgets('REQ-FAIL-1, REQ-FAIL-2, REQ-APPTEST-3: $name shows the '
        'Failure_Message in a live region, which stays until the Sentence '
        'changes', (tester) async {
      final semantics = tester.ensureSemantics();
      final (h, _) = await pumpPending(tester);

      answer(h.client);
      await h.frame();

      expect(find.text(failureMessageText), findsOneWidget);
      expect(
        failureMessageText,
        'No suggestions. Add letters or speak what you typed.',
      );
      expect(
        tester.getSemantics(find.byType(FailureMessage)),
        containsSemantics(isLiveRegion: true),
      );
      expect(find.byType(ThinkingIndicator), findsNothing);
      expect(find.byType(CandidateList), findsNothing);
      expect(h.speech.spoken, isEmpty);

      // No timer removes it: 10 s of frames.
      for (var i = 0; i < 600; i++) {
        h.clock.now += frameStep;
        await h.frame();
      }
      expect(find.text(failureMessageText), findsOneWidget);

      // A Sentence change removes it. After 10 s of silence a new letter
      // would start a new word, so Undo makes the change.
      await h.tapButton('Undo');
      expect(h.sentence, 'E ');
      expect(find.text(failureMessageText), findsNothing);
      semantics.dispose();
    });
  }

  testWidgets('REQ-FAIL-2, REQ-APPTEST-3: the next Expand_Action removes the '
      'Failure_Message and sends a new request', (tester) async {
    final (h, _) = await pumpPending(tester);
    h.client.fail(0, ExpansionFailureKind.status);
    await h.frame();
    expect(find.text(failureMessageText), findsOneWidget);

    await h.tapButton('Expand');

    expect(find.text(failureMessageText), findsNothing);
    expect(find.byType(ThinkingIndicator), findsOneWidget);
    expect(h.client.calls, hasLength(2));
    expect(h.sentence, 'E T');
  });

  testWidgets(
    'REQ-FAIL-3, REQ-APPTEST-3: while the Failure_Message is shown there is '
    'no modal barrier and Speak, Space, Undo and Clear work as usual',
    (tester) async {
      final h = await pumpExpansionScreen(
        tester,
        store: MockNoticeStore(accepted: true),
      );
      final afterT = await h.keyET(t);
      final barriersBefore = find.byType(ModalBarrier).evaluate().length;
      await h.tapButton('Expand');
      h.client.fail(0, ExpansionFailureKind.timeout);
      await h.frame();
      expect(find.text(failureMessageText), findsOneWidget);
      expect(find.byType(ModalBarrier).evaluate().length, barriersBefore);

      await h.tapButton('Speak');
      expect(h.speech.spoken, ['E T']);
      expect(find.text(failureMessageText), findsOneWidget);

      await h.keyLetter(afterT, '---');
      expect(h.sentence, 'E TO');

      await h.tapButton('Undo');
      expect(h.sentence, 'E T');

      await h.tapButton('Clear');
      expect(h.sentence, '');
    },
  );

  /// Keys [count] single-`E` words from [startUs]. Returns the frame time
  /// after the last one.
  Future<int> keyWords(ExpansionHarness h, int startUs, int count) async {
    var at = await h.keyLetter(startUs, '.');
    for (var i = 1; i < count; i++) {
      at = await h.keyLetter(at + 1400000, '.');
    }
    return at;
  }

  /// Keys one word of [count] `E` letters from [startUs]. Returns the frame
  /// time after the last one.
  Future<int> keyLongWord(ExpansionHarness h, int startUs, int count) async {
    var at = startUs;
    for (var i = 0; i < count; i++) {
      at = await h.keyLetter(at, '.');
    }
    return at;
  }

  for (final (message, sentence, keySentence)
      in <(String, String, Future<void> Function(ExpansionHarness))>[
        (
          'Expand needs letters only.',
          'E1',
          (h) async {
            final afterE = await h.keyLetter(t, '.');
            await h.keyLetter(afterE, '.----');
          },
        ),
        (
          'Expand takes up to 12 words.',
          List.filled(13, 'E').join(' '),
          (h) async => keyWords(h, t, 13),
        ),
        (
          'Expand takes up to 8 letters a word.',
          'EEEEEEEEE',
          (h) async => keyLongWord(h, t, 9),
        ),
      ]) {
    testWidgets(
      'REQ-TOKENS-2, REQ-TOKENS-3, REQ-APPTEST-3: "$message" is shown with '
      'Expand disabled, ignores Expand_Actions and stays until the Sentence '
      'changes',
      (tester) async {
        final h = await pumpExpansionScreen(
          tester,
          store: MockNoticeStore(accepted: true),
        );
        await keySentence(h);
        expect(h.sentence, sentence);

        expect(find.text(message), findsOneWidget);
        expect(find.byType(TokensMessage), findsOneWidget);
        final expand = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Expand'),
        );
        expect(expand.enabled, isFalse);

        await h.tapButton('Expand');
        await h.pressKey(LogicalKeyboardKey.arrowDown);
        expect(h.client.calls, isEmpty);
        expect(h.noticeShown, isFalse);
        expect(find.byType(ThinkingIndicator), findsNothing);

        for (var i = 0; i < 600; i++) {
          h.clock.now += frameStep;
          await h.frame();
        }
        expect(find.text(message), findsOneWidget);

        // Undo the last letter: the Sentence is ready again.
        await h.tapButton('Undo');
        expect(find.text(message), findsNothing);
        expect(find.byType(TokensMessage), findsNothing);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Expand'))
              .enabled,
          isTrue,
        );
      },
    );
  }

  testWidgets(
    'REQ-TOKENS-2, REQ-TOKENS-3, REQ-APPTEST-3: an empty Sentence disables '
    'Expand with no Tokens_Message',
    (tester) async {
      final h = await pumpExpansionScreen(
        tester,
        store: MockNoticeStore(accepted: true),
      );
      expect(h.sentence, '');
      expect(find.byType(TokensMessage), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Expand'))
            .enabled,
        isFalse,
      );
      await h.pressKey(LogicalKeyboardKey.arrowDown);
      expect(h.client.calls, isEmpty);
    },
  );
}
