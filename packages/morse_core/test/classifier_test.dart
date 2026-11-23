import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

/// 2^40 Microseconds, the largest valid Calibration value. REQ-CAL-14.
const int _cap = 1099511627776;

Classifier _classifier({
  int dit = 100000,
  int dah = 300000,
  int symbolGap = 250000,
  int letterGap = 700000,
  double? factor,
}) => Classifier(
  Calibration(
    ditLength: dit,
    dahLength: dah,
    symbolGap: symbolGap,
    letterGap: letterGap,
  ),
  factor == null ? TimingConfig() : TimingConfig(wordGapFactor: factor),
);

Matcher _throwsNegativeDuration() => throwsA(
  isA<TimingInputException>()
      .having((e) => e.kind, 'kind', TimingInputErrorKind.negativeDuration)
      .having((e) => e.index, 'index', isNull),
);

Matcher _throwsDebounceTimeTooLong() => throwsA(
  isA<TimingInputException>()
      .having((e) => e.kind, 'kind', TimingInputErrorKind.debounceTimeTooLong)
      .having((e) => e.index, 'index', isNull)
      .having((e) => e.message, 'message', contains('debounce time')),
);

/// Dit_Length 100,000 is below Symbol_Gap 250,000, so Dit_Length binds.
final Calibration _ditBinds = Calibration(
  ditLength: 100000,
  dahLength: 300000,
  symbolGap: 250000,
  letterGap: 700000,
);

/// Symbol_Gap 80,000 is below Dit_Length 100,000, so Symbol_Gap binds.
final Calibration _gapBinds = Calibration(
  ditLength: 100000,
  dahLength: 300000,
  symbolGap: 80000,
  letterGap: 700000,
);

/// Both decoder constructors, so each REQ-TIMING-9 case runs against both.
final Map<String, Object Function(Calibration, TimingConfig)> _decoders = {
  'BatchDecoder': BatchDecoder.new,
  'LiveDecoder': LiveDecoder.new,
};

