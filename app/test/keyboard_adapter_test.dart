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
const _arrowDown = (
  PhysicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowDown,
);
const _digit1 = (PhysicalKeyboardKey.digit1, LogicalKeyboardKey.digit1);
const _digit2 = (PhysicalKeyboardKey.digit2, LogicalKeyboardKey.digit2);
const _digit3 = (PhysicalKeyboardKey.digit3, LogicalKeyboardKey.digit3);
const _digit4 = (PhysicalKeyboardKey.digit4, LogicalKeyboardKey.digit4);
const _digit5 = (PhysicalKeyboardKey.digit5, LogicalKeyboardKey.digit5);
const _numpad1 = (PhysicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad1);
const _numpad2 = (PhysicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad2);
const _numpad3 = (PhysicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad3);
const _numpad4 = (PhysicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad4);
const _numpad5 = (PhysicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad5);

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

  group('ArrowDown', () {
    test('REQ-TOKENS-4: ArrowDown key-down maps to expand', () {
      expect(
        keyActionFor(_down(_arrowDown.$1, _arrowDown.$2)),
        KeyAction.expand,
      );
    });
    test('REQ-TOKENS-4: ArrowDown key-up maps to swallow', () {
      expect(
        keyActionFor(_up(_arrowDown.$1, _arrowDown.$2)),
        KeyAction.swallow,
      );
    });
    test('REQ-TOKENS-4, REQ-KEY-2: ArrowDown repeat maps to swallow', () {
      expect(
        keyActionFor(_repeat(_arrowDown.$1, _arrowDown.$2)),
        KeyAction.swallow,
      );
    });
  });

  group('Number keys', () {
    for (final (n, digit, numpad, action) in [
      (1, _digit1, _numpad1, KeyAction.choose1),
      (2, _digit2, _numpad2, KeyAction.choose2),
      (3, _digit3, _numpad3, KeyAction.choose3),
      (4, _digit4, _numpad4, KeyAction.choose4),
    ]) {
      for (final (name, key) in [('digit $n', digit), ('numpad $n', numpad)]) {
        test('REQ-CHOICE-3: $name key-down maps to choose$n', () {
          expect(keyActionFor(_down(key.$1, key.$2)), action);
        });
        test('REQ-CHOICE-3: $name key-up maps to swallow', () {
          expect(keyActionFor(_up(key.$1, key.$2)), KeyAction.swallow);
        });
        test('REQ-CHOICE-3, REQ-KEY-2: $name repeat maps to swallow', () {
          expect(keyActionFor(_repeat(key.$1, key.$2)), KeyAction.swallow);
        });
      }
    }

    for (final (name, key) in [('digit 5', _digit5), ('numpad 5', _numpad5)]) {
      test('REQ-CHOICE-3: $name key-down maps to ignore', () {
        expect(keyActionFor(_down(key.$1, key.$2)), KeyAction.ignore);
      });
      test('REQ-CHOICE-3: $name key-up maps to ignore', () {
        expect(keyActionFor(_up(key.$1, key.$2)), KeyAction.ignore);
      });
      test('REQ-CHOICE-3: $name repeat maps to ignore', () {
        expect(keyActionFor(_repeat(key.$1, key.$2)), KeyAction.ignore);
      });
    }
  });

  test('REQ-TOKENS-4: Space, Enter and Escape keep their actions after the '
      'ArrowDown and number keys were added', () {
    // Space stays the Morse key in every state of this spec.
    expect(keyActionFor(_down(_space.$1, _space.$2)), KeyAction.press);
    expect(keyActionFor(_up(_space.$1, _space.$2)), KeyAction.release);
    expect(keyActionFor(_repeat(_space.$1, _space.$2)), KeyAction.swallow);
    expect(keyActionFor(_down(_enter.$1, _enter.$2)), KeyAction.speak);
    expect(
      keyActionFor(_down(_numpadEnter.$1, _numpadEnter.$2)),
      KeyAction.speak,
    );
    expect(
      keyActionFor(_down(_escape.$1, _escape.$2)),
      KeyAction.closeFallback,
    );
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
