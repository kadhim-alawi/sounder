import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_core/morse_core.dart';
import 'package:sounder/speech/fallback_view.dart';
import 'package:sounder/ui/action_bar.dart';
import 'package:sounder/ui/sentence_display.dart';
import 'package:sounder/ui/sounder_colors.dart';

Finder _button(String label) => find.widgetWithText(FilledButton, label);

/// Pumps an [ActionBar] and returns how many times Expand was called.
Future<List<int>> _pumpBar(WidgetTester tester, {required bool enabled}) async {
  final calls = <int>[0];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ActionBar(
          onSpeak: () {},
          onUndo: () {},
          onClear: () {},
          onExpand: () => calls[0]++,
          expandEnabled: enabled,
        ),
      ),
    ),
  );
  return calls;
}

/// The resolved background and text colours of the Material inside [label].
(Color?, Color?) _colours(WidgetTester tester, String label) {
  final material = tester.widget<Material>(
    find.descendant(of: _button(label), matching: find.byType(Material)),
  );
  return (material.color, material.textStyle?.color);
}

void main() {
  testWidgets('REQ-TOKENS-4: Expand is the button after Clear', (
    tester,
  ) async {
    await _pumpBar(tester, enabled: true);
    final labels = tester
        .widgetList<FilledButton>(find.byType(FilledButton))
        .map((b) => ((b.child! as Text).data))
        .toList();
    expect(labels, ['Speak', 'Undo', 'Clear', 'Expand']);
    final size = tester.getSize(_button('Expand'));
    expect(size.width, greaterThanOrEqualTo(64));
    expect(size.height, greaterThanOrEqualTo(64));
  });

  testWidgets('REQ-TOKENS-4: an enabled Expand calls onExpand once', (
    tester,
  ) async {
    final calls = await _pumpBar(tester, enabled: true);
    await tester.tap(_button('Expand'));
    await tester.pump();
    expect(calls[0], 1);
  });

  testWidgets(
    'REQ-TOKENS-2: a disabled Expand ignores taps and keeps its colours',
    (tester) async {
      final calls = await _pumpBar(tester, enabled: false);
      expect(tester.widget<FilledButton>(_button('Expand')).enabled, isFalse);
      await tester.tap(_button('Expand'));
      await tester.pump();
      expect(calls[0], 0);
      expect(_colours(tester, 'Expand'), (
        SounderColors.released,
        SounderColors.text,
      ));
      expect(_colours(tester, 'Expand'), _colours(tester, 'Clear'));
    },
  );

  group('REQ-CHOICE-5: FallbackView candidate text', () {
    const sentence = <DecodedItem>[];

    Future<void> pumpView(WidgetTester tester, String? candidate) =>
        tester.pumpWidget(
          MaterialApp(
            home: FallbackView(
              sentence: sentence,
              onClose: () {},
              candidateText: candidate,
            ),
          ),
        );

    testWidgets('REQ-CHOICE-5: candidate text at 36 px replaces the Sentence', (
      tester,
    ) async {
      await pumpView(tester, 'I need water');
      expect(find.byType(SentenceDisplay), findsNothing);
      final text = tester.widget<Text>(find.text('I need water'));
      expect(text.style?.fontSize, 36);
      expect(find.text(FallbackView.notice), findsOneWidget);
      expect(_button('Close'), findsOneWidget);
    });

    testWidgets('REQ-CHOICE-5: no candidate text shows the Sentence', (
      tester,
    ) async {
      await pumpView(tester, null);
      expect(find.byType(SentenceDisplay), findsOneWidget);
    });
  });
}