void main() {
  group('Decoder Debounce_Time limit', () {
    for (final entry in _decoders.entries) {
      final name = entry.key;
      final create = entry.value;

      test('REQ-TIMING-9 $name accepts Debounce_Time equal to Dit_Length '
          'or Symbol_Gap', () {
        // Each limit, taken as the binding one, is accepted exactly.
        expect(
          create(_ditBinds, TimingConfig(debounceTime: _ditBinds.ditLength)),
          isNotNull,
        );
        expect(
          create(_gapBinds, TimingConfig(debounceTime: _gapBinds.symbolGap)),
          isNotNull,
        );
      });

      test('REQ-TIMING-9 $name rejects Debounce_Time one more than '
          'Dit_Length when Dit_Length binds', () {
        expect(
          () => create(
            _ditBinds,
            TimingConfig(debounceTime: _ditBinds.ditLength + 1),
          ),
          _throwsDebounceTimeTooLong(),
        );
      });

      test('REQ-TIMING-9 $name rejects Debounce_Time one more than '
          'Symbol_Gap when Symbol_Gap binds', () {
        expect(
          () => create(
            _gapBinds,
            TimingConfig(debounceTime: _gapBinds.symbolGap + 1),
          ),
          _throwsDebounceTimeTooLong(),
        );
      });
    }
  });

  group('Classifier', () {
    test('REQ-TIMING-5 Dit_Length 100,000 and Dah_Length 300,000 give '
        'Press_Threshold 200,000', () {
      final c = _classifier();
      expect(c.pressThreshold, 200000);
      for (final d in [100000, 120000, 199999]) {
        expect(c.classifyPress(d), MorseSymbol.dit, reason: 'press $d');
      }
      for (final d in [200000, 240000, 300000]) {
        expect(c.classifyPress(d), MorseSymbol.dah, reason: 'press $d');
      }
    });

    test('REQ-TIMING-5 Dah_Length 300,001 gives Press_Threshold 200,001', () {
      final c = _classifier(dah: 300001);
      expect(c.pressThreshold, 200001);
      expect(c.classifyPress(200000), MorseSymbol.dit);
      expect(c.classifyPress(200001), MorseSymbol.dah);
    });

    test('REQ-TIMING-6 Symbol_Gap 250,000 and Letter_Gap 700,000 give '
        'thresholds 475,000 and 1,400,000', () {
      final c = _classifier();
      expect(c.letterGapThreshold, 475000);
      expect(c.wordGapThreshold, 1400000);
      for (final d in [214000, 314000, 474999]) {
        expect(c.classifyGap(d), GapClass.insideLetter, reason: 'gap $d');
      }
      for (final d in [475000, 700000, 1399999]) {
        expect(c.classifyGap(d), GapClass.betweenLetters, reason: 'gap $d');
      }
      expect(c.classifyGap(1400000), GapClass.betweenWords);
    });

    test('REQ-TIMING-6 Word_Gap_Factor 2.5 and Letter_Gap 700,001 give '
        'Word_Gap_Threshold 1,750,003', () {
      final c = _classifier(letterGap: 700001, factor: 2.5);
      expect(c.wordGapThreshold, 1750003);
    });

    test('REQ-TIMING-11 a negative Press duration throws negativeDuration '
        'with no index', () {
      final c = _classifier();
      for (final d in [-1, -100000]) {
        expect(
          () => c.classifyPress(d),
          _throwsNegativeDuration(),
          reason: 'press $d',
        );
      }
    });

    test('REQ-TIMING-11 a negative Gap duration throws negativeDuration '
        'with no index', () {
      final c = _classifier();
      for (final d in [-1, -700000]) {
        expect(
          () => c.classifyGap(d),
          _throwsNegativeDuration(),
          reason: 'gap $d',
        );
      }
    });

    test('REQ-PBT-6 REQ-TIMING-3 REQ-TIMING-4 a duration exactly at a '
        'threshold falls in the longer class', () {
      final c = _classifier(
        dit: 123457,
        dah: 345679,
        symbolGap: 222223,
        letterGap: 777779,
        factor: 1.75,
      );

      final p = c.pressThreshold;
      expect(c.classifyPress(p), MorseSymbol.dah);
      expect(c.classifyPress(p - 1), MorseSymbol.dit);
      expect(c.classifyPress(0), MorseSymbol.dit);

      final l = c.letterGapThreshold;
      expect(c.classifyGap(l), GapClass.betweenLetters);
      expect(c.classifyGap(l - 1), GapClass.insideLetter);
      expect(c.classifyGap(0), GapClass.insideLetter);

      final w = c.wordGapThreshold;
      expect(c.classifyGap(w), GapClass.betweenWords);
      expect(c.classifyGap(w - 1), GapClass.betweenLetters);
    });

    test('REQ-TIMING-1 Word_Gap_Factor 1 + 2^-52 with Letter_Gap 2^40 gives '
        'Word_Gap_Threshold 2^40 + 1 exactly', () {
      // 1 + 2^-52 is the smallest double above 1.0; the product with 2^40 is
      // 2^40 + 2^-12, whose ceiling is 2^40 + 1, also Letter_Gap + 1.
      const factor = 1.0 + 1 / 4503599627370496;
      expect(factor, greaterThan(1.0));
      final c = _classifier(letterGap: _cap, factor: factor);
      expect(c.wordGapThreshold, _cap + 1);
      expect(c.wordGapThreshold, greaterThanOrEqualTo(_cap + 1));
    });

    test('REQ-TIMING-1 Word_Gap_Factor 1,000 with Letter_Gap 2^40 gives '
        'Word_Gap_Threshold 1,000 x 2^40 exactly', () {
      final c = _classifier(letterGap: _cap, factor: 1000.0);
      expect(c.wordGapThreshold, 1000 * _cap);
    });
  });
}
