import 'package:flutter_test/flutter_test.dart';
import 'package:sounder/ui/key_screen_state.dart';

void main() {
  group('KeyScreenState expansion fields', () {
    test('REQ-NOTICE-1, REQ-WAIT-1, REQ-CHOICE-1, REQ-FAIL-1, REQ-CHOICE-5: '
        'initial state has the expansion area idle', () {
      final s = KeyScreenState.initial();
      expect(s.noticeVisible, isFalse);
      expect(s.thinking, isFalse);
      expect(s.candidates, isEmpty);
      expect(s.failureVisible, isFalse);
      expect(s.fallbackCandidate, isNull);
    });

    test('REQ-CHOICE-1: candidates are copied and unmodifiable', () {
      final source = <String>['I want water', 'I wish'];
      final s = KeyScreenState.initial().copyWith(candidates: source);
      source.add('changed');
      expect(s.candidates, <String>['I want water', 'I wish']);
      expect(() => s.candidates.add('x'), throwsUnsupportedError);
    });

    test('REQ-CHOICE-5: copyWith keeps fallbackCandidate when omitted and '
        'resets it to null when passed null', () {
      final set = KeyScreenState.initial().copyWith(
        fallbackCandidate: 'I want water',
      );
      expect(set.fallbackCandidate, 'I want water');
      expect(set.copyWith(thinking: true).fallbackCandidate, 'I want water');
      expect(set.copyWith(fallbackCandidate: null).fallbackCandidate, isNull);
    });

    test('REQ-NOTICE-1, REQ-WAIT-1, REQ-FAIL-1: copyWith replaces only the '
        'given flags', () {
      final s = KeyScreenState.initial().copyWith(
        noticeVisible: true,
        thinking: true,
        failureVisible: true,
      );
      expect(s.noticeVisible, isTrue);
      expect(s.thinking, isTrue);
      expect(s.failureVisible, isTrue);
      expect(s.fallbackVisible, isFalse);
      expect(s.copyWith(thinking: false).noticeVisible, isTrue);
    });
  });
}
