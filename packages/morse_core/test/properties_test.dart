/// Property-based tests for morse-core, one `property(...)` per correctness
/// property in the design. Each uses a single `forAll` with
/// `maxExamples: 200`, the fixed seed `N*1000 + 3` for Property N, and
/// `onFalsify: report(seed)`. REQ-TEST-1, REQ-TEST-6.
library;

import 'package:kiri_check/kiri_check.dart';
import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

import 'support/arbitraries.dart';
import 'support/oracles.dart';

const CodeTable table = CodeTable();

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
}
