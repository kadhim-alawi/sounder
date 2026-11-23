/// Reference models for the adaptive-timing property tests.
///
/// This file does not import `package:morse_core`. Each oracle works on plain
/// records and is written in a different shape from the code in `lib/`, so a
/// shared mistake is unlikely. REQ-PBT-1.
library;

import 'dart:typed_data';

import 'itu_fixture.dart';

/// A Press as a plain record: press timestamp and release timestamp, in
/// Microseconds. REQ-DEBOUNCE-4.
typedef PressRecord = (int pressedAt, int releasedAt);

/// The merge-then-drop debounce of REQ-DEBOUNCE-4 and REQ-DEBOUNCE-5.
///
/// First groups Press indexes into runs: index `i` joins the run of `i - 1`
/// when the Gap between them is shorter than [d]. Each run becomes one Press
/// from the first Press's press timestamp to the last Press's release
/// timestamp. Then every Press shorter than [d] is removed, and nothing is
/// merged afterwards. [presses] must be time ordered and is not changed.
/// REQ-DEBOUNCE-4, REQ-DEBOUNCE-5.
List<PressRecord> referenceDebounce(List<PressRecord> presses, int d) {
  final runs = <List<int>>[];
  for (var i = 0; i < presses.length; i++) {
    final joins = i > 0 && presses[i].$1 - presses[i - 1].$2 < d;
    if (joins) {
      runs.last.add(i);
    } else {
      runs.add(<int>[i]);
    }
  }
  return <PressRecord>[
    for (final run in runs) (presses[run.first].$1, presses[run.last].$2),
  ].where((p) => p.$2 - p.$1 >= d).toList();
}

/// A Calibration as a plain record of its four values in Microseconds.
/// REQ-CAL-14.
typedef CalibrationRecord = ({
  int ditLength,
  int dahLength,
  int symbolGap,
  int letterGap,
});

/// The three thresholds of REQ-TIMING-1 as whole Microseconds.
typedef ThresholdRecord = ({
  int pressThreshold,
  int letterGapThreshold,
  int wordGapThreshold,
});

/// ⌈numerator / denominator⌉ for a non-negative numerator and a positive
/// denominator.
BigInt _ceilDiv(BigInt numerator, BigInt denominator) {
  final q = numerator ~/ denominator;
  return q * denominator == numerator ? q : q + BigInt.one;
}

/// [factor] as an exact fraction `(numerator, denominator)`, read from its
/// IEEE-754 bits. [factor] must be a finite, normal, positive double.
(BigInt, BigInt) _exactFraction(double factor) {
  final bytes = ByteData(8)..setFloat64(0, factor);
  final bits = bytes.getUint64(0);
  final exponentBits = (bits >> 52) & 0x7FF;
  final fractionBits = bits & 0xFFFFFFFFFFFFF;
  // A normal double is (2^52 + fraction) × 2^(exponent − 1075).
  final significand = (BigInt.one << 52) + BigInt.from(fractionBits);
  final shift = exponentBits - 1075;
  return shift >= 0
      ? (significand << shift, BigInt.one)
      : (significand, BigInt.one << -shift);
}

/// The thresholds of REQ-TIMING-1 computed in exact rational arithmetic:
/// Press_Threshold = ⌈(Dit_Length + Dah_Length) / 2⌉, Letter_Gap_Threshold =
/// ⌈(Symbol_Gap + Letter_Gap) / 2⌉, and Word_Gap_Threshold = the smallest
/// whole number greater than Letter_Gap and not less than [factor] ×
/// Letter_Gap. [factor] must be finite and greater than 1. REQ-TIMING-1.
ThresholdRecord exactThresholds(CalibrationRecord cal, double factor) {
  final two = BigInt.two;
  final press = _ceilDiv(
    BigInt.from(cal.ditLength) + BigInt.from(cal.dahLength),
    two,
  );
  final letter = _ceilDiv(
    BigInt.from(cal.symbolGap) + BigInt.from(cal.letterGap),
    two,
  );
  final (factorNumerator, factorDenominator) = _exactFraction(factor);
  final lg = BigInt.from(cal.letterGap);
  final product = _ceilDiv(factorNumerator * lg, factorDenominator);
  final aboveLetterGap = lg + BigInt.one;
  final word = product >= aboveLetterGap ? product : aboveLetterGap;
  return (
    pressThreshold: press.toInt(),
    letterGapThreshold: letter.toInt(),
    wordGapThreshold: word.toInt(),
  );
}

