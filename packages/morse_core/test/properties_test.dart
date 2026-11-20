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
const MorseDecoder decoder = MorseDecoder();

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

  // Feature: morse-core, Property 6: decode(encode(s)) equals the Normalised_Text of s
  property('REQ-FMT-3 text round trip', () {
    forAll(
      plainText(),
      (s) {
        final encoded = encoder.encode(s);
        String? decoded;
        expect(() => decoded = decoder.decode(encoded), returnsNormally,
            reason: 'decode("$encoded") threw for encode("$s")');
        expect(decoded, equals(normalise(s)),
            reason: 'decode(encode("$s")) differs from normalise("$s")');
      },
      maxExamples: 200,
      seed: 6003,
      onFalsify: report(6003),
    );
  });

  // Feature: morse-core, Property 7: encode(decode(m)) == m for generated Encoded_Text
  property(
      'REQ-DEC-1 REQ-DEC-2 REQ-DEC-3 REQ-FMT-4 REQ-FMT-5 code round trip',
      () {
    forAll(
      encodedText(),
      (m) {
        String? decoded;
        expect(() => decoded = decoder.decode(m), returnsNormally,
            reason: 'decode("$m") threw');
        String? reencoded;
        expect(() => reencoded = encoder.encode(decoded!), returnsNormally,
            reason: 'encode("$decoded") threw for decode("$m")');
        expect(reencoded, equals(m),
            reason: 'encode(decode("$m")) gave "$reencoded"');
      },
      maxExamples: 200,
      seed: 7003,
      onFalsify: report(7003),
    );
  });

  // Feature: morse-core, Property 8: for any generated Encoded_Text m with k
  // codes and w Word_Separators, decode(m) contains only uppercase
  // Supported_Characters and single spaces, has no leading or trailing
  // space, and has length k + w
  property('REQ-DEC-7 decoder output is closed', () {
    final allowed = <String>{...ituFixture.keys, ' '};
    forAll(
      countedEncodedText(),
      (r) {
        final (m, k, w) = r;
        String? decoded;
        expect(() => decoded = decoder.decode(m), returnsNormally,
            reason: 'decode("$m") threw');
        final out = decoded!;
        for (var i = 0; i < out.length; i++) {
          expect(allowed.contains(out[i]), isTrue,
              reason: 'decode("$m") gave "$out", which holds '
                  'code unit ${out.codeUnitAt(i)} at $i');
        }
        expect(out.contains('  '), isFalse,
            reason: 'decode("$m") gave "$out", which holds a double space');
        expect(out.startsWith(' ') || out.endsWith(' '), isFalse,
            reason: 'decode("$m") gave "$out", with a leading or '
                'trailing space');
        expect(out.length, equals(k + w),
            reason: 'decode("$m") gave "$out"; expected length '
                '$k codes + $w separators');
      },
      maxExamples: 200,
      seed: 8003,
      onFalsify: report(8003),
    );
  });

  // Feature: morse-core, Property 9: for any string s over '.', '-', space
  // and '/', decode(s) returns a value iff isEncodedText(s); on success
  // encode(decode(s)) == s; on failure it throws exactly one
  // MorseFormatException with requirementId in REQ-ERR-3 to REQ-ERR-7
  property(
      'REQ-DEC-10 REQ-FMT-5 REQ-FMT-6 REQ-ERR-9 decoder accepts exactly the '
      'conforming strings', () {
    const structuralIds = <String>{
      'REQ-ERR-3',
      'REQ-ERR-4',
      'REQ-ERR-5',
      'REQ-ERR-6',
      'REQ-ERR-7',
    };
    forAll(
      oneOf(<Arbitrary<dynamic>>[decoderAlphabetString(), nearMiss()])
          .cast<String>(),
      (s) {
        String? returned;
        MorseFormatException? error;
        try {
          returned = decoder.decode(s);
        } on MorseFormatException catch (e) {
          error = e;
        }
        if (isEncodedText(s)) {
          expect(error, isNull,
              reason: 'decode("$s") threw ${error?.requirementId} at '
                  '${error?.position} for conforming input');
          expect(encoder.encode(returned!), equals(s),
              reason: 'encode(decode("$s")) gave '
                  '"${encoder.encode(returned)}"');
        } else {
          expect(returned, isNull,
              reason: 'decode("$s") returned "$returned" for '
                  'non-conforming input');
          expect(error, isNotNull,
              reason: 'decode("$s") did not throw for non-conforming input');
          expect(structuralIds.contains(error!.requirementId), isTrue,
              reason: 'decode("$s") threw ${error.requirementId}; expected '
                  'one of REQ-ERR-3 to REQ-ERR-7');
        }
      },
      maxExamples: 200,
      seed: 9003,
      onFalsify: report(9003),
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

  // Feature: morse-core, Property 11: for any non-empty generated
  // Encoded_Text m, index i and non-surrogate code unit c outside '.', '-',
  // space and '/', decoding m with index i replaced by c throws one
  // MorseFormatException with requirementId 'REQ-ERR-2', position i and
  // offending c, and returns no value. One (m, i, c) triple per case.
  property(
      'REQ-ERR-2 REQ-ERR-11 REQ-ERR-12 decoder reports an injected invalid '
      'character', () {
    forAll(
      injectedInvalid(),
      (r) {
        final (m, i, c) = r;
        final input = m.substring(0, i) + c + m.substring(i + 1);
        Object? returned;
        MorseFormatException? error;
        try {
          returned = decoder.decode(input);
        } on MorseFormatException catch (e) {
          error = e;
        }
        expect(returned, isNull,
            reason: 'decode returned "$returned" for ${input.codeUnits}');
        expect(error, isNotNull,
            reason: 'decode did not throw for ${input.codeUnits}');
        expect(error!.requirementId, equals('REQ-ERR-2'),
            reason: 'wrong requirementId for "$m" with U+'
                '${c.codeUnitAt(0).toRadixString(16)} at $i');
        expect(error.position, equals(i),
            reason: 'wrong position for "$m" with code unit '
                '${c.codeUnitAt(0)} at $i');
        expect(error.offending.codeUnits, equals(c.codeUnits),
            reason: 'wrong offending character for "$m" with code unit '
                '${c.codeUnitAt(0)} at $i');
      },
      maxExamples: 200,
      seed: 11003,
      onFalsify: report(11003),
    );
  });

  // Feature: morse-core, Property 12: for any string s (arbitrary Unicode,
  // the decoder alphabet, or mutated Encoded_Text), every
  // MorseFormatException e thrown by encode(s) or decode(s) has
  // 0 <= position < s.length, offset == position, the position in decimal
  // in the message, the quoted Token or the U+XXXX form of the character in
  // the message, source == null and toString() == message
  property('REQ-ERR-8 every error is well formed', () {
    forAll(
      _mixedString(),
      (s) {
        final errors = <(String, MorseFormatException)>[];
        try {
          encoder.encode(s);
        } on MorseFormatException catch (e) {
          errors.add(('encode', e));
        }
        try {
          decoder.decode(s);
        } on MorseFormatException catch (e) {
          errors.add(('decode', e));
        }
        for (final (op, e) in errors) {
          final where = '$op(${s.codeUnits}) threw ${e.requirementId}';
          expect(e.position, inInclusiveRange(0, s.length - 1),
              reason: '$where with position ${e.position} out of range');
          expect(e.offset, equals(e.position),
              reason: '$where with offset ${e.offset} != position');
          expect(
              RegExp('(?<![0-9])${e.position}(?![0-9])').hasMatch(e.message),
              isTrue,
              reason: '$where; message "${e.message}" lacks position '
                  '${e.position}');
          if (_tokenErrors.contains(e.requirementId)) {
            expect(e.message, contains('"${e.offending}"'),
                reason: '$where; message "${e.message}" lacks the quoted '
                    'Token');
          } else {
            expect(e.message, contains(_uPlus(e.offending)),
                reason: '$where; message "${e.message}" lacks '
                    '${_uPlus(e.offending)}');
            if (e.offending == '/') {
              expect(e.message, contains('"/"'),
                  reason: '$where; message "${e.message}" lacks "/"');
            }
          }
          expect(e.source, isNull, reason: '$where with a non-null source');
          expect(e.toString(), equals(e.message),
              reason: '$where; toString() differs from message');
        }
      },
      maxExamples: 200,
      seed: 12003,
      onFalsify: report(12003),
    );
  });

  // Feature: morse-core, Property 13: for any string s, two calls of
  // encode(s) give equal results or both throw MorseFormatException with the
  // same requirementId and position; the same holds for decode(s)
  property('REQ-PURE-2 encoder and decoder are deterministic', () {
    forAll(
      _mixedString(),
      (s) {
        final ops = <String, String Function(String)>{
          'encode': encoder.encode,
          'decode': decoder.decode,
        };
        for (final MapEntry(key: op, value: f) in ops.entries) {
          final first = _outcome(() => f(s));
          final second = _outcome(() => f(s));
          expect(second, equals(first),
              reason: '$op(${s.codeUnits}) gave $first, then $second');
        }
      },
      maxExamples: 200,
      seed: 13003,
      onFalsify: report(13003),
    );
  });
}

/// Mixed string generator shared by Property 12 and Property 13: arbitrary
/// Unicode strings, strings over the decoder alphabet, and near-miss
/// Encoded_Text. REQ-ERR-8, REQ-PURE-2.
Arbitrary<String> _mixedString() => oneOf(<Arbitrary<dynamic>>[
      string(maxLength: 30),
      decoderAlphabetString(),
      nearMiss(),
    ]).cast<String>();

/// Outcome of one encode or decode call for Property 13: `('ok', result)`
/// on return, or `('error', 'requirementId@position')` on a
/// MorseFormatException. Records compare by value. REQ-PURE-2.
(String, String) _outcome(String Function() call) {
  try {
    return ('ok', call());
  } on MorseFormatException catch (e) {
    return ('error', '${e.requirementId}@${e.position}');
  }
}

/// Error kinds whose offending value is a whole Token rather than a single
/// character. REQ-ERR-3, REQ-ERR-4, REQ-ERR-8.
const Set<String> _tokenErrors = <String>{'REQ-ERR-3', 'REQ-ERR-4'};

/// Independent `U+XXXX` form of the single character [c] for Property 12:
/// uppercase hex, at least four digits; a valid surrogate pair gives its
/// combined code point and a lone surrogate gives its code unit. REQ-ERR-8.
String _uPlus(String c) {
  final value = c.length == 2 && _isLoneHigh(c[0]) && _startsWithLow(c[1])
      ? c.runes.single
      : c.codeUnitAt(0);
  return 'U+${value.toRadixString(16).toUpperCase().padLeft(4, '0')}';
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
