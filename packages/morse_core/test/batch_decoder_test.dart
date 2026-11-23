import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

import 'support/timing_oracles.dart';

// The reference Calibration of REQ-BATCH-5.
const _cal = (
  ditLength: 100000,
  dahLength: 300000,
  symbolGap: 250000,
  letterGap: 700000,
);

Calibration _calibration() => Calibration(
  ditLength: _cal.ditLength,
  dahLength: _cal.dahLength,
  symbolGap: _cal.symbolGap,
  letterGap: _cal.letterGap,
);

BatchDecoder _decoder([TimingConfig? config]) =>
    BatchDecoder(_calibration(), config ?? TimingConfig.defaults);

List<SwitchEvent> _events(List<EventRecord> records) => [
  for (final (isPress, t) in records)
    isPress ? SwitchEvent.press(t) : SwitchEvent.release(t),
];

List<SwitchEvent> _presses(List<(int, int)> presses) => [
  for (final (a, b) in presses) ...[
    SwitchEvent.press(a),
    SwitchEvent.release(b),
  ],
];

/// [count] Presses of 100,000 separated by Gaps of 250,000, from [start].
List<(int, int)> _dits(int count, int start) => [
  for (var i = 0; i < count; i++)
    (start + i * 350000, start + i * 350000 + 100000),
];

const _space = DecodedItem.wordSpace();
DecodedItem _l(String c) => DecodedItem.letter(c);

void main() {
  group('BatchDecoder', () {
    test('REQ-BATCH-3 an unknown Symbol sequence gives an Unknown_Letter_Item '
        'and decoding continues', () {
      // E, then seven dits as one letter, then T after a letter gap each.
      final presses = <(int, int)>[
        (0, 100000),
        ..._dits(7, 800000),
        // Last dit of the run ends at 800,000 + 6 × 350,000 + 100,000.
        (3000000 + 700000, 3000000 + 700000 + 300000),
      ];
      expect(
        _decoder().decode(_presses(presses)),
        equals([_l('E'), const DecodedItem.unknownLetter('.......'), _l('T')]),
      );
    });

    test('REQ-BATCH-4 an empty Event_Sequence gives an empty list', () {
      expect(_decoder().decode(const []), isEmpty);
    });

    test('REQ-BATCH-4 an empty list when debounce removes every Press', () {
      final events = _presses([
        (0, 20000),
        (500000, 510000),
        (2000000, 2029999),
      ]);
      expect(_decoder().decode(events), isEmpty);
    });

    test('REQ-BATCH-4 output starts and ends with a letter and has no two '
        'Word_Spaces in a row, even across a very long silence', () {
      // T, a gap of ten Word_Gap_Thresholds, then E.
      final events = _presses([(0, 300000), (14300000, 14400000)]);
      expect(_decoder().decode(events), equals([_l('T'), _space, _l('E')]));
    });

    test('REQ-BATCH-5 the Ideal_Timing of SOS decodes to S, O, S', () {
      final events = _events(idealTiming('SOS', _cal, 2.0, 0));
      expect(_decoder().decode(events), equals([_l('S'), _l('O'), _l('S')]));
    });

    test('REQ-BATCH-6 the Ideal_Timing of HI THERE decodes with one '
        'Word_Space', () {
      final events = _events(idealTiming('HI THERE', _cal, 2.0, 0));
      expect(
        _decoder().decode(events),
        equals([
          _l('H'),
          _l('I'),
          _space,
          _l('T'),
          _l('H'),
          _l('E'),
          _l('R'),
          _l('E'),
        ]),
      );
    });

    test('REQ-BATCH-7 seven dits inside one letter give one '
        'Unknown_Letter_Item', () {
      final out = _decoder().decode(_presses(_dits(7, 0)));
      expect(out, equals([const DecodedItem.unknownLetter('.......')]));
      expect(out.single.kind, DecodedItemKind.unknownLetter);
      expect(out.single.symbols, '.......');
    });

    test('REQ-BATCH-10 two Presses 10,000 apart merge into one T', () {
      final events = _presses([(0, 150000), (160000, 300000)]);
      expect(_decoder().decode(events), equals([_l('T')]));
    });

    test('REQ-BATCH-11 a dropped short Press leaves a 900,000 Gap between '
        'two letters', () {
      final events = _presses([
        (0, 100000),
        (350000, 360000),
        (1000000, 1100000),
      ]);
      expect(_decoder().decode(events), equals([_l('E'), _l('E')]));
    });

    test('REQ-BATCH-12 seven dits, a letter gap, then one dit give an '
        'Unknown_Letter_Item then E', () {
      // The seventh dit releases at 6 × 350,000 + 100,000 = 2,200,000.
      final events = _presses([..._dits(7, 0), (2900000, 3000000)]);
      expect(
        _decoder().decode(events),
        equals([const DecodedItem.unknownLetter('.......'), _l('E')]),
      );
    });

    test('REQ-DEBOUNCE-13 a 20,000 Press is dropped at a Debounce_Time of '
        '30,000 and is E at 10,000', () {
      final events = _presses([(0, 20000)]);
      expect(
        _decoder(TimingConfig(debounceTime: 30000)).decode(events),
        isEmpty,
      );
      expect(
        _decoder(TimingConfig(debounceTime: 10000)).decode(events),
        equals([_l('E')]),
      );
    });
  });
}