/// A Switch_Event as a plain record: `true` for a press, `false` for a
/// release, and the timestamp in Microseconds. REQ-EVENT-1.
typedef EventRecord = (bool isPress, int timestamp);

/// The glossary Ideal_Timing of [text] for [cal], starting with a press at
/// [start].
///
/// Every dit Press lasts Dit_Length and every dah Press Dah_Length. A Gap
/// between two Symbols of one character lasts Symbol_Gap, a Gap between two
/// characters of one word lasts Letter_Gap, and a Gap across one or more
/// spaces lasts `(1.5 × W).round()`, where `W` is the Word_Gap_Threshold
/// from [exactThresholds] for [factor]. Leading and trailing spaces add
/// nothing. Characters are looked up in the ITU fixture after upper-casing
/// ASCII letters; any other character throws an [ArgumentError].
/// REQ-CAL-2, REQ-CAL-15.
List<EventRecord> idealTiming(
  String text,
  CalibrationRecord cal,
  double factor,
  int start,
) {
  final wordGap = (1.5 * exactThresholds(cal, factor).wordGapThreshold).round();
  final events = <EventRecord>[];
  var t = start;
  var spacePending = false;
  for (final unit in text.codeUnits) {
    final character = String.fromCharCode(unit);
    if (character == ' ') {
      spacePending = true;
      continue;
    }
    final isLower = unit >= 0x61 && unit <= 0x7A;
    final code = ituFixture[isLower ? character.toUpperCase() : character];
    if (code == null) {
      throw ArgumentError.value(text, 'text', 'has no Morse code');
    }
    // The Gap before the character's first Symbol, when one exists.
    if (events.isNotEmpty) t += spacePending ? wordGap : cal.letterGap;
    spacePending = false;
    for (var k = 0; k < code.length; k++) {
      if (k > 0) t += cal.symbolGap;
      events.add((true, t));
      t += code[k] == '.' ? cal.ditLength : cal.dahLength;
      events.add((false, t));
    }
  }
  return events;
}

/// The ITU fixture code of one UTF-16 code unit, after folding `a`-`z` to
/// `A`-`Z`, or null for a space or any unit the fixture lacks.
/// REQ-CAL-3, REQ-CAL-20.
String? _fixtureCode(int unit) {
  final folded = unit >= 0x61 && unit <= 0x7A ? unit - 0x20 : unit;
  return ituFixture[String.fromCharCode(folded)];
}

/// The keying plan of [text]: the Symbols of every character with a fixture
/// code, in order, and the class of each Gap between consecutive Symbols:
/// 0 inside a character, 1 between characters, 2 across one or more spaces.
/// Characters without a code add nothing. `gapClasses` has one entry fewer
/// than `symbols` has characters, or none. REQ-CAL-2, REQ-CAL-4.
({String symbols, List<int> gapClasses}) keyingPlan(String text) {
  final codes = <String>[];
  final spaceBefore = <bool>[];
  var space = false;
  for (final unit in text.codeUnits) {
    if (unit == 0x20) {
      space = true;
      continue;
    }
    final code = _fixtureCode(unit);
    if (code == null) continue;
    codes.add(code);
    spaceBefore.add(space);
    space = false;
  }
  final gapClasses = <int>[];
  for (var c = 0; c < codes.length; c++) {
    if (c > 0) gapClasses.add(spaceBefore[c] ? 2 : 1);
    gapClasses.addAll(List<int>.filled(codes[c].length - 1, 0));
  }
  return (symbols: codes.join(), gapClasses: gapClasses);
}

