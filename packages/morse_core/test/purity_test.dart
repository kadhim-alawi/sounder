// Purity and structure tests for morse_core.
//
// `dart:io` is used here, in a test, and never in `lib/`. Every path is
// relative to the package root, which is the working directory of
// `dart test` in `packages/morse_core`, so the test reads only files inside
// this package. REQ-TEST-7.
import 'dart:io';

import 'package:morse_core/morse_core.dart';
import 'package:test/test.dart';

import 'support/requirement_ids.dart';

/// `dart:` libraries a `lib/` file may import. REQ-PURE-1.
const _allowedDartLibraries = {
  'dart:core',
  'dart:collection',
  'dart:convert',
  'dart:math',
  'dart:typed_data',
  'dart:async',
};

/// Imports no `lib/` file may use. REQ-PURE-1, REQ-PURE-3.
const _forbiddenImportPrefixes = [
  'package:flutter',
  'dart:ui',
  'dart:io',
  'dart:html',
  'dart:js_interop',
  'dart:ffi',
  'dart:isolate',
  'dart:mirrors',
];

/// Dev dependencies allowed: test and lint tooling only. REQ-PURE-1.
const _allowedDevDependencies = {'test', 'lints', 'kiri_check'};

/// Identifiers that read the clock, randomness, files, network, processes
/// or the environment. REQ-PURE-3.
final _impureIdentifier = RegExp(
  r'\b(DateTime|Stopwatch|Timer|Random|Platform|Process|File|Directory|'
  r'Socket|HttpClient|HttpRequest|fromEnvironment|Zone)\b|Uri\.base',
);

final _directive = RegExp(r'''^\s*(import|export)\s+['"]([^'"]+)['"]([^;]*);''');

final _typeDeclaration = RegExp(
  r'^(?:(?:abstract|sealed|base|interface|final|mixin)\s+)*'
  r'(class|mixin|enum|typedef|extension\s+type|extension)\s+([A-Za-z_$][\w$]*)',
);

/// A top-level variable without `final` or `const`: a type (or `var`/`late`)
/// followed by a name and `=` or `;`. Functions and getters have `(` or `=>`.
final _mutableTopLevel = RegExp(
  r'^(?!final\b|const\b|import\b|export\b|library\b|part\b|typedef\b)'
  r'(?:late\s+)?(?:var\s+\w+|\w[\w<>?, ]*\s+\w+)\s*(=(?!>)|;)',
);

/// A static field without `final` or `const`.
final _mutableStatic = RegExp(
  r'^\s*static\s+(?!final\b|const\b)(?:late\s+)?'
  r'(?:var\s+\w+|[\w<>?, ]+\s+\w+)\s*(=(?!>)|;)',
);

/// All Dart files under `lib/`, sorted by path.
List<File> _libFiles() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// All Dart files directly in `lib/src/`, sorted by path.
List<File> _srcFiles() {
  final files = Directory('lib/src')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

String _name(File f) => f.uri.pathSegments.last;

/// Source lines with whole-line comments removed.
List<String> _codeLines(File f) => f
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .toList();

/// `(kind, uri, rest)` for every import and export directive in [f].
List<(String, String, String)> _directives(File f) => [
      for (final line in _codeLines(f))
        if (_directive.firstMatch(line) case final m?)
          (m.group(1)!, m.group(2)!, m.group(3)!.trim()),
    ];

/// Names of the public type declarations at the top level of [f].
List<(String, String)> _publicTypes(File f) => [
      for (final line in _codeLines(f))
        if (_typeDeclaration.firstMatch(line) case final m?)
          if (!m.group(2)!.startsWith('_')) (m.group(1)!, m.group(2)!),
    ];

/// `MorseFormatException` becomes `morse_format_exception`.
String _snakeCase(String name) => name
    .replaceAllMapped(
      RegExp(r'(?<=[a-z0-9])([A-Z])|(?<=[A-Z])([A-Z])(?=[a-z])'),
      (m) => '_${m[0]}',
    )
    .toLowerCase();

/// Package names listed under the top-level [section] of `pubspec.yaml`.
List<String> _pubspecSection(String section) {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final start = lines.indexWhere((l) => l.startsWith('$section:'));
  if (start < 0) return const [];
  final inline = lines[start].substring(section.length + 1).split('#').first;
  final names = <String>[];
  final inlineValue = inline.trim();
  if (inlineValue.isNotEmpty && inlineValue != '{}') {
    // Inline flow map such as `{a: ^1.0.0}`.
    names.addAll(inlineValue
        .replaceAll(RegExp(r'[{}]'), '')
        .split(',')
        .map((e) => e.split(':').first.trim())
        .where((e) => e.isNotEmpty));
  }
  for (final line in lines.skip(start + 1)) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.startsWith(' ')) break; // Next top-level key.
    final m = RegExp(r'^  (\S[^:]*):').firstMatch(line);
    if (m != null) names.add(m.group(1)!.trim());
  }
  return names;
}

