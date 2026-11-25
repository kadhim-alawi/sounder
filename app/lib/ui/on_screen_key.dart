import 'package:flutter/widgets.dart';

import '../input/pointer_adapter.dart';
import 'sounder_colors.dart';

/// The large on-screen switch. A pointer going down calls [onPress]; the
/// same pointer going up or being cancelled calls [onRelease], wherever the
/// pointer is by then. Both receive the event's `PointerEvent.timeStamp`.
/// Shows "Pressed" with a 4 px border or "Released" with a 1 px border, so
/// the state does not depend on colour. No ink, splash or animation.
/// REQ-KEY-3, REQ-KEY-8, REQ-A11Y-1, REQ-A11Y-2, REQ-A11Y-5, REQ-KEY-12.
class OnScreenKey extends StatefulWidget {
  /// Creates the On_Screen_Key. REQ-KEY-3, REQ-KEY-8.
  const OnScreenKey({
    super.key,
    required this.isPressed,
    required this.onPress,
    required this.onRelease,
  });

  /// The minimum height of the key in logical pixels. REQ-A11Y-2.
  static const double minHeight = 160;

  /// Whether the Live_Decoder reports the switch as pressed. REQ-KEY-8.
  final bool isPressed;

  /// Called with the pointer-down timestamp. REQ-KEY-3, REQ-KEY-4.
  final ValueChanged<Duration> onPress;

  /// Called with the pointer-up or cancel timestamp of the pressing
  /// pointer. REQ-KEY-3, REQ-KEY-4.
  final ValueChanged<Duration> onRelease;

  @override
  State<OnScreenKey> createState() => _OnScreenKeyState();
}

class _OnScreenKeyState extends State<OnScreenKey> {
  final PointerAdapter _pointers = PointerAdapter();

  void _down(PointerDownEvent event) {
    if (_pointers.down(event.pointer)) widget.onPress(event.timeStamp);
  }

  void _end(PointerEvent event) {
    if (_pointers.end(event.pointer)) widget.onRelease(event.timeStamp);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = widget.isPressed;
    final label = pressed ? 'Pressed' : 'Released';
    return Semantics(
      container: true,
      button: true,
      label: 'Morse key',
      value: pressed ? 'pressed' : 'released',
      excludeSemantics: true,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerUp: _end,
        onPointerCancel: _end,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: double.infinity,
            minHeight: OnScreenKey.minHeight,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: pressed ? SounderColors.pressed : SounderColors.released,
              border: Border.all(
                color: SounderColors.text,
                width: pressed ? 4 : 1,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(16)),
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: SounderColors.text,
                  fontSize: 32,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
