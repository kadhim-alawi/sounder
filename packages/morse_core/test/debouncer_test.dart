import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

Debouncer _debouncer(int d) => Debouncer(TimingConfig(debounceTime: d));

Matcher _throwsAt(TimingInputErrorKind kind, int index) => throwsA(
  isA<TimingInputException>()
      .having((e) => e.kind, 'kind', kind)
      .having((e) => e.index, 'index', index),
);

void main() {
  group('Debouncer', () {
    test('REQ-DEBOUNCE-10 a Debounce_Time of 0 returns the input unchanged, '
        'including zero-length Presses and Gaps', () {
      const input = [
        Press(-500, -500),
        Press(-500, 100),
        Press(100, 100),
        Press(2000, 2001),
        Press(2001, 50000),
      ];
      expect(_debouncer(0).debounce(input), equals(input));
    });

    test('REQ-DEBOUNCE-11 a short bounce before a press merges into one Press',
        () {
      const input = [Press(0, 2000), Press(4000, 100000)];
      expect(_debouncer(30000).debounce(input), equals([Press(0, 100000)]));
    });

    test('REQ-DEBOUNCE-12 a short isolated Press is dropped', () {
      const input = [
        Press(0, 100000),
        Press(400000, 410000),
        Press(700000, 800000),
      ];
      expect(
        _debouncer(30000).debounce(input),
        equals([Press(0, 100000), Press(700000, 800000)]),
      );
    });

    test('REQ-DEBOUNCE-21 a Press of exactly d is kept and a Gap just under d '
        'merges', () {
      const input = [
        Press(0, 30000),
        Press(60000, 160000),
        Press(189999, 290000),
      ];
      expect(
        _debouncer(30000).debounce(input),
        equals([Press(0, 30000), Press(60000, 290000)]),
      );
    });

    test('REQ-DEBOUNCE-22 merges run first, then short Presses are dropped '
        'with no further merge', () {
      const input = [
        Press(0, 5000),
        Press(10000, 15000),
        Press(20000, 120000),
        Press(500000, 502000),
        Press(510000, 512000),
      ];
      expect(_debouncer(30000).debounce(input), equals([Press(0, 120000)]));
    });

    test('REQ-PBT-6 REQ-DEBOUNCE-6 a Press and a Gap of exactly d are kept '
        'unchanged', () {
      const d = 30000;
      const input = [Press(0, d), Press(2 * d, 3 * d)];
      final result = _debouncer(d).debounce(input);
      expect(result, equals(input));
      expect(result[0].duration, d);
      expect(result[1].pressedAt - result[0].releasedAt, d);
    });

    test('REQ-DEBOUNCE-6 the caller list is unchanged and the result is a new '
        'list', () {
      final input = [Press(0, 2000), Press(4000, 100000)];
      final copy = List<Press>.of(input);
      final result = _debouncer(30000).debounce(input);
      expect(input, equals(copy));
      expect(identical(result, input), isFalse);
    });

    group('REQ-DEBOUNCE-20 invalid Press lists', () {
      test('REQ-DEBOUNCE-20 release before press reports releaseBeforePress '
          'at its index', () {
        const input = [Press(0, 100000), Press(200000, 150000)];
        expect(
          () => _debouncer(30000).debounce(input),
          _throwsAt(TimingInputErrorKind.releaseBeforePress, 1),
        );
      });

      test('REQ-DEBOUNCE-20 a Press starting before the previous release '
          'reports pressOverlapsPrevious at its index', () {
        const input = [
          Press(0, 100000),
          Press(200000, 300000),
          Press(250000, 400000),
        ];
        expect(
          () => _debouncer(30000).debounce(input),
          _throwsAt(TimingInputErrorKind.pressOverlapsPrevious, 2),
        );
      });

      test('REQ-DEBOUNCE-20 when both rules break at one index, '
          'releaseBeforePress wins', () {
        const input = [Press(0, 100000), Press(50000, 40000)];
        expect(
          () => _debouncer(30000).debounce(input),
          _throwsAt(TimingInputErrorKind.releaseBeforePress, 1),
        );
      });

      test('REQ-DEBOUNCE-20 the lowest invalid index is reported', () {
        const input = [
          Press(0, 100000),
          Press(200000, 300000),
          Press(250000, 400000), // overlaps previous, index 2
          Press(500000, 450000), // release before press, index 3
        ];
        expect(
          () => _debouncer(30000).debounce(input),
          _throwsAt(TimingInputErrorKind.pressOverlapsPrevious, 2),
        );
      });

      test('REQ-DEBOUNCE-20 an invalid list returns no partial result and '
          'leaves the input unchanged', () {
        final input = [
          Press(0, 2000),
          Press(4000, 100000),
          Press(90000, 200000),
        ];
        final copy = List<Press>.of(input);
        List<Press>? result;
        expect(
          () => result = _debouncer(30000).debounce(input),
          _throwsAt(TimingInputErrorKind.pressOverlapsPrevious, 2),
        );
        expect(result, isNull);
        expect(input, equals(copy));
      });
    });
  });
}