/// The four public classes of the package. REQ-PURE-6.
const _publicApi = {
  'CodeTable',
  'MorseEncoder',
  'MorseDecoder',
  'MorseFormatException',
};

/// `dart:core` types the example may name besides the public API.
const _coreTypes = {'String', 'int', 'bool', 'Object', 'FormatException'};

/// The identifier left by the `dart create` scaffold. It is built from two
/// parts so this file never contains it and the scan cannot match itself.
/// REQ-PURE-6.
const _scaffoldIdentifier = 'Awe' 'some';

/// Scaffold files that must not exist. REQ-PURE-6.
const _scaffoldFiles = {'morse_core_base.dart', 'morse_core_test.dart'};

/// A requirement ID in the form `REQ-<AREA>-<n>`. REQ-PURE-7.
final _requirementId = RegExp(r'REQ-[A-Z]+-\d+');

/// An UpperCamelCase identifier such as a class name.
final _typeName = RegExp(r'\b[A-Z][a-z0-9]\w*\b');

/// A CamelCase identifier with at least two humps, such as `CodeTable`.
final _camelCaseName = RegExp(r'\b[A-Z][a-z0-9]+[A-Z]\w*\b');

/// Files in this package (outside `.dart_tool/` and `build/`) whose text is
/// scanned for scaffold leftovers.
List<File> _packageFiles() => Directory('.')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) {
      final segments = f.uri.pathSegments;
      return !segments.contains('.dart_tool') && !segments.contains('build');
    })
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// [line] with string literals emptied and a trailing `//` comment removed,
/// so braces and identifiers outside strings can be read.
String _stripCode(String line) => line
    .replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''")
    .replaceAll(RegExp(r'"(?:[^"\\]|\\.)*"'), '""')
    .replaceFirst(RegExp(r'//.*$'), '');

/// The name declared on a member or top-level declaration line [code]
/// (already stripped), or null if the line declares nothing.
String? _declaredName(String code) {
  final accessor =
      RegExp(r'\b(?:get|set)\s+([A-Za-z_$][\w$]*)').firstMatch(code);
  if (accessor != null) return accessor.group(1);
  if (RegExp(r'\boperator\b').hasMatch(code)) return 'operator';
  final paren = code.indexOf('(');
  final assign = RegExp(r'=(?![=>])|;').firstMatch(code)?.start ?? -1;
  if (paren >= 0 && (assign < 0 || paren < assign)) {
    // Method, function or constructor (possibly named, possibly generic).
    return RegExp(r'([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?)\s*'
            r'(?:<[^()]*>)?\s*$')
        .firstMatch(code.substring(0, paren))
        ?.group(1);
  }
  if (assign >= 0) {
    // Field or variable.
    return RegExp(r'([A-Za-z_$][\w$]*)\s*$')
        .firstMatch(code.substring(0, assign))
        ?.group(1);
  }
  return null;
}

/// The consecutive `///` lines directly above line [index], skipping
/// annotations such as `@override`.
List<String> _docAbove(List<String> lines, int index) {
  var j = index - 1;
  while (j >= 0 && lines[j].trim().startsWith('@')) {
    j--;
  }
  final doc = <String>[];
  while (j >= 0 && lines[j].trim().startsWith('///')) {
    doc.insert(0, lines[j].trim());
    j--;
  }
  return doc;
}

/// A public declaration and the `///` comment above it. REQ-PURE-7.
typedef _Declaration = ({int line, String name, List<String> doc});

