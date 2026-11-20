/// Property-based tests for morse-core, one `property(...)` per correctness
/// property in the design. Each uses a single `forAll` with
/// `maxExamples: 200`, the fixed seed `N*1000 + 3` for Property N, and
/// `onFalsify: report(seed)`. REQ-TEST-1, REQ-TEST-6.
library;

import 'package:kiri_check/kiri_check.dart';
import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

import 'support/arbitraries.dart';
import 'support/itu_fixture.dart';
import 'support/oracles.dart';

const CodeTable table = CodeTable();
const MorseEncoder encoder = MorseEncoder();

void main() {
  // Feature: morse-core, Property 1: for any Supported_Character c, exactly
  // one entry of CodeTable.codes has the code codeFor(c). Changed by bugfix
  // spec morse-core-unique-codes-property.
  property('REQ-CODE-4 codes are unique', () {
    forAll(
      supportedChar(),
      (c) {
        final code = table.codeFor(c);
        expect(code, isNotNull, reason: 'codeFor($c) is null');
        final sharing = table.codes.entries
            .where((entry) => entry.value == code)
            .map((entry) => entry.key)
            .toList();
        expect(sharing.length, equals(1),
            reason: 'codeFor($c) is "$code", shared by '
                '${sharing.length} entries: ${sharing.join(' ')}');
      },
      maxExamples: 200,
      seed: 1003,
      onFalsify: report(1003),
    );
  });

  // Feature: morse-core, Property 2: for any Supported_Character c,
  // codeFor(c) is non-null, matches ^[.-]{1,6}$, and
  // characterFor(codeFor(c)) == asciiUpper(c)
  property(
      'REQ-CODE-5 REQ-CODE-7 REQ-CODE-8 table round trip and code shape', () {
    final shape = RegExp(r'^[.-]{1,6}$');
    forAll(
      supportedChar(),
      (c) {
        final code = table.codeFor(c);
        expect(code, isNotNull, reason: 'codeFor($c) is null');
        expect(code, matches(shape), reason: 'codeFor($c) has a bad shape');
        expect(table.characterFor(code!), equals(asciiUpper(c)),
            reason: 'round trip failed for $c');
      },
      maxExamples: 200,
      seed: 2003,
      onFalsify: report(2003),
    );
  });

  // Feature: morse-core, Property 3: for any string s that is not a single
  // Supported_Character, codeFor(s) is null; for any string m that is not a
  // key of CodeTable.characters, characterFor(m) is null; neither throws
  property('REQ-CODE-9 invalid lookups return null without throwing', () {
    forAll(
      combine2<String, String>(notSupportedCharString(), notCodeString()),
      (pair) {
        final (s, m) = pair;
        expect(() => table.codeFor(s), returnsNormally,
            reason: 'codeFor threw for ${s.codeUnits}');
        expect(table.codeFor(s), isNull,
            reason: 'codeFor returned a code for ${s.codeUnits}');
        expect(() => table.characterFor(m), returnsNormally,
            reason: 'characterFor threw for "$m"');
        expect(table.characterFor(m), isNull,
            reason: 'characterFor returned a character for "$m"');
      },
      maxExamples: 200,
      seed: 3003,
      onFalsify: report(3003),
    );
  });

  // Feature: morse-core, Property 4: for any Plain_Text s of
  // Supported_Characters and spaces, encode(s) equals the reference built
  // from normalise(s) and the ITU fixture, and
  // encode(s) == encode(asciiUpper(s))
  property(
      'REQ-ENC-1 REQ-ENC-2 REQ-ENC-3 REQ-ENC-4 REQ-ENC-5 REQ-ENC-6 '
      'REQ-ENC-7 REQ-ENC-11 encoder matches the reference model', () {
    forAll(
      plainText(),
      (s) {
        final encoded = encoder.encode(s);
        expect(encoded, equals(referenceEncode(s)),
            reason: 'encode("$s") differs from the reference model');
        expect(encoder.encode(asciiUpper(s)), equals(encoded),
            reason: 'encode("$s") differs from encode of its uppercase form');
      },
      maxExamples: 200,
      seed: 4003,
      onFalsify: report(4003),
    );
  });

  // Feature: morse-core, Property 5: for any Plain_Text s of
  // Supported_Characters and spaces, encode(s) conforms to the REQ-FMT-1
  // grammar as checked by the independent oracle isEncodedText
  property(
      'REQ-ENC-6 REQ-ENC-10 REQ-FMT-2 encoder output conforms to the format',
      () {
    forAll(
      plainText(),
      (s) {
        final encoded = encoder.encode(s);
        expect(isEncodedText(encoded), isTrue,
            reason: 'encode("$s") gave "$encoded", which does not match '
                'the REQ-FMT-1 grammar');
      },
      maxExamples: 200,
      seed: 5003,
      onFalsify: report(5003),
    );
  });

  // Feature: morse-core, Property 10: for any Plain_Text prefix p, any
  // Unsupported_Character u and any suffix q, encode(p + u + q) throws one
  // MorseFormatException with requirementId 'REQ-ERR-1', position p.length
  // and offending u, and returns no value
  property(
      'REQ-ERR-1 REQ-ERR-9 REQ-ERR-10 encoder reports the first unsupported '
      'character', () {
    forAll(
      // Cases where u is a lone high surrogate and q starts with a low
      // surrogate are filtered out: p + u + q would then hold a valid pair,
      // and the first Unsupported_Character would be two code units, not u.
      // p never contains surrogates, so a lone low surrogate u cannot pair
      // with the end of p.
      combine3<String, String, String>(
        plainText(),
        unsupportedChar(),
        _suffix(),
      ).filter((r) => !(_isLoneHigh(r.$2) && _startsWithLow(r.$3))),
      (r) {
        final (p, u, q) = r;
        final input = p + u + q;
        Object? returned;
        MorseFormatException? error;
        try {
          returned = encoder.encode(input);
        } on MorseFormatException catch (e) {
          error = e;
        }
        expect(returned, isNull,
            reason: 'encode returned "$returned" for ${input.codeUnits}');
        expect(error, isNotNull,
            reason: 'encode did not throw for ${input.codeUnits}');
        expect(error!.requirementId, equals('REQ-ERR-1'),
            reason: 'wrong requirementId for ${input.codeUnits}');
        expect(error.position, equals(p.length),
            reason: 'wrong position for ${input.codeUnits}');
        expect(error.offending.codeUnits, equals(u.codeUnits),
            reason: 'wrong offending character for ${input.codeUnits}');
      },
      maxExamples: 200,
      seed: 10003,
      onFalsify: report(10003),
    );
  });
}