/// The name of the first REQ-CAL-3 rule [word] fails, or null when it is a
/// suitable Calibration_Word. Characters are UTF-16 code units. The rules
/// are all evaluated, then the first failing one in REQ-CAL-3 order is
/// picked: `empty`, `tooLong` (more than 16), `badCharacter` (a space or no
/// code), `tooShort` (fewer than 2), `noDit`, `noDah`, `noLongCode`.
/// REQ-CAL-3.
String? referenceWordRule(String word) {
  final units = word.codeUnits;
  final codes = <String?>[for (final u in units) _fixtureCode(u)];
  final all = codes.whereType<String>().join();
  final failures = <String, bool>{
    'empty': units.isEmpty,
    'tooLong': units.length > 16,
    'badCharacter': codes.contains(null),
    'tooShort': units.length < 2,
    'noDit': !all.contains('.'),
    'noDah': !all.contains('-'),
    'noLongCode': !codes.any((c) => c != null && c.length >= 2),
  };
  for (final entry in failures.entries) {
    if (entry.value) return entry.key;
  }
  return null;
}

/// The largest accepted timestamp magnitude, 2^52. REQ-EVENT-1.
const int _timestampBound = 4503599627370496;

/// The first REQ-EVENT-3 violation in [events] as the error kind name and
/// event index, or null for a Valid_Event_Sequence.
///
/// Unlike the engine's early-return scan, this collects every violation at
/// every index with its precedence (0 timestamp out of range, 1 starts with
/// release, 2 two presses in a row, 3 two releases in a row, 4 decreasing
/// timestamp), then picks the lowest index and, at that index, the lowest
/// precedence. Ends with press is reported, at the last index, only when
/// nothing else is collected. [events] is not changed.
/// REQ-EVENT-3, REQ-EVENT-5.
({String rule, int index})? referenceValidate(List<EventRecord> events) {
  const rules = <String>[
    'timestampOutOfRange',
    'startsWithRelease',
    'twoPressesInARow',
    'twoReleasesInARow',
    'decreasingTimestamp',
  ];
  final found = <(int, int)>[];
  for (var i = 0; i < events.length; i++) {
    final (isPress, t) = events[i];
    if (t < -_timestampBound || t > _timestampBound) found.add((i, 0));
    if (i == 0 && !isPress) found.add((i, 1));
    if (i > 0) {
      final (previousIsPress, previousT) = events[i - 1];
      if (isPress && previousIsPress) found.add((i, 2));
      if (!isPress && !previousIsPress) found.add((i, 3));
      if (t < previousT) found.add((i, 4));
    }
  }
  if (found.isEmpty) {
    if (events.isNotEmpty && events.last.$1) {
      return (rule: 'endsWithPress', index: events.length - 1);
    }
    return null;
  }
  found.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  return (rule: rules[found.first.$2], index: found.first.$1);
}

/// The median of REQ-CAL-7: the middle value of an odd count; for an even
/// count the mean of the two middle values rounded half up, computed in
/// `BigInt`. [values] must be non-empty and is not changed. REQ-CAL-7.
int _referenceMedian(List<int> values) {
  final sorted = List<int>.of(values)..sort();
  final n = sorted.length;
  if (n.isOdd) return sorted[n ~/ 2];
  final sum = BigInt.from(sorted[n ~/ 2 - 1]) + BigInt.from(sorted[n ~/ 2]);
  return ((sum + BigInt.one) ~/ BigInt.two).toInt();
}

/// Whether some value of [shorter] is at least some value of [longer].
bool _overlaps(List<int> shorter, List<int> longer) =>
    shorter.any((x) => longer.any((y) => x >= y));

