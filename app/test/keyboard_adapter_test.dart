import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sounder/input/keyboard_adapter.dart';

KeyDownEvent _down(PhysicalKeyboardKey physical, LogicalKeyboardKey logical) =>
    KeyDownEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: Duration.zero,
    );

KeyUpEvent _up(PhysicalKeyboardKey physical, LogicalKeyboardKey logical) =>
    KeyUpEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: Duration.zero,
    );

KeyRepeatEvent _repeat(
  PhysicalKeyboardKey physical,
  LogicalKeyboardKey logical,
) => KeyRepeatEvent(
  physicalKey: physical,
  logicalKey: logical,
  timeStamp: Duration.zero,
);

const _space = (PhysicalKeyboardKey.space, LogicalKeyboardKey.space);
const _enter = (PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter);
const _numpadEnter = (
  PhysicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.numpadEnter,
);
const _escape = (PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape);
const _keyA = (PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA);
const _tab = (PhysicalKeyboardKey.tab, LogicalKeyboardKey.tab);

void main() {
  group('Space', () {
    test('REQ-KEY-1: Space key-down maps to press', () {
      expect(keyActionFor(_down(_space.$1, _space.$2)), KeyAction.press);
    });
    test('REQ-KEY-1: Space key-up maps to release', () {
      expect(keyActionFor(_up(_space.$1, _space.$2)), KeyAction.release);
    });
    test('REQ-KEY-2: Space repeat maps to swallow', () {
      expect(keyActionFor(_repeat(_space.$1, _space.$2)), KeyAction.swallow);
    });
  });

  group('Enter', () {
    for (final (name, key) in [
      ('Enter', _enter),
      ('numpad Enter', _numpadEnter),
    ]) {
      test('REQ-SPEAK-1: $name key-down maps to speak', () {
        expect(keyActionFor(_down(key.$1, key.$2)), KeyAction.speak);
      });
      test('REQ-SPEAK-1: $name key-up maps to swallow', () {
        expect(keyActionFor(_up(key.$1, key.$2)), KeyAction.swallow);
      });
      test('REQ-KEY-2: $name repeat maps to swallow', () {
        expect(keyActionFor(_repeat(key.$1, key.$2)), KeyAction.swallow);
      });
    }
  });

  group('Escape', () {
    test('REQ-SPEAK-4: Escape key-down maps to closeFallback', () {
      expect(
        keyActionFor(_down(_escape.$1, _escape.$2)),
        KeyAction.closeFallback,
      );
    });
    test('REQ-SPEAK-4: Escape key-up maps to swallow', () {
      expect(keyActionFor(_up(_escape.$1, _escape.$2)), KeyAction.swallow);
    });
    test('REQ-KEY-2, REQ-SPEAK-4: Escape repeat maps to swallow', () {
      expect(keyActionFor(_repeat(_escape.$1, _escape.$2)), KeyAction.swallow);
    });
  });

  group('Other keys', () {
    for (final (name, key) in [('A', _keyA), ('Tab', _tab)]) {
      test('REQ-KEY-1: $name key-down maps to ignore', () {
        expect(keyActionFor(_down(key.$1, key.$2)), KeyAction.ignore);
      });
      test('REQ-KEY-1: $name key-up maps to ignore', () {
        expect(keyActionFor(_up(key.$1, key.$2)), KeyAction.ignore);
      });
      test('REQ-KEY-1: $name repeat maps to ignore', () {
        expect(keyActionFor(_repeat(key.$1, key.$2)), KeyAction.ignore);
      });
    }
  });

  test('REQ-KEY-1: matching uses the logical key, not the physical key', () {
    // A layout that puts the Space character on another physical key still
    // counts as Space; a physical Space key mapped to another logical key
    // does not.
    expect(
      keyActionFor(_down(PhysicalKeyboardKey.keyA, LogicalKeyboardKey.space)),
      KeyAction.press,
    );
    expect(
      keyActionFor(_down(PhysicalKeyboardKey.space, LogicalKeyboardKey.keyA)),
      KeyAction.ignore,
    );
  });
}