/// Suffix for Property 10: up to 10 characters mixing Supported_Characters,
/// spaces and further Unsupported_Characters. REQ-ERR-1, REQ-ERR-10.
Arbitrary<String> _suffix() => list<String>(
      oneOf(<Arbitrary<dynamic>>[
        supportedChar(),
        constantFrom<String>(const <String>[' ']),
        unsupportedChar(),
      ]).cast<String>(),
      maxLength: 10,
    ).map((chars) => chars.join());

bool _isLoneHigh(String u) {
  if (u.length != 1) return false;
  final unit = u.codeUnitAt(0);
  return unit >= 0xD800 && unit <= 0xDBFF;
}

bool _startsWithLow(String q) {
  if (q.isEmpty) return false;
  final unit = q.codeUnitAt(0);
  return unit >= 0xDC00 && unit <= 0xDFFF;
}

/// Reference model for Property 4: splits the Normalised_Text of [s] on
/// single spaces (no words if it is empty), replaces each character with its
/// ITU fixture code, and joins codes with `' '` and words with `' / '`.
/// Built from the fixture, not from `CodeTable`. REQ-ENC-1 to REQ-ENC-7.
String referenceEncode(String s) {
  final normalised = normalise(s);
  if (normalised.isEmpty) return '';
  return normalised
      .split(' ')
      .map((word) => word.split('').map((c) => ituFixture[c]!).join(' '))
      .join(' / ');
}
