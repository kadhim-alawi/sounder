import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

import 'support/itu_fixture.dart';

void main() {
  const table = CodeTable();

  // The expected key set, written out independently of both `lib/` and the
  // ITU fixture. REQ-CODE-1.
  final expectedKeys = <String>{
    ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''),
    ...'0123456789'.split(''),
    ...'.,?/-()'.split(''),
  };

  group('codes', () {
    test('REQ-CODE-1 holds exactly the 43 supported characters as keys', () {
      expect(expectedKeys, hasLength(43));
      expect(table.codes, hasLength(43));
      expect(table.codes.keys.toSet(), equals(expectedKeys));
    });

    test('REQ-CODE-1 has no lowercase, space or other keys', () {
      for (final key in table.codes.keys) {
        expect(key, hasLength(1), reason: 'key "$key" is not one character');
        expect(key, isNot(matches(RegExp('[a-z]'))),
            reason: 'key "$key" is lowercase');
        expect(key, isNot(' '), reason: 'space is a key');
      }
      for (final absent in [' ', 'a', 'z', 'e', '!', ':', '', 'AB']) {
        expect(table.codes.containsKey(absent), isFalse,
            reason: '"$absent" must not be a key');
      }
    });

    test('REQ-CODE-2 REQ-TEST-2 maps A, E, T, 1 and 0 to their ITU codes', () {
      expect(table.codes['A'], '.-');
      expect(table.codes['E'], '.');
      expect(table.codes['T'], '-');
      expect(table.codes['1'], '.----');
      expect(table.codes['0'], '-----');
    });

    test('REQ-CODE-3 REQ-TEST-2 maps the seven punctuation marks', () {
      expect(table.codes['.'], '.-.-.-');
      expect(table.codes[','], '--..--');
      expect(table.codes['?'], '..--..');
      expect(table.codes['/'], '-..-.');
      expect(table.codes['-'], '-....-');
      expect(table.codes['('], '-.--.');
      expect(table.codes[')'], '-.--.-');
    });
  });

  group('characters', () {
    test('REQ-CODE-6 reverse lookup has 43 entries mapping back to uppercase',
        () {
      expect(table.characters, hasLength(43));
      for (final entry in table.codes.entries) {
        expect(table.characters[entry.value], entry.key,
            reason: 'reverse of "${entry.value}"');
      }
    });
  });

  group('invalid lookups', () {
    test('REQ-CODE-9 codeFor returns null for non-supported input', () {
      for (final input in ['', ' ', 'AB', 'ı', '!']) {
        expect(() => table.codeFor(input), returnsNormally,
            reason: 'codeFor("$input") threw');
        expect(table.codeFor(input), isNull,
            reason: 'codeFor("$input") was not null');
      }
    });

    test('REQ-CODE-9 characterFor returns null for non-codes', () {
      for (final input in ['', '.......', '. -', '/']) {
        expect(() => table.characterFor(input), returnsNormally,
            reason: 'characterFor("$input") threw');
        expect(table.characterFor(input), isNull,
            reason: 'characterFor("$input") was not null');
      }
    });
  });

  group('immutability', () {
    final maps = <String, Map<String, String> Function()>{
      'codes': () => table.codes,
      'characters': () => table.characters,
    };

    maps.forEach((name, get) {
      test('REQ-CODE-10 $name rejects []=, remove, clear and addAll', () {
        final map = get();
        final snapshot = Map<String, String>.of(map);

        expect(() => map['Q'] = '.', throwsUnsupportedError);
        expect(() => map['NEW'] = '.', throwsUnsupportedError);
        expect(() => map.remove(map.keys.first), throwsUnsupportedError);
        expect(() => map.clear(), throwsUnsupportedError);
        expect(() => map.addAll({'NEW': '.'}), throwsUnsupportedError);

        expect(get(), hasLength(43));
        expect(get(), equals(snapshot));
      });
    });
  });

  group('ITU fixture', () {
    test('REQ-TEST-3 REQ-CODE-1 REQ-CODE-2 REQ-CODE-3 matches ITU-R M.1677-1',
        () {
      final codes = table.codes;

      expect(codes.length, 43,
          reason: 'wrong count: CodeTable has ${codes.length} entries, '
              'expected 43');
      expect(ituFixture.length, 43,
          reason: 'wrong count: fixture has ${ituFixture.length} entries, '
              'expected 43');

      final missing =
          ituFixture.keys.where((c) => !codes.containsKey(c)).toList();
      expect(missing, isEmpty,
          reason: 'missing character: fixture characters absent from '
              'CodeTable: $missing');

      final extra =
          codes.keys.where((c) => !ituFixture.containsKey(c)).toList();
      expect(extra, isEmpty,
          reason: 'extra character: CodeTable characters absent from '
              'fixture: $extra');

      final differing = [
        for (final entry in ituFixture.entries)
          if (codes.containsKey(entry.key) && codes[entry.key] != entry.value)
            '${entry.key}: CodeTable "${codes[entry.key]}", '
                'fixture "${entry.value}"',
      ];
      expect(differing, isEmpty,
          reason: 'differing code: $differing');
    });
  });
}
