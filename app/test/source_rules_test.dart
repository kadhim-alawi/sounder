// Source rule tests. They read the app's own Dart files and check rules that
// no unit test can see from the outside: what lib/compose imports and calls
// (REQ-COMPOSE-1), that no mock reaches lib/ (REQ-CI-3, REQ-APPTEST-4), that
// the expansion code logs nothing (REQ-FAIL-4), that lib/ holds no hardcoded
// Candidate (REQ-APPTEST-4), and that every test description starts with its
// requirement IDs (REQ-CI-2, REQ-APPTEST-5).
//
// The checks run on tokens from a small Dart lexer below, not on raw text, so
// a comment such as "starts no Timer" or a string literal containing a test
// call never counts as code. `flutter test` runs with `app/` as the working
// directory, so all paths are relative to it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

enum _Kind { identifier, string, punct }

final class _Token {
  _Token(this.kind, this.text);
  final _Kind kind;

  /// Identifier name, punctuation character, or a string literal's content
  /// between its quotes (interpolations kept as written).
  final String text;

  /// True for tokens inside a `${...}` interpolation of a string literal.
  bool interpolated = false;

  /// True for a raw string literal (`r'...'`), whose escapes are literal.
  bool raw = false;
}

/// Splits Dart source into identifier, string and punctuation tokens and
/// drops comments and whitespace. Handles nested block comments, raw strings,
/// triple-quoted strings and `${...}` interpolation (whose tokens are kept).
List<_Token> _lex(String src) {
  final tokens = <_Token>[];
  var i = 0;

  bool isIdentStart(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x24;
  bool isIdentPart(int c) => isIdentStart(c) || (c >= 0x30 && c <= 0x39);

  late void Function() lexUntilCloseBrace;

  // Reads a string literal starting at the quote at [i].
  void lexString({required bool raw}) {
    // Interpolation tokens are lexed while reading the literal; the literal's
    // own token goes before them so it stays next to the token preceding it.
    final position = tokens.length;
    final quote = src[i];
    final triple = src.startsWith(quote * 3, i);
    final close = triple ? quote * 3 : quote;
    i += close.length;
    final buf = StringBuffer();
    while (i < src.length && !src.startsWith(close, i)) {
      final ch = src[i];
      if (!raw && ch == r'\' && i + 1 < src.length) {
        buf.write(src.substring(i, i + 2));
        i += 2;
      } else if (!raw && ch == r'$' && src.startsWith(r'${', i)) {
        final start = i;
        i += 2;
        lexUntilCloseBrace();
        buf.write(src.substring(start, i));
      } else {
        buf.write(ch);
        i++;
      }
    }
    i += close.length;
    tokens.insert(position, _Token(_Kind.string, buf.toString())..raw = raw);
    for (var k = position + 1; k < tokens.length; k++) {
      tokens[k].interpolated = true;
    }
  }

  // Lexes one token or skips one comment or whitespace run at [i].
  void step() {
    final c = src.codeUnitAt(i);
    if (src.startsWith('//', i)) {
      final end = src.indexOf('\n', i);
      i = end < 0 ? src.length : end;
    } else if (src.startsWith('/*', i)) {
      var depth = 0;
      do {
        if (src.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (src.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      } while (depth > 0 && i < src.length);
    } else if (c == 0x27 || c == 0x22) {
      lexString(raw: false);
    } else if (isIdentStart(c) || (c >= 0x30 && c <= 0x39)) {
      final start = i;
      while (i < src.length && isIdentPart(src.codeUnitAt(i))) {
        i++;
      }
      final word = src.substring(start, i);
      if (word == 'r' && i < src.length && (src[i] == "'" || src[i] == '"')) {
        lexString(raw: true);
      } else {
        tokens.add(_Token(_Kind.identifier, word));
      }
    } else if (c <= 0x20) {
      i++;
    } else {
      tokens.add(_Token(_Kind.punct, src[i]));
      i++;
    }
  }

  lexUntilCloseBrace = () {
    var depth = 1;
    while (i < src.length) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') {
        depth--;
        if (depth == 0) {
          i++;
          return;
        }
      }
      if (src[i] == '{' || src[i] == '}') {
        i++;
      } else {
        step();
      }
    }
  };

  while (i < src.length) {
    step();
  }
  return tokens;
}

/// All `.dart` files under [dir], relative to the `app/` working directory.
List<File> _dartFiles(String dir) {
  final root = Directory(dir);
  expect(root.existsSync(), isTrue, reason: '$dir not found from app/');
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// URIs of every import, export and part directive in [tokens].
List<String> _directiveUris(List<_Token> tokens) => [
  for (var k = 0; k + 1 < tokens.length; k++)
    if (tokens[k].kind == _Kind.identifier &&
        {'import', 'export', 'part'}.contains(tokens[k].text) &&
        tokens[k + 1].kind == _Kind.string)
      tokens[k + 1].text,
];

bool _isIdent(List<_Token> t, int k, String name) =>
    k >= 0 &&
    k < t.length &&
    t[k].kind == _Kind.identifier &&
    t[k].text == name;

bool _isPunct(List<_Token> t, int k, String ch) =>
    k >= 0 && k < t.length && t[k].kind == _Kind.punct && t[k].text == ch;

/// A description that starts with one or more REQ IDs, comma separated,
/// followed by a colon, for example `REQ-KEY-9, REQ-A11Y-4: ...`.
final _reqPrefix = RegExp(
  r'^REQ-[A-Z0-9]+-\d+[a-z]?(, REQ-[A-Z0-9]+-\d+[a-z]?)*:',
);

/// One `test(`, `testWidgets(` or `property(` call found in a test file.
final class _TestCall {
  _TestCall(this.function, this.description);
  final String function;

  /// The description literal (adjacent literals joined), or null when the
  /// first argument is not a string literal.
  final String? description;
}

List<_TestCall> _testCalls(List<_Token> t) {
  const names = {'test', 'testWidgets', 'property'};
  final calls = <_TestCall>[];
  for (var k = 0; k < t.length; k++) {
    if (t[k].kind != _Kind.identifier || !names.contains(t[k].text)) continue;
    if (!_isPunct(t, k + 1, '(')) continue;
    // `x.test(` is a method call and `void test(` a declaration, not a test.
    if (_isPunct(t, k - 1, '.')) continue;
    if (k > 0 && t[k - 1].kind == _Kind.identifier) continue;
    var j = k + 2;
    final buf = StringBuffer();
    while (j < t.length && (t[j].kind == _Kind.string || t[j].interpolated)) {
      if (!t[j].interpolated) buf.write(t[j].text);
      j++;
    }
    calls.add(_TestCall(t[k].text, j == k + 2 ? null : buf.toString()));
  }
  return calls;
}

/// [file]'s path relative to `app/`, with `/` separators on every platform.
String _posix(File file) => file.path.replaceAll(r'\', '/');

/// The value of a non-raw string literal's text: Dart escapes resolved.
/// Interpolations stay as written, so such a literal never equals a
/// sentence.
String _unescape(String s) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final ch = s[i];
    if (ch != r'\' || i + 1 >= s.length) {
      out.write(ch);
      i++;
      continue;
    }
    final next = s[i + 1];
    i += 2;
    switch (next) {
      case 'n':
        out.write('\n');
      case 'r':
        out.write('\r');
      case 't':
        out.write('\t');
      case 'f':
        out.write('\f');
      case 'b':
        out.write('\b');
      case 'v':
        out.write('\v');
      case 'x':
        out.writeCharCode(int.parse(s.substring(i, i + 2), radix: 16));
        i += 2;
      case 'u':
        if (i < s.length && s[i] == '{') {
          final end = s.indexOf('}', i);
          out.writeCharCode(int.parse(s.substring(i + 1, end), radix: 16));
          i = end + 1;
        } else {
          out.writeCharCode(int.parse(s.substring(i, i + 4), radix: 16));
          i += 4;
        }
      default:
        out.write(next);
    }
  }
  return out.toString();
}

/// The comparison form for the hardcoded-Candidate rule: ASCII letters
/// lowercased, surrounding whitespace trimmed and trailing `.`, `!` and `?`
/// removed. REQ-APPTEST-4.
String _normalise(String s) {
  final lower = String.fromCharCodes([
    for (final c in s.codeUnits) c >= 0x41 && c <= 0x5A ? c + 0x20 : c,
  ]);
  return lower.trim().replaceFirst(RegExp(r'[.!?]+$'), '').trim();
}

/// Every string value written in [t]: each literal on its own, and each run
/// of adjacent literals joined, as Dart concatenates them.
List<String> _literalValues(List<_Token> t) {
  final values = <String>[];
  final run = <String>[];
  void endRun() {
    if (run.length > 1) values.add(run.join());
    run.clear();
  }

  for (final token in t.where((x) => !x.interpolated)) {
    if (token.kind != _Kind.string) {
      endRun();
      continue;
    }
    final value = token.raw ? token.text : _unescape(token.text);
    values.add(value);
    run.add(value);
  }
  endRun();
  return values;
}

/// The six sentences hoped for in spike 3, from the `TESTS` table in
/// `spikes/expand_spike/src/index.ts` (summarised in `spikes/RESULTS.md`).
/// Copied here because nothing under `spikes/` ships or must stay.
const _spike3Sentences = [
  'I want some water please',
  'Can you help me',
  'I am tired',
  'Please call my daughter',
  'I need to go to the bathroom',
  'What time is it',
];

/// Interfaces whose test doubles must be named `Mock...` (REQ-APPTEST-4).
const _mockedSeams = {
  'ExpansionTransport',
  'ExpansionClient',
  'NoticeStore',
  'SpeechService',
};

/// Each class declared in [t], with every identifier between its name and
/// its body (its supertypes, interfaces, mixins and type arguments).
List<({String name, Set<String> supertypes})> _classes(List<_Token> t) => [
  for (var k = 0; k + 1 < t.length; k++)
    if (_isIdent(t, k, 'class') && t[k + 1].kind == _Kind.identifier)
      (
        name: t[k + 1].text,
        supertypes: {
          for (var j = k + 2; j < t.length && !_isPunct(t, j, '{'); j++)
            if (t[j].kind == _Kind.identifier) t[j].text,
        },
      ),
];

void main() {
  test('REQ-COMPOSE-1: lib/compose imports no Flutter, dart:ui, dart:html, '
      'dart:io or dart:js_interop library and uses no clock or timer', () {
    const bannedUris = {'dart:ui', 'dart:html', 'dart:io', 'dart:js_interop'};
    final files = _dartFiles('lib/compose');
    expect(files, isNotEmpty);
    final problems = <String>[];
    for (final file in files) {
      final t = _lex(file.readAsStringSync());
      for (final uri in _directiveUris(t)) {
        if (uri.startsWith('package:flutter') || bannedUris.contains(uri)) {
          problems.add('${file.path}: imports $uri');
        }
      }
      for (var k = 0; k < t.length; k++) {
        if (_isIdent(t, k, 'Stopwatch') || _isIdent(t, k, 'Timer')) {
          problems.add('${file.path}: uses ${t[k].text}');
        }
        if (_isIdent(t, k, 'DateTime') &&
            _isPunct(t, k + 1, '.') &&
            _isIdent(t, k + 2, 'now')) {
          problems.add('${file.path}: uses DateTime.now');
        }
        if (_isIdent(t, k, 'Future') &&
            _isPunct(t, k + 1, '.') &&
            _isIdent(t, k + 2, 'delayed')) {
          problems.add('${file.path}: uses Future.delayed');
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('REQ-CI-3: no file under lib/ defines or uses a Mock class or imports '
      'from test/', () {
    final files = _dartFiles('lib');
    expect(files, isNotEmpty);
    final testDir = Directory('test').absolute.uri.toString();
    final mockName = RegExp(r'^Mock[A-Z0-9_]');
    final problems = <String>[];
    for (final file in files) {
      final t = _lex(file.readAsStringSync());
      for (final uri in _directiveUris(t)) {
        final resolved = file.absolute.uri.resolve(uri).toString();
        if (resolved.startsWith(testDir) ||
            RegExp(r'(^|/)test/').hasMatch(uri)) {
          problems.add('${file.path}: imports $uri');
        }
      }
      for (var k = 0; k < t.length; k++) {
        if (t[k].kind == _Kind.identifier && mockName.hasMatch(t[k].text)) {
          problems.add('${file.path}: names ${t[k].text}');
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('REQ-CI-2, REQ-APPTEST-5: every test, testWidgets and property '
      'description under test/ begins with its REQ IDs and a colon', () {
    final files = _dartFiles('test');
    final problems = <String>[];
    var count = 0;
    var ownCount = 0;
    for (final file in files) {
      final calls = _testCalls(_lex(file.readAsStringSync()));
      count += calls.length;
      if (file.path.endsWith('source_rules_test.dart')) ownCount = calls.length;
      for (final call in calls) {
        final d = call.description;
        if (d == null) {
          problems.add(
            '${file.path}: ${call.function} has no literal '
            'description',
          );
        } else if (!_reqPrefix.hasMatch(d)) {
          problems.add('${file.path}: ${call.function} "$d"');
        }
      }
    }
    // The scan must see this file's own six tests, so it cannot pass
    // vacuously.
    expect(ownCount, 6);
    expect(count, greaterThan(6));
    expect(problems, isEmpty);
  });

  test('REQ-FAIL-4: the expansion files in lib/compose, lib/net, lib/store '
      'and the Key_Screen controller call no print, debugPrint or log and '
      'import no dart:developer', () {
    final files = [
      ..._dartFiles('lib/compose'),
      ..._dartFiles('lib/net'),
      ..._dartFiles('lib/store'),
      File('lib/ui/key_screen_controller.dart'),
    ];
    final paths = files.map(_posix).toSet();
    expect(
      paths,
      containsAll([
        'lib/compose/initials_validator.dart',
        'lib/compose/sentence_tokens.dart',
        'lib/compose/narrowing.dart',
        'lib/compose/expansion_client.dart',
        'lib/net/http_expansion_transport.dart',
        'lib/store/notice_store.dart',
        'lib/ui/key_screen_controller.dart',
      ]),
    );
    final problems = <String>[];
    for (final file in files) {
      final t = _lex(file.readAsStringSync());
      for (final uri in _directiveUris(t)) {
        if (uri == 'dart:developer') problems.add('${file.path}: imports $uri');
      }
      for (var k = 0; k < t.length; k++) {
        // print and debugPrint count as a call or a tear-off; log only as a
        // call or a member access, so a variable named log is allowed.
        final banned =
            _isIdent(t, k, 'print') ||
            _isIdent(t, k, 'debugPrint') ||
            (_isIdent(t, k, 'log') &&
                (_isPunct(t, k + 1, '(') || _isPunct(t, k - 1, '.')));
        if (banned) problems.add('${file.path}: uses ${t[k].text}');
      }
    }
    expect(problems, isEmpty);
  });

  test('REQ-APPTEST-4: no string literal under lib/ equals a valid fixture '
      'candidate or a spike-3 sentence', () {
    final fixture = jsonDecode(
      File('../fixtures/expansion_validator.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final candidates = [
      for (final c in fixture['cases'] as List<dynamic>)
        if ((c as Map<String, dynamic>)['valid'] == true)
          c['candidate'] as String,
    ];
    expect(candidates, isNotEmpty);
    expect(_spike3Sentences, hasLength(6));
    final banned = {
      for (final s in [...candidates, ..._spike3Sentences]) _normalise(s),
    };
    // The rule must be able to fire: a literal holding a fixture candidate
    // is caught, through escapes, case, whitespace and trailing punctuation.
    expect(
      banned,
      contains(_normalise(_literalValues(_lex(r"'I DON\'T know!? '")).single)),
    );
    final problems = <String>[];
    for (final file in _dartFiles('lib')) {
      for (final value in _literalValues(_lex(file.readAsStringSync()))) {
        if (banned.contains(_normalise(value))) {
          problems.add('${file.path}: hardcodes "$value"');
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('REQ-APPTEST-4, REQ-COMPOSE-1, REQ-CI-3: the source rules cover the '
      'new expansion files, and every test double of an expansion or speech '
      'seam under test/ is named Mock', () {
    // REQ-COMPOSE-1 scans every file in lib/compose; REQ-CI-3 every file in
    // lib/.
    expect(
      _dartFiles('lib/compose').map(_posix),
      containsAll([
        'lib/compose/initials_validator.dart',
        'lib/compose/sentence_tokens.dart',
        'lib/compose/narrowing.dart',
        'lib/compose/expansion_client.dart',
      ]),
    );
    expect(
      _dartFiles('lib').map(_posix),
      containsAll([
        'lib/net/http_expansion_transport.dart',
        'lib/store/notice_store.dart',
        'lib/ui/key_screen_controller.dart',
      ]),
    );
    final declared = <String>{};
    final problems = <String>[];
    for (final file in _dartFiles('test')) {
      for (final c in _classes(_lex(file.readAsStringSync()))) {
        declared.add(c.name);
        final seams = c.supertypes.intersection(_mockedSeams);
        if (seams.isNotEmpty && !c.name.startsWith('Mock')) {
          problems.add(
            '${file.path}: ${c.name} implements ${seams.join(', ')}',
          );
        }
      }
    }
    expect(declared, containsAll(['MockExpansionTransport', 'MockDelay']));
    expect(problems, isEmpty);
  });
}