/// Every public declaration in [lines]: the library directive, top-level
/// public types, functions and variables, and the constructors, methods,
/// getters, setters and fields declared directly in the body of a public
/// type. Members of private types are not public API and are skipped.
/// REQ-PURE-7.
List<_Declaration> _publicDeclarations(List<String> lines) {
  final found = <_Declaration>[];
  var depth = 0;
  // Brace depths that are the body of a public type.
  final publicBodies = <int>{};
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.startsWith('//')) continue;
    final code = _stripCode(raw);
    if (!trimmed.startsWith('@') && !trimmed.startsWith('}')) {
      String? name;
      if (depth == 0 && !raw.startsWith(' ')) {
        if (RegExp(r'^library\b').hasMatch(trimmed)) {
          name = 'library';
        } else if (RegExp(r'^(import|export|part)\b').hasMatch(trimmed)) {
          name = null;
        } else if (_typeDeclaration.firstMatch(raw) case final m?) {
          name = m.group(2)!;
          if (!name.startsWith('_')) publicBodies.add(depth + 1);
        } else {
          name = _declaredName(code);
        }
      } else if (publicBodies.contains(depth) &&
          RegExp(r'^  \S').hasMatch(raw)) {
        name = _declaredName(code);
      }
      if (name != null && !name.split('.').last.startsWith('_')) {
        found.add((line: i + 1, name: name, doc: _docAbove(lines, i)));
      }
    }
    final closes = '}'.allMatches(code).length;
    depth += '{'.allMatches(code).length - closes;
    if (closes > 0) publicBodies.removeWhere((d) => d > depth);
  }
  return found;
}

/// The declarations in [declarations] whose doc comment is missing or cites
/// no requirement ID. REQ-PURE-7.
List<_Declaration> _undocumented(List<_Declaration> declarations) => [
      for (final d in declarations)
        if (!_requirementId.hasMatch(d.doc.join('\n'))) d,
    ];

/// Requirement IDs that REQ-TEST-1 requires a property-based test for.
const _test1Ids = [
  'REQ-CODE-4',
  'REQ-CODE-7',
  'REQ-ENC-10',
  'REQ-DEC-7',
  'REQ-FMT-2',
  'REQ-FMT-3',
  'REQ-FMT-4',
  'REQ-ERR-10',
];

/// Requirement IDs that REQ-TEST-2 requires an example-based test for.
const _test2Ids = [
  'REQ-CODE-1',
  'REQ-CODE-2',
  'REQ-CODE-3',
  'REQ-ENC-7',
  'REQ-ENC-8',
  'REQ-ENC-9',
  'REQ-DEC-4',
  'REQ-DEC-5',
  'REQ-DEC-6',
  'REQ-ERR-1',
  'REQ-ERR-2',
  'REQ-ERR-3',
  'REQ-ERR-4',
  'REQ-ERR-5',
  'REQ-ERR-6',
  'REQ-ERR-7',
  'REQ-ERR-8',
];

/// The fixture comparison test required by REQ-TEST-3.
const _test3Ids = ['REQ-TEST-3'];

/// The start of a `test(` or `property(` call followed by its first string
/// literal. Built so this file's own source never matches it by accident.
final _testCall = RegExp(r'''\b(test|property)\(\s*['"]''');

/// A Dart string literal (single or double quoted, no triple quotes) at the
/// start of the remaining text, after optional whitespace.
final _adjacentLiteral = RegExp(r'''^\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''');

/// The run of requirement IDs at the start of a test name. REQ-TEST-4.
final _leadingIds = RegExp(r'^(?:REQ-[A-Z]+-\d+ )+');

/// The names of every `test(` and `property(` call in [source], with
/// adjacent string literals joined. Whole-line comments are ignored.
/// REQ-TEST-4.
List<String> _testNames(String source) {
  final code = source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
  final names = <String>[];
  for (final m in _testCall.allMatches(code)) {
    // Start at the opening quote of the first literal.
    var rest = code.substring(m.end - 1);
    final buffer = StringBuffer();
    while (true) {
      final lit = _adjacentLiteral.firstMatch(rest);
      if (lit == null) break;
      buffer.write(lit.group(1) ?? lit.group(2));
      rest = rest.substring(lit.end);
    }
    names.add(buffer.toString());
  }
  return names;
}