/// The outcome of [referenceCalibrate]. `reason` is the Rejection_Reason
/// name, or null when accepted. `eventRule` and `eventIndex` are set for
/// `invalidEvents`; `expectedPresses` and `receivedPresses` for
/// `wrongPressCount`; `calibration` only when accepted. REQ-CAL-31.
typedef CalibrationOutcome = ({
  String? reason,
  String? eventRule,
  int? eventIndex,
  int? expectedPresses,
  int? receivedPresses,
  CalibrationRecord? calibration,
});

CalibrationOutcome _rejected(
  String reason, {
  String? eventRule,
  int? eventIndex,
  int? expectedPresses,
  int? receivedPresses,
}) => (
  reason: reason,
  eventRule: eventRule,
  eventIndex: eventIndex,
  expectedPresses: expectedPresses,
  receivedPresses: receivedPresses,
  calibration: null,
);

/// The Calibrator written from the requirements: the REQ-CAL-3 word rules
/// ([referenceWordRule]), the Valid_Event_Sequence check
/// ([referenceValidate]), pairing and [referenceDebounce] with [d], the
/// count, the dit/dah then gap separation (any expected-shorter value at
/// least any expected-longer value), the REQ-CAL-7 medians, then the zero
/// and 2^40 checks, returning at the first that applies in the REQ-CAL-12
/// order. [events] is not changed. REQ-CAL-3, REQ-CAL-5, REQ-CAL-7 to
/// REQ-CAL-12, REQ-CAL-30, REQ-CAL-31.
CalibrationOutcome referenceCalibrate(
  String word,
  List<EventRecord> events,
  int d,
) {
  if (referenceWordRule(word) != null) return _rejected('unsuitableWord');

  final violation = referenceValidate(events);
  if (violation != null) {
    return _rejected(
      'invalidEvents',
      eventRule: violation.rule,
      eventIndex: violation.index,
    );
  }

  final paired = <PressRecord>[
    for (var i = 0; i + 1 < events.length; i += 2)
      (events[i].$2, events[i + 1].$2),
  ];
  final presses = referenceDebounce(paired, d);
  final plan = keyingPlan(word);
  if (presses.length != plan.symbols.length) {
    return _rejected(
      'wrongPressCount',
      expectedPresses: plan.symbols.length,
      receivedPresses: presses.length,
    );
  }

  final dits = <int>[
    for (var i = 0; i < presses.length; i++)
      if (plan.symbols[i] == '.') presses[i].$2 - presses[i].$1,
  ];
  final dahs = <int>[
    for (var i = 0; i < presses.length; i++)
      if (plan.symbols[i] == '-') presses[i].$2 - presses[i].$1,
  ];
  final inside = <int>[
    for (var j = 0; j < plan.gapClasses.length; j++)
      if (plan.gapClasses[j] == 0) presses[j + 1].$1 - presses[j].$2,
  ];
  final between = <int>[
    for (var j = 0; j < plan.gapClasses.length; j++)
      if (plan.gapClasses[j] == 1) presses[j + 1].$1 - presses[j].$2,
  ];
  if (_overlaps(dits, dahs)) return _rejected('pressesOverlap');
  if (_overlaps(inside, between)) return _rejected('gapsOverlap');

  final medians = <int>[
    _referenceMedian(dits),
    _referenceMedian(dahs),
    _referenceMedian(inside),
    _referenceMedian(between),
  ];
  if (medians.contains(0)) return _rejected('zeroDuration');
  if (medians.any((m) => m > 1099511627776)) {
    return _rejected('durationTooLong');
  }
  return (
    reason: null,
    eventRule: null,
    eventIndex: null,
    expectedPresses: null,
    receivedPresses: null,
    calibration: (
      ditLength: medians[0],
      dahLength: medians[1],
      symbolGap: medians[2],
      letterGap: medians[3],
    ),
  );
}

/// One Decoded_Item as a plain record. `kind` is `letter`, `unknownLetter`
/// or `wordSpace`; `value` is the character for a letter, the Symbol
/// sequence for an unknown letter, and the empty string for a Word_Space.
/// REQ-BATCH-1, REQ-BATCH-2, REQ-BATCH-3.
typedef DecodedRecord = ({String kind, String value});

