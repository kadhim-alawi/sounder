import 'dart:typed_data';

import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

/// 2^40 Microseconds, the largest valid Calibration value. REQ-CAL-14.
const int _cap = 1099511627776;

/// The smallest double greater than [x], for a finite positive [x].
double _nextUp(double x) {
  final bytes = ByteData(8)..setFloat64(0, x);
  bytes.setUint64(0, bytes.getUint64(0) + 1);
  return bytes.getFloat64(0);
}

Matcher _throwsKind(TimingInputErrorKind kind) =>
    throwsA(isA<TimingInputException>().having((e) => e.kind, 'kind', kind));

Calibration _cal({
  int dit = 100000,
  int dah = 300000,
  int symbolGap = 250000,
  int letterGap = 700000,
}) => Calibration(
  ditLength: dit,
  dahLength: dah,
  symbolGap: symbolGap,
  letterGap: letterGap,
);

void main() {
  group('TimingConfig', () {
    test('REQ-DEBOUNCE-1 defaults are 30,000 and 2.0', () {
      final config = TimingConfig();
      expect(config.debounceTime, 30000);
      expect(config.wordGapFactor, 2.0);
      expect(TimingConfig.defaults.debounceTime, 30000);
      expect(TimingConfig.defaults.wordGapFactor, 2.0);
    });

    test('REQ-DEBOUNCE-1 each omitted field takes its default', () {
      final onlyDebounce = TimingConfig(debounceTime: 12345);
      expect(onlyDebounce.debounceTime, 12345);
      expect(onlyDebounce.wordGapFactor, 2.0);

      final onlyFactor = TimingConfig(wordGapFactor: 3.75);
      expect(onlyFactor.debounceTime, 30000);
      expect(onlyFactor.wordGapFactor, 3.75);
    });

    test('REQ-DEBOUNCE-1 supplied values read back exactly', () {
      final factor = _nextUp(1.0);
      final config = TimingConfig(debounceTime: 7, wordGapFactor: factor);
      expect(config.debounceTime, 7);
      expect(config.wordGapFactor, factor);
      expect(config.wordGapFactor, isNot(1.0));
    });

    test('REQ-DEBOUNCE-3 a negative Debounce_Time is rejected', () {
      expect(
        () => TimingConfig(debounceTime: -30000),
        _throwsKind(TimingInputErrorKind.invalidDebounceTime),
      );
    });

    test('REQ-DEBOUNCE-3 a NaN or infinite Word_Gap_Factor is rejected', () {
      for (final factor in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => TimingConfig(wordGapFactor: factor),
          _throwsKind(TimingInputErrorKind.invalidWordGapFactor),
          reason: 'factor $factor',
        );
      }
    });

    test('REQ-DEBOUNCE-3 a Word_Gap_Factor of at most 1.0 is rejected', () {
      for (final factor in [1.0, 0.999, 0.0, -2.0]) {
        expect(
          () => TimingConfig(wordGapFactor: factor),
          _throwsKind(TimingInputErrorKind.invalidWordGapFactor),
          reason: 'factor $factor',
        );
      }
    });

    test('REQ-DEBOUNCE-3 the Word_Gap_Factor cap is 1,000 inclusive', () {
      expect(TimingConfig(wordGapFactor: 1000.0).wordGapFactor, 1000.0);
      final above = _nextUp(1000.0);
      expect(above, greaterThan(1000.0));
      expect(
        () => TimingConfig(wordGapFactor: above),
        _throwsKind(TimingInputErrorKind.invalidWordGapFactor),
      );
      expect(
        () => TimingConfig(wordGapFactor: 1001.0),
        _throwsKind(TimingInputErrorKind.invalidWordGapFactor),
      );
    });

    test('REQ-DEBOUNCE-3 the smallest double above 1.0 is accepted', () {
      final factor = _nextUp(1.0);
      expect(TimingConfig(wordGapFactor: factor).wordGapFactor, factor);
    });

    test('REQ-DEBOUNCE-3 both fields invalid names the Debounce_Time', () {
      for (final factor in [double.nan, 1.0, 2000.0]) {
        expect(
          () => TimingConfig(debounceTime: -1, wordGapFactor: factor),
          _throwsKind(TimingInputErrorKind.invalidDebounceTime),
          reason: 'factor $factor',
        );
      }
    });

    test('REQ-DEBOUNCE-14 Debounce_Time 0 and Word_Gap_Factor 1.5 are '
        'accepted', () {
      expect(TimingConfig(debounceTime: 0).debounceTime, 0);
      expect(TimingConfig(wordGapFactor: 1.5).wordGapFactor, 1.5);
      final both = TimingConfig(debounceTime: 0, wordGapFactor: 1.5);
      expect(both.debounceTime, 0);
      expect(both.wordGapFactor, 1.5);
    });

    test('REQ-DEBOUNCE-14 Debounce_Time -1 and Word_Gap_Factor 1.0 are '
        'rejected', () {
      expect(
        () => TimingConfig(debounceTime: -1),
        _throwsKind(TimingInputErrorKind.invalidDebounceTime),
      );
      expect(
        () => TimingConfig(wordGapFactor: 1.0),
        _throwsKind(TimingInputErrorKind.invalidWordGapFactor),
      );
    });
  });

  group('Calibration', () {
    test('REQ-CAL-14 valid values are accepted and read back', () {
      final cal = _cal();
      expect(cal.ditLength, 100000);
      expect(cal.dahLength, 300000);
      expect(cal.symbolGap, 250000);
      expect(cal.letterGap, 700000);
      expect(
        Calibration(ditLength: 1, dahLength: 2, symbolGap: 1, letterGap: 2),
        isA<Calibration>(),
      );
    });

    test('REQ-CAL-14 a Dit_Length of 0 or less is rejected', () {
      for (final dit in [0, -1]) {
        expect(
          () => _cal(dit: dit),
          _throwsKind(TimingInputErrorKind.invalidDitLength),
          reason: 'dit $dit',
        );
      }
    });

    test('REQ-CAL-14 a Dah_Length of 0 or less is rejected', () {
      for (final dah in [0, -1]) {
        expect(
          () => _cal(dah: dah),
          _throwsKind(TimingInputErrorKind.invalidDahLength),
          reason: 'dah $dah',
        );
      }
    });

    test('REQ-CAL-14 a Symbol_Gap of 0 or less is rejected', () {
      for (final gap in [0, -1]) {
        expect(
          () => _cal(symbolGap: gap),
          _throwsKind(TimingInputErrorKind.invalidSymbolGap),
          reason: 'symbol gap $gap',
        );
      }
    });

    test('REQ-CAL-14 a Letter_Gap of 0 or less is rejected', () {
      for (final gap in [0, -1]) {
        expect(
          () => _cal(letterGap: gap),
          _throwsKind(TimingInputErrorKind.invalidLetterGap),
          reason: 'letter gap $gap',
        );
      }
    });

    test('REQ-CAL-14 a Dah_Length at most the Dit_Length is rejected', () {
      for (final dah in [100000, 99999]) {
        expect(
          () => _cal(dah: dah),
          _throwsKind(TimingInputErrorKind.invalidDahLength),
          reason: 'dah $dah',
        );
      }
      expect(_cal(dah: 100001).dahLength, 100001);
    });

    test('REQ-CAL-14 a Letter_Gap at most the Symbol_Gap is rejected', () {
      for (final gap in [250000, 249999]) {
        expect(
          () => _cal(letterGap: gap),
          _throwsKind(TimingInputErrorKind.invalidLetterGap),
          reason: 'letter gap $gap',
        );
      }
      expect(_cal(letterGap: 250001).letterGap, 250001);
    });

    test('REQ-CAL-14 values up to 2^40 are accepted', () {
      // Dit_Length and Symbol_Gap must stay below their partners, so they
      // reach 2^40 - 1 while Dah_Length and Letter_Gap reach 2^40.
      final cal = Calibration(
        ditLength: _cap - 1,
        dahLength: _cap,
        symbolGap: _cap - 1,
        letterGap: _cap,
      );
      expect(cal.ditLength, _cap - 1);
      expect(cal.dahLength, _cap);
      expect(cal.symbolGap, _cap - 1);
      expect(cal.letterGap, _cap);
    });

    test('REQ-CAL-14 each value above 2^40 is rejected', () {
      expect(
        () => _cal(dit: _cap + 1, dah: _cap + 2),
        _throwsKind(TimingInputErrorKind.invalidDitLength),
      );
      expect(
        () => _cal(dah: _cap + 1),
        _throwsKind(TimingInputErrorKind.invalidDahLength),
      );
      expect(
        () => _cal(symbolGap: _cap + 1, letterGap: _cap + 2),
        _throwsKind(TimingInputErrorKind.invalidSymbolGap),
      );
      expect(
        () => _cal(letterGap: _cap + 1),
        _throwsKind(TimingInputErrorKind.invalidLetterGap),
      );
    });

    test('REQ-CAL-14 the first invalid field is named in the order Dit, Dah, '
        'Symbol_Gap, Letter_Gap', () {
      expect(
        () =>
            Calibration(ditLength: 0, dahLength: 0, symbolGap: 0, letterGap: 0),
        _throwsKind(TimingInputErrorKind.invalidDitLength),
      );
      expect(
        () => Calibration(
          ditLength: 100000,
          dahLength: 100000,
          symbolGap: 0,
          letterGap: 0,
        ),
        _throwsKind(TimingInputErrorKind.invalidDahLength),
      );
      expect(
        () => Calibration(
          ditLength: 100000,
          dahLength: 300000,
          symbolGap: _cap + 1,
          letterGap: 0,
        ),
        _throwsKind(TimingInputErrorKind.invalidSymbolGap),
      );
      expect(
        () => Calibration(
          ditLength: 100000,
          dahLength: 300000,
          symbolGap: 250000,
          letterGap: 250000,
        ),
        _throwsKind(TimingInputErrorKind.invalidLetterGap),
      );
    });
  });
}