/// The requirement IDs at the start of [name]. REQ-TEST-4.
List<String> _idsAtStart(String name) {
  final run = _leadingIds.firstMatch(name)?.group(0) ?? '';
  return _requirementId.allMatches(run).map((m) => m[0]!).toList();
}

/// The test files directly in `test/` (not `test/support/`).
List<File> _testFiles() => Directory('test')
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('_test.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// Every Dart file under `test/`, including `test/support/`.
List<File> _allTestDartFiles() => Directory('test')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// Every test name in `test/*.dart`, keyed by file path. REQ-TEST-4.
Map<String, List<String>> _allTestNames() => {
      for (final f in _testFiles()) f.path: _testNames(f.readAsStringSync()),
    };

/// Text that would skip a test: the `skip` named argument of `package:test`
/// or a `Skip` annotation. Built from parts so this file never contains the
/// literals it searches for. REQ-TEST-5.
final _skipMarker = RegExp('\\b${'sk' 'ip'}\\s*:|@${'Sk' 'ip'}\\b');

void main() {
  setUpAll(() {
    // Guard REQ-TEST-7: the tests must run from the package root.
    final pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue,
        reason: 'run `dart test` from packages/morse_core');
    expect(pubspec.readAsStringSync(), contains('name: morse_core'));
  });

  group('dependencies and imports', () {
    test('REQ-PURE-1 pubspec.yaml lists no runtime dependencies', () {
      expect(_pubspecSection('dependencies'), isEmpty);
    });

    test('REQ-PURE-1 dev_dependencies are test and lint tooling only', () {
      final dev = _pubspecSection('dev_dependencies');
      expect(dev, isNotEmpty);
      expect(dev.toSet().difference(_allowedDevDependencies), isEmpty);
    });

    test(
        'REQ-PURE-1 REQ-TEST-7 lib/ imports only allowed dart: libraries '
        'or relative paths', () {
      final files = _libFiles();
      expect(files, isNotEmpty);
      for (final file in files) {
        for (final (kind, uri, _) in _directives(file)) {
          final where = '${file.path}: $kind $uri';
          for (final prefix in _forbiddenImportPrefixes) {
            expect(uri.startsWith(prefix), isFalse,
                reason: '$where is forbidden');
          }
          if (uri.startsWith('dart:')) {
            expect(_allowedDartLibraries, contains(uri),
                reason: '$where is not an allowed dart: library');
          } else {
            expect(uri.contains(':'), isFalse,
                reason: '$where is not a relative path');
          }
        }
      }
    });

    test('REQ-PURE-1 no lib/ file imports kiri_check, test or lints', () {
      for (final file in _libFiles()) {
        for (final (_, uri, _) in _directives(file)) {
          expect(uri, isNot(matches(RegExp(r'^package:(kiri_check|test|lints)/'))),
              reason: '${file.path} imports $uri');
        }
      }
    });
  });

  group('no I/O, clock, randomness or mutable globals', () {
    test('REQ-PURE-3 no lib/ file imports an I/O library', () {
      for (final file in _libFiles()) {
        for (final (_, uri, _) in _directives(file)) {
          expect(
              uri,
              isNot(anyOf('dart:io', 'dart:html', 'dart:ffi', 'dart:isolate',
                  startsWith('package:'))),
              reason: '${file.path} imports $uri');
        }
      }
    });

    test('REQ-PURE-3 no lib/ file uses clock, random, file, network or '
        'environment APIs', () {
      for (final file in _libFiles()) {
        final lines = _codeLines(file);
        for (var i = 0; i < lines.length; i++) {
          expect(_impureIdentifier.hasMatch(lines[i]), isFalse,
              reason: '${file.path} line ${i + 1}: ${lines[i].trim()}');
        }
      }
    });

    test('REQ-PURE-3 every top-level and static variable is final or const',
        () {
      for (final file in _libFiles()) {
        final lines = _codeLines(file);
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final where = '${file.path} line ${i + 1}: ${line.trim()}';
          expect(_mutableTopLevel.hasMatch(line), isFalse, reason: where);
          expect(_mutableStatic.hasMatch(line), isFalse, reason: where);
        }
      }
    });

    test('REQ-PURE-3 the variable checks catch mutable declarations', () {
      // Self-check of the patterns above, so a broken regex cannot pass
      // silently.
      expect(_mutableTopLevel.hasMatch('var counter = 0;'), isTrue);
      expect(_mutableTopLevel.hasMatch('int counter = 0;'), isTrue);
      expect(_mutableTopLevel.hasMatch('Map<String, int>? cache;'), isTrue);
      expect(_mutableTopLevel.hasMatch('final int counter = 0;'), isFalse);
      expect(_mutableTopLevel.hasMatch('String f(int x) => "";'), isFalse);
      expect(_mutableStatic.hasMatch('  static int counter = 0;'), isTrue);
      expect(_mutableStatic.hasMatch('  static var cache;'), isTrue);
      expect(_mutableStatic.hasMatch('  static const int n = 1;'), isFalse);
      expect(_mutableStatic.hasMatch('  static final m = {};'), isFalse);
      expect(_mutableStatic.hasMatch('  static String f(String s) {'), isFalse);
      expect(_mutableStatic.hasMatch('  static int get n => 1;'), isFalse);
    });

    test('REQ-PURE-3 REQ-CODE-10 mutating codes and characters throws and '
        'leaves them unchanged', () {
      const table = CodeTable();
      for (final map in [table.codes, table.characters]) {
        final before = Map.of(map);
        final key = map.keys.first;
        expect(() => map['#'] = '#', throwsUnsupportedError);
        expect(() => map[key] = 'x', throwsUnsupportedError);
        expect(() => map.remove(key), throwsUnsupportedError);
        expect(() => map.clear(), throwsUnsupportedError);
        expect(() => map.addAll({'#': '#'}), throwsUnsupportedError);
        expect(map, hasLength(43));
        expect(map, equals(before));
      }
    });
  });

  group('file structure and exports', () {
    test('REQ-PURE-4 each lib/src/ file declares exactly one public class '
        'named after the file', () {
      final files = _srcFiles();
      expect(files, isNotEmpty);
      for (final file in files) {
        final types = _publicTypes(file);
        expect(types, hasLength(1),
            reason: '${file.path} declares public types $types');
        final (kind, name) = types.single;
        expect(kind, 'class', reason: '${file.path}: $name is a $kind');
        expect('${_snakeCase(name)}.dart', _name(file),
            reason: '${file.path} declares $name');
      }
    });

    test('REQ-PURE-4 snake_case conversion matches the naming rule', () {
      expect(_snakeCase('CodeTable'), 'code_table');
      expect(_snakeCase('MorseFormatException'), 'morse_format_exception');
      expect(_snakeCase('MorseDecoder'), 'morse_decoder');
    });

    test('REQ-PURE-5 lib/morse_core.dart exports every public class in '
        'lib/src/', () {
      final exports = {
        for (final (kind, uri, rest) in _directives(File('lib/morse_core.dart')))
          if (kind == 'export') uri: rest,
      };
      for (final file in _srcFiles()) {
        final uri = 'src/${_name(file)}';
        expect(exports.keys, contains(uri), reason: '$uri is not exported');
        final combinators = exports[uri]!;
        for (final (_, name) in _publicTypes(file)) {
          expect(combinators, isNot(contains('hide')),
              reason: '$uri hides names');
          if (combinators.contains('show')) {
            expect(combinators, contains(name),
                reason: '$uri does not show $name');
          }
        }
      }
    });

    test('REQ-PURE-5 the single public import gives the whole API', () {
      // This file imports only package:morse_core/morse_core.dart from the
      // package, never a file under lib/src/.
      const table = CodeTable();
      const encoder = MorseEncoder();
      const decoder = MorseDecoder();
      expect(table.codeFor('S'), '...');
      final morse = encoder.encode('sos');
      expect(morse, '... --- ...');
      expect(decoder.decode(morse), 'SOS');
      expect(() => encoder.encode('!'), throwsA(isA<MorseFormatException>()));
      final error = MorseFormatException(
          requirementId: 'REQ-ERR-1', offending: '!', position: 0);
      expect(error, isA<FormatException>());
    });

    test('REQ-PURE-5 this test imports no file under lib/src/', () {
      final self = File('test/purity_test.dart');
      for (final (_, uri, _) in _directives(self)) {
        expect(uri, isNot(contains('src/')), reason: 'imports $uri');
        if (uri.startsWith('package:morse_core/')) {
          expect(uri, 'package:morse_core/morse_core.dart');
        }
      }
    });
  });

  group('scaffold removal', () {
    test('REQ-PURE-6 no file in the package contains the scaffold '
        'identifier', () {
      final pattern = RegExp('\\b$_scaffoldIdentifier\\b');
      final files = _packageFiles()
          .where((f) => RegExp(r'\.(dart|yaml|md)$').hasMatch(f.path))
          .toList();
      expect(files.map(_name), containsAll(['pubspec.yaml', 'code_table.dart']));
      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          expect(pattern.hasMatch(lines[i]), isFalse,
              reason: '${file.path} line ${i + 1}');
        }
      }
    });

    test('REQ-PURE-6 the scaffold files are gone', () {
      final names = _packageFiles().map(_name).toSet();
      expect(names.intersection(_scaffoldFiles), isEmpty);
    });

    test('REQ-PURE-6 the pubspec.yaml description describes only the public '
        'API', () {
      final line = File('pubspec.yaml')
          .readAsLinesSync()
          .singleWhere((l) => l.startsWith('description:'));
      final description = line.substring('description:'.length).trim();
      final lower = description.toLowerCase();
      for (final part in ['code table', 'encoder', 'decoder', 'error']) {
        expect(lower, contains(part), reason: 'description omits $part');
      }
      final names = _camelCaseName.allMatches(description).map((m) => m[0]!);
      expect(names.toSet().difference(_publicApi), isEmpty);
    });

    test('REQ-PURE-6 example/ imports only the public library and names only '
        'the four public classes', () {
      final files = Directory('example')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);
      final used = <String>{};
      for (final file in files) {
        for (final (_, uri, _) in _directives(file)) {
          if (uri.startsWith('dart:')) continue;
          expect(uri, 'package:morse_core/morse_core.dart',
              reason: '${file.path} imports $uri');
        }
        for (final line in _codeLines(file)) {
          used.addAll(
              _typeName.allMatches(_stripCode(line)).map((m) => m[0]!));
        }
      }
      expect(used.difference({..._publicApi, ..._coreTypes}), isEmpty);
      expect(used, containsAll(_publicApi));
    });
  });

  group('doc comments', () {
    test('REQ-PURE-7 the declaration scanner finds missing and ID-less doc '
        'comments', () {
      // Self-check of the scanner, so a broken pattern cannot pass silently.
      const source = '''
/// Library doc. REQ-CODE-1.
library;

/// Doc. REQ-CODE-1.
final class Good {
  /// REQ-CODE-1.
  const Good();

  int missing() => 1;

  /// No requirement cited.
  final int noId = 0;

  int _private() => 0;

  /// REQ-CODE-1.
  @override
  String toString() => '{';

  /// REQ-CODE-1.
  int get size => 0;

  set size(int v) {
    if (v > 0) {
      v = 0;
    }
  }
}

String topLevel() => '';

String _hiddenTopLevel() => '';

final class _Hidden {
  int notChecked() => 0;
}
''';
      final declarations = _publicDeclarations(source.split('\n'));
      expect(declarations.map((d) => d.name), [
        'library',
        'Good',
        'Good',
        'missing',
        'noId',
        'toString',
        'size',
        'size',
        'topLevel',
      ]);
      expect(_undocumented(declarations).map((d) => d.name),
          ['missing', 'noId', 'size', 'topLevel']);
    });

    test('REQ-PURE-7 every public declaration in lib/ has a /// comment '
        'citing a requirement ID', () {
      final all = <String>{};
      for (final file in _libFiles()) {
        final declarations = _publicDeclarations(file.readAsLinesSync());
        all.addAll(declarations.map((d) => d.name));
        for (final d in _undocumented(declarations)) {
          fail('${file.path} line ${d.line}: ${d.name} has no /// comment '
              'citing REQ-<AREA>-<n>');
        }
      }
      // The scanner must see the known public API, or it is broken.
      expect(
          all,
          containsAll([
            'library',
            ..._publicApi,
            'codes',
            'characters',
            'codeFor',
            'characterFor',
            'encode',
            'decode',
            'requirementId',
            'offending',
            'position',
            'toString',
          ]));
    });

    test('REQ-PURE-7 every requirement ID cited in a lib/ doc comment exists',
        () {
      var cited = 0;
      for (final file in _libFiles()) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].trim().startsWith('///')) continue;
          for (final m in _requirementId.allMatches(lines[i])) {
            cited++;
            expect(requirementIds, contains(m[0]),
                reason: '${file.path} line ${i + 1} cites ${m[0]}');
          }
        }
      }
      expect(cited, greaterThan(0));
    });
  });

  group('test names and skips', () {
    test('REQ-TEST-4 the test-name scanner joins literals and reads leading '
        'IDs', () {
      // Self-check of the scanner, so a broken pattern cannot pass silently.
      // The calls are built from parts so this file's scan does not see them.
      const t = 'te' 'st';
      const p = 'prop' 'erty';
      final source = [
        "$t('REQ-CODE-1 one', () {});",
        '// $t(\'commented out\', () {});',
        '$p(',
        "    'REQ-ENC-1 REQ-ENC-2 joined '",
        "    'name', () {});",
        '$t("REQ-DEC-4 double quoted", () {});',
        "$t('no id here', () {});",
      ].join('\n');
      final names = _testNames(source);
      expect(names, [
        'REQ-CODE-1 one',
        'REQ-ENC-1 REQ-ENC-2 joined name',
        'REQ-DEC-4 double quoted',
        'no id here',
      ]);
      expect(_idsAtStart(names[1]), ['REQ-ENC-1', 'REQ-ENC-2']);
      expect(_idsAtStart('REQ-ERR-8 cites REQ-ERR-1 later'), ['REQ-ERR-8']);
      expect(_idsAtStart(names[3]), isEmpty);
    });

    test('REQ-TEST-4 every test name begins with a known requirement ID', () {
      final byFile = _allTestNames();
      expect(byFile.keys.map((p) => File(p).uri.pathSegments.last),
          containsAll(['code_table_test.dart', 'properties_test.dart']));
      var count = 0;
      byFile.forEach((path, names) {
        expect(names, isNotEmpty, reason: '$path has no test names');
        for (final name in names) {
          count++;
          final ids = _idsAtStart(name);
          expect(ids, isNotEmpty,
              reason: '$path: "$name" does not begin with REQ-<AREA>-<n>');
          for (final id in ids) {
            expect(requirementIds, contains(id),
                reason: '$path: "$name" cites unknown $id');
          }
        }
      });
      // The design has 13 properties and many unit tests.
      expect(count, greaterThan(50));
    });

    test('REQ-TEST-4 REQ-TEST-1 REQ-TEST-2 REQ-TEST-3 every listed ID begins '
        'at least one test name', () {
      final leading = {
        for (final names in _allTestNames().values)
          for (final name in names) ..._idsAtStart(name),
      };
      for (final id in [..._test1Ids, ..._test2Ids, ..._test3Ids]) {
        expect(leading, contains(id), reason: 'no test name begins with $id');
      }
    });

    test('REQ-TEST-5 no test file skips a test', () {
      // Self-check of the pattern.
      expect(_skipMarker.hasMatch('${'sk' 'ip'}: true'), isTrue);
      expect(_skipMarker.hasMatch('@${'Sk' 'ip'}()'), isTrue);
      expect(_skipMarker.hasMatch('lines.${'sk' 'ip'}(1)'), isFalse);
      final files = _allTestDartFiles();
      expect(files, isNotEmpty);
      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          expect(_skipMarker.hasMatch(lines[i]), isFalse,
              reason: '${file.path} line ${i + 1}: ${lines[i].trim()}');
        }
      }
    });

    test('REQ-PURE-9 each of REQ-PURE-1 to REQ-PURE-7 appears in a test name',
        () {
      final cited = {
        for (final names in _allTestNames().values)
          for (final name in names)
            ..._requirementId.allMatches(name).map((m) => m[0]!),
      };
      for (var n = 1; n <= 7; n++) {
        expect(cited, contains('REQ-PURE-$n'),
            reason: 'no test name cites REQ-PURE-$n');
      }
    });
  });
}