/// The ITU fixture read backwards: Morse code to character.
final Map<String, String> _fixtureCharacters = <String, String>{
  for (final entry in ituFixture.entries) entry.value: entry.key,
};

/// The Batch_Decoder written from REQ-BATCH-1 to REQ-BATCH-4.
///
/// [events] must be a Valid_Event_Sequence. Pairs the events into Presses,
/// debounces them with [referenceDebounce] and [d], and takes the
/// thresholds from [exactThresholds] for [cal] and [factor]. Unlike the
/// engine's single pass, it first classifies every Symbol and every Gap,
/// then cuts the Symbol string into letters at the between-letters and
/// between-words Gaps, and finally maps each letter through the ITU
/// fixture, putting one Word_Space before each letter that follows a
/// between-words Gap. [events] is not changed.
/// REQ-BATCH-1, REQ-BATCH-2, REQ-BATCH-3, REQ-BATCH-4.
List<DecodedRecord> referenceDecode(
  List<EventRecord> events,
  CalibrationRecord cal,
  int d,
  double factor,
) {
  final paired = <PressRecord>[
    for (var i = 0; i + 1 < events.length; i += 2)
      (events[i].$2, events[i + 1].$2),
  ];
  final kept = referenceDebounce(paired, d);
  final t = exactThresholds(cal, factor);

  final symbols = <String>[
    for (final (a, b) in kept) b - a >= t.pressThreshold ? '-' : '.',
  ];
  // gapClass[j] is the class of the Gap before Press j + 1:
  // 0 inside a letter, 1 between letters, 2 between words.
  final gapClass = <int>[
    for (var j = 1; j < kept.length; j++)
      switch (kept[j].$1 - kept[j - 1].$2) {
        final g when g >= t.wordGapThreshold => 2,
        final g when g >= t.letterGapThreshold => 1,
        _ => 0,
      },
  ];

  // Letters as (Symbol string, preceded by a between-words Gap).
  final letters = <(String, bool)>[];
  var start = 0;
  for (var i = 1; i <= symbols.length; i++) {
    final ends = i == symbols.length || gapClass[i - 1] != 0;
    if (!ends) continue;
    final wordBefore = start > 0 && gapClass[start - 1] == 2;
    letters.add((symbols.sublist(start, i).join(), wordBefore));
    start = i;
  }

  return <DecodedRecord>[
    for (final (code, wordBefore) in letters) ...[
      if (wordBefore) (kind: 'wordSpace', value: ''),
      _fixtureCharacters.containsKey(code)
          ? (kind: 'letter', value: _fixtureCharacters[code]!)
          : (kind: 'unknownLetter', value: code),
    ],
  ];
}

/// The kind of one Live_Decoder call. REQ-LIVE-1.
enum LiveCallKind {
  /// A press call. REQ-LIVE-3.
  press,

  /// A release call. REQ-LIVE-3.
  release,

  /// An `advanceTo(now)` call. REQ-LIVE-4, REQ-LIVE-10.
  advance,
}

/// One Live_Decoder call as a plain record: its kind and its timestamp in
/// Microseconds. REQ-LIVE-1.
typedef LiveCallRecord = ({LiveCallKind kind, int timestamp});

/// The state [liveOracleTrace] expects after one call: the Partial_Sequence
/// and whether the switch is pressed. REQ-LIVE-2.
typedef LiveTraceStep = ({String partial, bool pressed});

