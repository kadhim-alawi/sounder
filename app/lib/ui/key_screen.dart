import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../compose/sentence_tokens.dart';
import '../input/keyboard_adapter.dart';
import '../speech/fallback_view.dart';
import 'action_bar.dart';
import 'candidate_list.dart';
import 'expansion_notice.dart';
import 'failure_message.dart';
import 'key_screen_controller.dart';
import 'on_screen_key.dart';
import 'partial_display.dart';
import 'sentence_display.dart';
import 'sounder_colors.dart';
import 'thinking_indicator.dart';
import 'tokens_message.dart';

/// The Key_Screen: one switch (Space or the On_Screen_Key) drives one
/// Live_Decoder through [KeyScreenController]; a Frame_Ticker calls
/// `advanceTo` once per rendered frame; the Fallback_View is a layer over the
/// screen inside the same root `Focus` (design D4, D8, D10). The expansion
/// area sits below the action bar (design D14).
/// REQ-KEY-1, REQ-KEY-2, REQ-KEY-4, REQ-KEY-5, REQ-KEY-6, REQ-KEY-12,
/// REQ-SPEAK-4, REQ-SPEAK-5, REQ-A11Y-4, REQ-TOKENS-4, REQ-NOTICE-2,
/// REQ-NOTICE-3, REQ-WAIT-2, REQ-CHOICE-3, REQ-CHOICE-5, REQ-FAIL-3.
class KeyScreen extends ConsumerStatefulWidget {
  /// Creates the Key_Screen. REQ-KEY-6.
  const KeyScreen({super.key});

  @override
  ConsumerState<KeyScreen> createState() => _KeyScreenState();
}

class _KeyScreenState extends ConsumerState<KeyScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    // Warm the voice list once (design L2). REQ-SPEAK-1.
    unawaited(ref.read(speechServiceProvider).init());
    // Frame_Ticker: one advanceTo per rendered frame with that frame's raw
    // timestamp (design D1, D4). REQ-KEY-4, REQ-KEY-5.
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    ref
        .read(keyScreenControllerProvider.notifier)
        .frame(SchedulerBinding.instance.currentSystemFrameTimeStamp);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Space, Enter, Escape, ArrowDown and the number keys 1 to 4 are handled
  /// here at the root, so no focused control activates and the browser
  /// performs no default action (design D8). Space stays the Morse key in
  /// every state. REQ-KEY-1, REQ-KEY-2, REQ-SPEAK-4, REQ-TOKENS-4,
  /// REQ-NOTICE-2, REQ-NOTICE-3, REQ-CHOICE-3.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final controller = ref.read(keyScreenControllerProvider.notifier);
    switch (keyActionFor(event)) {
      case KeyAction.press:
        controller.press(event.timeStamp);
      case KeyAction.release:
        controller.release(event.timeStamp);
      case KeyAction.speak:
        unawaited(controller.speak());
      case KeyAction.closeFallback:
        // Escape: Fallback_View first, then the Expansion_Notice (design
        // D12). REQ-SPEAK-4, REQ-NOTICE-3.
        controller.escape();
      case KeyAction.expand:
        // ArrowDown: Send while the notice is shown, else Expand (E18).
        // REQ-TOKENS-4, REQ-NOTICE-2.
        controller.arrowDown();
      case KeyAction.choose1:
        unawaited(controller.choose(1));
      case KeyAction.choose2:
        unawaited(controller.choose(2));
      case KeyAction.choose3:
        unawaited(controller.choose(3));
      case KeyAction.choose4:
        unawaited(controller.choose(4));
      case KeyAction.swallow:
        break;
      case KeyAction.ignore:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(keyScreenControllerProvider);
    final controller = ref.read(keyScreenControllerProvider.notifier);
    final check = sentenceTokens(state.sentence);
    // The expansion area below the action bar, in the D14 order. It only
    // grows downward, so the Sentence, Partial_Sequence and On_Screen_Key
    // never move. REQ-TOKENS-3, REQ-NOTICE-1, REQ-WAIT-1, REQ-WAIT-2,
    // REQ-FAIL-1, REQ-FAIL-3, REQ-CHOICE-2.
    final expansionArea = <Widget>[
      if (tokensMessageFor(check) != null) TokensMessage(check: check),
      if (state.noticeVisible)
        ExpansionNotice(
          onSend: controller.sendNotice,
          onCancel: controller.cancelNotice,
        ),
      if (state.thinking) const ThinkingIndicator(),
      if (state.failureVisible) const FailureMessage(),
      if (state.candidates.isNotEmpty)
        CandidateList(
          candidates: state.candidates,
          onChoose: (n) => unawaited(controller.choose(n)),
        ),
    ];
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Material(
        color: SounderColors.screenBackground,
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SentenceDisplay(sentence: state.sentence),
                      const SizedBox(height: 16),
                      PartialDisplay(partialSequence: state.partialSequence),
                      const SizedBox(height: 16),
                      OnScreenKey(
                        isPressed: state.isPressed,
                        onPress: controller.press,
                        onRelease: controller.release,
                      ),
                      const SizedBox(height: 16),
                      ActionBar(
                        onSpeak: () => unawaited(controller.speak()),
                        onUndo: controller.undo,
                        onClear: controller.clear,
                        onExpand: controller.expand,
                        // Disabled, not hidden, when Expand is not offered
                        // (E17). REQ-TOKENS-2, REQ-TOKENS-4.
                        expandEnabled: check is TokensReady,
                      ),
                      for (final widget in expansionArea) ...[
                        const SizedBox(height: 16),
                        widget,
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (state.fallbackVisible)
              Positioned.fill(
                child: FallbackView(
                  sentence: state.sentence,
                  candidateText: state.fallbackCandidate,
                  onClose: controller.closeFallback,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
