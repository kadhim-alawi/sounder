import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/keyboard_adapter.dart';
import '../speech/fallback_view.dart';
import 'action_bar.dart';
import 'key_screen_controller.dart';
import 'on_screen_key.dart';
import 'partial_display.dart';
import 'sentence_display.dart';
import 'sounder_colors.dart';

/// The Key_Screen: one switch (Space or the On_Screen_Key) drives one
/// Live_Decoder through [KeyScreenController]; a Frame_Ticker calls
/// `advanceTo` once per rendered frame; the Fallback_View is a layer over the
/// screen inside the same root `Focus` (design D4, D8, D10).
/// REQ-KEY-1, REQ-KEY-2, REQ-KEY-4, REQ-KEY-5, REQ-KEY-6, REQ-KEY-12,
/// REQ-SPEAK-4, REQ-SPEAK-5, REQ-A11Y-4.
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

  /// Space, Enter and Escape are handled here at the root, so no focused
  /// control activates and the browser performs no default action (design
  /// D8). REQ-KEY-1, REQ-KEY-2, REQ-SPEAK-4.
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
        controller.closeFallback();
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
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (state.fallbackVisible)
              Positioned.fill(
                child: FallbackView(
                  sentence: state.sentence,
                  onClose: controller.closeFallback,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