/// The Partial_Sequence the requirements give after the settling call at
/// index [s] of [calls] (a press call, or an `advanceTo` while released).
///
/// Written from REQ-LIVE-4 to REQ-LIVE-6 and REQ-LIVE-14 as a function of
/// the calls received so far, not as a state machine. With `S` the time of
/// call [s], the Presses received so far are grouped into merge runs (a
/// press less than [d] after the previous release joins its run,
/// REQ-LIVE-5). The last run is still open (the Pending_Press) while it is
/// held or released less than [d] before `S`; every other run is closed.
/// The closed runs lasting at least [d] are the kept Presses (REQ-LIVE-4,
/// REQ-LIVE-14). The Partial_Sequence holds the Symbols of the kept Presses
/// after the last Gap of at least the Letter_Gap_Threshold, unless the
/// letter is already complete: the time from the last kept release to the
/// open run's press, or to `S` when no run is open, reaches the
/// Letter_Gap_Threshold (REQ-LIVE-6).
String _livePartialAt(
  List<LiveCallRecord> calls,
  int s,
  int d,
  ThresholdRecord t,
) {
  final now = calls[s].timestamp;
  // Merge runs as (press timestamp, release timestamp or null while held).
  final runs = <(int, int?)>[];
  for (var i = 0; i <= s; i++) {
    final c = calls[i];
    switch (c.kind) {
      case LiveCallKind.press:
        final previousEnd = runs.isEmpty ? null : runs.last.$2;
        if (previousEnd != null && c.timestamp - previousEnd < d) {
          runs.last = (runs.last.$1, null);
        } else {
          runs.add((c.timestamp, null));
        }
      case LiveCallKind.release:
        runs.last = (runs.last.$1, c.timestamp);
      case LiveCallKind.advance:
        break;
    }
  }
  (int, int?)? open;
  if (runs.isNotEmpty) {
    final lastEnd = runs.last.$2;
    if (lastEnd == null || now - lastEnd < d) open = runs.last;
  }
  final closed = open == null ? runs : runs.sublist(0, runs.length - 1);
  final kept = <PressRecord>[
    for (final (a, b) in closed)
      if (b! - a >= d) (a, b),
  ];
  if (kept.isEmpty) return '';

  final lastRelease = kept.last.$2;
  final silenceEnd = open == null ? now : open.$1;
  if (silenceEnd - lastRelease >= t.letterGapThreshold) return '';

  var first = kept.length - 1;
  while (first > 0 &&
      kept[first].$1 - kept[first - 1].$2 < t.letterGapThreshold) {
    first--;
  }
  return <String>[
    for (final (a, b) in kept.sublist(first))
      b - a >= t.pressThreshold ? '-' : '.',
  ].join();
}

/// The Partial_Sequence and pressed state the requirements give after each
/// of [calls], fed in order to a new Live_Decoder for [cal], [d] and
/// [factor]. [calls] must be valid: press and release alternate starting
/// with a press, and timestamps never decrease.
///
/// The pressed state follows the kind of the last press or release call
/// (REQ-LIVE-3). The Partial_Sequence changes only on a press call or on an
/// `advanceTo` while released (REQ-LIVE-4, REQ-LIVE-6, REQ-LIVE-10), and is
/// recomputed from scratch at each such call by [_livePartialAt]. Thresholds
/// come from [exactThresholds]. [calls] is not changed.
/// REQ-LIVE-3, REQ-LIVE-4, REQ-LIVE-5, REQ-LIVE-6, REQ-LIVE-10,
/// REQ-LIVE-14.
List<LiveTraceStep> liveOracleTrace(
  List<LiveCallRecord> calls,
  CalibrationRecord cal,
  int d,
  double factor,
) {
  final t = exactThresholds(cal, factor);
  final steps = <LiveTraceStep>[];
  var pressed = false;
  var partial = '';
  for (var i = 0; i < calls.length; i++) {
    final kind = calls[i].kind;
    if (kind == LiveCallKind.release) pressed = false;
    final settles =
        kind == LiveCallKind.press ||
        (kind == LiveCallKind.advance && !pressed);
    if (kind == LiveCallKind.press) pressed = true;
    if (settles) partial = _livePartialAt(calls, i, d, t);
    steps.add((partial: partial, pressed: pressed));
  }
  return steps;
}
