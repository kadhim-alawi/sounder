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
import 'support/timing_requirement_ids.dart';

/// Every known requirement ID: the morse-core IDs and the adaptive-timing
/// IDs. REQ-PURE-7, REQ-TEST-4, REQ-ENGINE-6, REQ-PBT-3.
final _knownIds = requirementIds.union(timingRequirementIds);

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

final _directive = RegExp(
  r'''^\s*(import|export)\s+['"]([^'"]+)['"]([^;]*);''',
);

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
  final files =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// All Dart files directly in `lib/src/`, sorted by path.
List<File> _srcFiles() {
  final files =
      Directory('lib/src')
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
List<(String, String, String)> _directives(File f) =>
    _directivesIn(_codeLines(f));

/// `(kind, uri, rest)` for every import and export directive in [lines].
/// Whole-line comments are skipped.
List<(String, String, String)> _directivesIn(List<String> lines) => [
  for (final line in lines)
    if (!line.trimLeft().startsWith('//'))
      if (_directive.firstMatch(line) case final m?)
        (m.group(1)!, m.group(2)!, m.group(3)!.trim()),
];

/// Why the import and export directives in [lines], the source of the
/// `lib/` file [fileName], break the REQ-PURE-1 import rules, or an empty
/// list if they do not: no forbidden prefix, `dart:` libraries only from
/// the allowed set, and every other URI a relative path. REQ-ENGINE-1,
/// REQ-PURE-1.
/// At most one problem is reported per directive.
List<String> _importProblems(String fileName, List<String> lines) => [
  for (final (kind, uri, _) in _directivesIn(lines))
    if (_forbiddenImportPrefixes.any(uri.startsWith))
      '$fileName: $kind $uri is forbidden'
    else if (uri.startsWith('dart:') && !_allowedDartLibraries.contains(uri))
      '$fileName: $kind $uri is not an allowed dart: library'
    else if (!uri.startsWith('dart:') && uri.contains(':'))
      '$fileName: $kind $uri is not a relative path',
];

/// `(kind, name)` of the public type declarations at the top level of
/// [lines]. Whole-line comments are skipped.
List<(String, String)> _publicTypesIn(List<String> lines) => [
  for (final line in lines)
    if (!line.trimLeft().startsWith('//'))
      if (_typeDeclaration.firstMatch(line) case final m?)
        if (!m.group(2)!.startsWith('_')) (m.group(1)!, m.group(2)!),
];

/// Names of the public type declarations at the top level of [f].
List<(String, String)> _publicTypesOf(File f) => _publicTypesIn(_codeLines(f));

/// Kinds of public type allowed in a `lib/src/` file. REQ-PURE-4 as amended
/// by Decision B15, REQ-ENGINE-3.
const _allowedTypeKinds = {'class', 'enum'};

/// Why a `lib/src/` file named [fileName] with source [lines] breaks the
/// one-public-type-per-file rule, or an empty list if it does not: it must
/// declare exactly one public class or enum, named so that its `snake_case`
/// form plus `.dart` is the file name. REQ-PURE-4, REQ-ENGINE-3.
List<String> _structureProblems(String fileName, List<String> lines) {
  final types = _publicTypesIn(lines);
  if (types.length != 1) {
    return ['$fileName declares ${types.length} public types $types'];
  }
  final (kind, name) = types.single;
  return [
    if (!_allowedTypeKinds.contains(kind))
      '$fileName: $name is a $kind, not a class or enum',
    if ('${_snakeCase(name)}.dart' != fileName)
      '$fileName declares $name, expected ${_snakeCase(name)}.dart',
  ];
}

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
    names.addAll(
      inlineValue
          .replaceAll(RegExp(r'[{}]'), '')
          .split(',')
          .map((e) => e.split(':').first.trim())
          .where((e) => e.isNotEmpty),
    );
  }
  for (final line in lines.skip(start + 1)) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.startsWith(' ')) break; // Next top-level key.
    final m = RegExp(r'^  (\S[^:]*):').firstMatch(line);
    if (m != null) names.add(m.group(1)!.trim());
  }
  return names;
}

/// The public types of the package: the four morse-core classes and the 19
/// adaptive-timing types. REQ-ENGINE-4, which replaces the public-API
/// sentence of REQ-PURE-6.
const _publicTypes = {
  'CodeTable',
  'MorseEncoder',
  'MorseDecoder',
  'MorseFormatException',
  'SwitchEventKind',
  'SwitchEvent',
  'Press',
  'TimingConfig',
  'Calibration',
  'Calibrator',
  'CalibrationResult',
  'CalibrationRejection',
  'RejectionReason',
  'Debouncer',
  'Classifier',
  'MorseSymbol',
  'GapClass',
  'BatchDecoder',
  'LiveDecoder',
  'DecodedItem',
  'DecodedItemKind',
  'TimingInputException',
  'TimingInputErrorKind',
};

/// The public classes and enums made visible by the export directives in
/// [librarySource]. [readExported] returns the source lines of an exported
/// URI, relative to `lib/`. `show` and `hide` combinators are applied.
/// REQ-ENGINE-4.
Set<String> _exportedPublicTypes(
  String librarySource,
  List<String> Function(String uri) readExported,
) {
  final names = <String>{};
  for (final line in librarySource.split('\n')) {
    if (line.trimLeft().startsWith('//')) continue;
    final m = _directive.firstMatch(line);
    if (m == null || m.group(1) != 'export') continue;
    final rest = m.group(3)!.trim();
    List<String> listed(String keyword) {
      final c = RegExp('\\b$keyword\\s+([\\w\\s,]+)').firstMatch(rest);
      if (c == null) return const [];
      return c
          .group(1)!
          .split(',')
          .map((s) => s.trim().split(RegExp(r'\s+')).first)
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final shown = listed('show');
    final hidden = listed('hide');
    for (final (kind, name) in _publicTypesIn(readExported(m.group(2)!))) {
      if (!_allowedTypeKinds.contains(kind)) continue;
      if (shown.isNotEmpty && !shown.contains(name)) continue;
      if (hidden.contains(name)) continue;
      names.add(name);
    }
  }
  return names;
}

/// The four morse-core public types. Every other entry of [_publicTypes] is
/// a Timing_Engine type. REQ-ENGINE-4.
const _morseCoreTypes = {
  'CodeTable',
  'MorseEncoder',
  'MorseDecoder',
  'MorseFormatException',
};

/// The Timing_Engine source files: the `lib/src/` file of each
/// adaptive-timing public type, named as in REQ-ENGINE-3, plus every Dart
/// file under `lib/src/internal/` (design Decision T5). The four morse-core
/// files are not Timing_Engine source. REQ-ENGINE-5.
List<File> _timingFiles() {
  final typeFiles = [
    for (final name in _publicTypes.difference(_morseCoreTypes))
      File('lib/src/${_snakeCase(name)}.dart'),
  ];
  final internal = Directory('lib/src/internal').existsSync()
      ? Directory('lib/src/internal')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
      : <File>[];
  return [...typeFiles, ...internal]..sort((a, b) => a.path.compareTo(b.path));
}

/// A call to `print` or `log` (including `developer.log`), or any use of
/// `stdout` or `stderr`, as whole words. `catalog(`, `backlog(` and
/// `printer` do not match. REQ-ENGINE-5.
final _outputUse = RegExp(r'\b(?:print|log)\s*\(|\b(?:stdout|stderr)\b');

/// Why the source [lines] of the Timing_Engine file [fileName] break
/// REQ-ENGINE-5, or an empty list if they do not. Directives are checked
/// for `dart:developer`, since the URI is a string literal. Every other
/// line is checked after whole-line comments (including `///` doc
/// comments) are dropped and string literals and trailing comments are
/// stripped, so prose in comments and messages cannot cause a false
/// failure. REQ-ENGINE-5, REQ-PBT-7.
List<String> _outputProblems(String fileName, List<String> lines) => [
  for (final (kind, uri, _) in _directivesIn(lines))
    if (uri == 'dart:developer' || uri.startsWith('dart:developer/'))
      '$fileName: $kind $uri is forbidden',
  for (var i = 0; i < lines.length; i++)
    if (!lines[i].trimLeft().startsWith('//'))
      if (_outputUse.firstMatch(_stripCode(lines[i])) case final m?)
        '$fileName line ${i + 1}: ${m[0]} writes output',
];

/// Why the source [lines] of the Timing_Engine file [fileName] break
/// REQ-ENGINE-2, or an empty list if they do not: no clock, randomness,
/// file, network, process or environment API (the [_impureIdentifier]
/// scan), and no top-level or static variable that is not `final` or
/// `const` (the [_mutableTopLevel] and [_mutableStatic] scans). Whole-line
/// comments are dropped and string literals and trailing comments are
/// stripped, so prose cannot cause a false failure. Private instance fields
/// inside a class body are instance state, which REQ-ENGINE-2 allows, and
/// are not flagged. At most one problem is reported per scan per line.
/// REQ-ENGINE-2, REQ-PBT-7.
List<String> _impurityProblems(String fileName, List<String> lines) => [
  for (var i = 0; i < lines.length; i++)
    if (!lines[i].trimLeft().startsWith('//')) ...[
      if (_impureIdentifier.firstMatch(_stripCode(lines[i])) case final m?)
        '$fileName line ${i + 1}: ${m[0]} reads the clock, randomness, '
            'I/O or environment',
      if (_mutableTopLevel.hasMatch(_stripCode(lines[i])))
        '$fileName line ${i + 1}: mutable top-level variable',
      if (_mutableStatic.hasMatch(_stripCode(lines[i])))
        '$fileName line ${i + 1}: mutable static field',
    ],
];

/// `dart:core` types the example may name besides the public API.
const _coreTypes = {'String', 'int', 'bool', 'Object', 'FormatException'};

/// The identifier left by the `dart create` scaffold. It is built from two
/// parts so this file never contains it and the scan cannot match itself.
/// REQ-PURE-6.
const _scaffoldIdentifier =
    'Awe'
    'some';

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
List<File> _packageFiles() =>
    Directory('.').listSync(recursive: true).whereType<File>().where((f) {
      final segments = f.uri.pathSegments;
      return !segments.contains('.dart_tool') && !segments.contains('build');
    }).toList()..sort((a, b) => a.path.compareTo(b.path));

/// [line] with string literals emptied and a trailing `//` comment removed,
/// so braces and identifiers outside strings can be read.
String _stripCode(String line) => line
    .replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''")
    .replaceAll(RegExp(r'"(?:[^"\\]|\\.)*"'), '""')
    .replaceFirst(RegExp(r'//.*$'), '');

/// The name declared on a member or top-level declaration line [code]
/// (already stripped), or null if the line declares nothing.
String? _declaredName(String code) {
  final accessor = RegExp(r'\b(?:get|set)\s+([A-Za-z_$][\w$]*)')
      .firstMatch(code);
  if (accessor != null) return accessor.group(1);
  if (RegExp(r'\boperator\b').hasMatch(code)) return 'operator';
  final paren = code.indexOf('(');
  final assign = RegExp(r'=(?![=>])|;').firstMatch(code)?.start ?? -1;
  if (paren >= 0 && (assign < 0 || paren < assign)) {
    // Method, function or constructor (possibly named, possibly generic).
    return RegExp(
      r'([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?)\s*'
      r'(?:<[^()]*>)?\s*$',
    ).firstMatch(code.substring(0, paren))?.group(1);
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

/// The identifier at the start of [code], or null.
final _leadingIdentifier = RegExp(r'^\s*([A-Za-z_$][\w$]*)');

/// The enum value names in [values], the text of an enum value list (already
/// stripped) up to its `;` or `}`, such as `a, b('x')`. REQ-ENGINE-6.
List<String> _enumValueNames(String values) => [
  for (final part in values.split(','))
    ?_leadingIdentifier.firstMatch(part)?.group(1),
];

/// Every public declaration in [lines]: the library directive, top-level
/// public types, functions and variables, the values of a public enum, and
/// the constructors, methods, getters, setters and fields declared directly
/// in the body of a public type. Members of private types are not public API
/// and are skipped. An enum value written on the same line as its enum's
/// opening brace has no room for a doc comment of its own, so it is reported
/// with an empty doc. REQ-PURE-7, REQ-ENGINE-6.
List<_Declaration> _publicDeclarations(List<String> lines) {
  final found = <_Declaration>[];
  var depth = 0;
  // Brace depths that are the body of a public type.
  final publicBodies = <int>{};
  // Brace depth of the public enum body whose value list is being read, or
  // null when no value list is open.
  int? enumValuesDepth;
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.startsWith('//')) continue;
    final code = _stripCode(raw);
    final lineDepth = depth;
    if (!trimmed.startsWith('@') && !trimmed.startsWith('}')) {
      String? name;
      var sameLineValues = const <String>[];
      if (depth == 0 && !raw.startsWith(' ')) {
        if (RegExp(r'^library\b').hasMatch(trimmed)) {
          name = 'library';
        } else if (RegExp(r'^(import|export|part)\b').hasMatch(trimmed)) {
          name = null;
        } else if (_typeDeclaration.firstMatch(raw) case final m?) {
          name = m.group(2)!;
          if (!name.startsWith('_')) {
            publicBodies.add(depth + 1);
            final brace = code.indexOf('{');
            if (m.group(1) == 'enum' && brace >= 0) {
              final rest = code.substring(brace + 1);
              final end = rest.indexOf(RegExp(r'[;}]'));
              sameLineValues = _enumValueNames(
                end < 0 ? rest : rest.substring(0, end),
              );
              if (!rest.contains(';')) enumValuesDepth = depth + 1;
            }
          }
        } else {
          name = _declaredName(code);
        }
      } else if (enumValuesDepth == depth && RegExp(r'^  \S').hasMatch(raw)) {
        // An enum value, with or without constructor arguments.
        name = _leadingIdentifier.firstMatch(code)?.group(1);
      } else if (publicBodies.contains(depth) &&
          RegExp(r'^  \S').hasMatch(raw)) {
        name = _declaredName(code);
      }
      if (name != null && !name.split('.').last.startsWith('_')) {
        found.add((line: i + 1, name: name, doc: _docAbove(lines, i)));
      }
      for (final value in sameLineValues) {
        found.add((line: i + 1, name: value, doc: const []));
      }
    }
    // A `;` at the enum body's own depth ends its value list.
    if (enumValuesDepth == lineDepth && lineDepth > 0 && code.contains(';')) {
      enumValuesDepth = null;
    }
    final closes = '}'.allMatches(code).length;
    depth += '{'.allMatches(code).length - closes;
    if (closes > 0) {
      publicBodies.removeWhere((d) => d > depth);
      if (enumValuesDepth != null && enumValuesDepth > depth) {
        enumValuesDepth = null;
      }
    }
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

/// Requirement IDs that REQ-PBT-1 requires a property-based test for.
const _pbt1Ids = [
  'REQ-DEBOUNCE-7',
  'REQ-DEBOUNCE-8',
  'REQ-DEBOUNCE-9',
  'REQ-CAL-15',
  'REQ-TIMING-2',
  'REQ-TIMING-7',
  'REQ-TIMING-8',
  'REQ-TIMING-10',
  'REQ-BATCH-8',
  'REQ-BATCH-9',
  'REQ-LIVE-11',
];

/// Requirement IDs that REQ-PBT-2 requires an example-based test for.
const _pbt2Ids = [
  'REQ-EVENT-3',
  'REQ-EVENT-4',
  'REQ-EVENT-5',
  'REQ-EVENT-6',
  'REQ-DEBOUNCE-1',
  'REQ-DEBOUNCE-3',
  'REQ-DEBOUNCE-10',
  'REQ-DEBOUNCE-11',
  'REQ-DEBOUNCE-12',
  'REQ-DEBOUNCE-13',
  'REQ-DEBOUNCE-14',
  'REQ-DEBOUNCE-20',
  'REQ-DEBOUNCE-21',
  'REQ-DEBOUNCE-22',
  'REQ-CAL-1',
  'REQ-CAL-3',
  'REQ-CAL-4',
  'REQ-CAL-8',
  'REQ-CAL-9',
  'REQ-CAL-10',
  'REQ-CAL-11',
  'REQ-CAL-12',
  'REQ-CAL-13',
  'REQ-CAL-14',
  'REQ-CAL-16',
  'REQ-CAL-20',
  'REQ-CAL-21',
  'REQ-CAL-30',
  'REQ-CAL-31',
  'REQ-TIMING-5',
  'REQ-TIMING-6',
  'REQ-TIMING-9',
  'REQ-TIMING-11',
  'REQ-BATCH-3',
  'REQ-BATCH-4',
  'REQ-BATCH-5',
  'REQ-BATCH-6',
  'REQ-BATCH-7',
  'REQ-BATCH-10',
  'REQ-BATCH-11',
  'REQ-BATCH-12',
  'REQ-LIVE-3',
  'REQ-LIVE-5',
  'REQ-LIVE-6',
  'REQ-LIVE-7',
  'REQ-LIVE-8',
  'REQ-LIVE-9',
  'REQ-LIVE-10',
  'REQ-LIVE-12',
  'REQ-LIVE-13',
  'REQ-LIVE-14',
];

/// Requirement IDs that REQ-PBT-6 requires boundary-value tests to cite.
const _pbt6Ids = ['REQ-DEBOUNCE-6', 'REQ-TIMING-3', 'REQ-TIMING-4'];

/// Requirement IDs that REQ-PBT-7 (a) requires tests to cite.
const _pbt7Ids = [
  'REQ-ENGINE-4',
  'REQ-ENGINE-1',
  'REQ-ENGINE-5',
  'REQ-DEBOUNCE-2',
];

/// REQ-ENGINE-1 to REQ-ENGINE-6, each of which REQ-ENGINE-8 requires a test
/// name to begin with.
final _engine8Ids = [for (var n = 1; n <= 6; n++) 'REQ-ENGINE-$n'];

/// Every Timing_Engine public type, reached as a `Type` through the single
/// public import. If any were not exported from `lib/morse_core.dart`, this
/// file would not compile. REQ-ENGINE-3.
const _timingTypeLiterals = <Type>[
  SwitchEventKind,
  SwitchEvent,
  Press,
  TimingConfig,
  Calibration,
  Calibrator,
  CalibrationResult,
  CalibrationRejection,
  RejectionReason,
  Debouncer,
  Classifier,
  MorseSymbol,
  GapClass,
  BatchDecoder,
  LiveDecoder,
  DecodedItem,
  DecodedItemKind,
  TimingInputException,
  TimingInputErrorKind,
];

/// Why the public declarations in [lines], the source of the Timing_Engine
/// file [fileName], break REQ-ENGINE-6, or an empty list: every public
/// declaration, enum values included, needs a `///` comment that cites at
/// least one ID from the morse-core or adaptive-timing requirement set.
/// REQ-ENGINE-6.
List<String> _timingDocProblems(String fileName, List<String> lines) => [
  for (final d in _publicDeclarations(lines))
    if (!_requirementId
        .allMatches(d.doc.join('\n'))
        .any((m) => _knownIds.contains(m[0])))
      '$fileName line ${d.line}: ${d.name} has no /// comment citing a '
          'known requirement ID',
];

/// The start of a `test(` or `property(` call followed by its first string
/// literal. Built so this file's own source never matches it by accident.
final _testCall = RegExp(r'''\b(test|property)\(\s*['"]''');

/// A Dart string literal (single or double quoted, no triple quotes) at the
/// start of the remaining text, after optional whitespace.
final _adjacentLiteral = RegExp(
  r'''^\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
);

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
List<File> _testFiles() =>
    Directory('test')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_test.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// Every Dart file under `test/`, including `test/support/`.
List<File> _allTestDartFiles() =>
    Directory('test')
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
final _skipMarker = RegExp(
  '\\b${'sk'
      'ip'}\\s*:|@${'Sk'
      'ip'}\\b',
);

/// The Timing_Engine files that REQ-DEBOUNCE-2 bans numeric literals of
/// 1,000 or more from: the Debouncer and Classifier named by REQ-PBT-7, and
/// the Calibrator and both decoders named by REQ-DEBOUNCE-2. REQ-DEBOUNCE-2.
const _noLargeLiteralFiles = [
  'debouncer.dart',
  'classifier.dart',
  'calibrator.dart',
  'batch_decoder.dart',
  'live_decoder.dart',
];

/// The one file allowed to hold the default literals. REQ-DEBOUNCE-2.
const _defaultsFile = 'timing_config.dart';

/// [source] with every comment (`//`, `///`, and `/* */`, nested and
/// multi-line) and every string literal (single, double, triple-quoted and
/// raw, interpolations included) replaced by spaces. Newlines are kept, so
/// line numbers still match the source. REQ-DEBOUNCE-2.
String _blankCommentsAndStrings(String source) {
  final out = StringBuffer();
  var i = 0;
  final n = source.length;
  void blank(int end) {
    for (var j = i; j < end && j < n; j++) {
      out.write(source[j] == '\n' ? '\n' : ' ');
    }
    i = end < n ? end : n;
  }

  bool isIdentChar(String c) => RegExp(r'[\w$]').hasMatch(c);
  while (i < n) {
    final c = source[i];
    final next = i + 1 < n ? source[i + 1] : '';
    if (c == '/' && next == '/') {
      final end = source.indexOf('\n', i);
      blank(end < 0 ? n : end);
    } else if (c == '/' && next == '*') {
      var depth = 0;
      var j = i;
      while (j < n) {
        if (source.startsWith('/*', j)) {
          depth++;
          j += 2;
        } else if (source.startsWith('*/', j)) {
          depth--;
          j += 2;
          if (depth == 0) break;
        } else {
          j++;
        }
      }
      blank(j);
    } else if (c == "'" ||
        c == '"' ||
        (c == 'r' &&
            (next == "'" || next == '"') &&
            (i == 0 || !isIdentChar(source[i - 1])))) {
      final raw = c == 'r';
      var j = raw ? i + 1 : i;
      final quote = source[j];
      final triple = source.startsWith(quote * 3, j);
      final close = triple ? quote * 3 : quote;
      j += close.length;
      while (j < n && !source.startsWith(close, j)) {
        if (!triple && source[j] == '\n') break; // Unterminated; stop here.
        j += (!raw && source[j] == r'\') ? 2 : 1;
      }
      blank(j + close.length);
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

/// A Dart numeric literal as a whole token: hex, or decimal with optional
/// digit separators, fraction and exponent. A digit inside an identifier
/// such as `unit1000` is not a token. REQ-DEBOUNCE-2.
final _numericLiteral = RegExp(
  r'(?<![\w$.])(?:0[xX][0-9a-fA-F_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?'
  r'|\.\d[\d_]*(?:[eE][+-]?\d+)?)(?![\w$])',
);

/// `(line, token, value)` for every numeric literal in [source] outside
/// comments and strings. REQ-DEBOUNCE-2.
List<(int, String, double)> _numericLiteralsIn(String source) {
  final code = _blankCommentsAndStrings(source);
  return [
    for (final m in _numericLiteral.allMatches(code))
      (
        '\n'.allMatches(code.substring(0, m.start)).length + 1,
        m[0]!,
        _literalValue(m[0]!),
      ),
  ];
}

/// The value of the numeric literal [token]. REQ-DEBOUNCE-2.
double _literalValue(String token) {
  final digits = token.replaceAll('_', '');
  if (digits.startsWith(RegExp('0[xX]'))) {
    return BigInt.parse(digits.substring(2), radix: 16).toDouble();
  }
  return double.parse(digits);
}

/// Whether [token] is a double literal: it has a fraction or an exponent.
bool _isDoubleLiteral(String token) =>
    !token.startsWith(RegExp('0[xX]')) && token.contains(RegExp('[.eE]'));

/// Whether [token] spells a default of Timing_Config: any literal whose value
/// is 30,000 (`30000`, `30_000`, `0x7530`, `3e4`, `30000.0`), or a double
/// literal whose value is 2.0 (`2.0`, `2e0`). The int `2` is not a default
/// spelling, because the threshold arithmetic uses the literal 2 (design
/// Decision T8). REQ-DEBOUNCE-2.
bool _isDefaultLiteral(String token, double value) =>
    value == 30000 || (value == 2 && _isDoubleLiteral(token));

/// Why the source of the file [fileName] breaks the REQ-DEBOUNCE-2 ban on
/// numeric literals of 1,000 or more, or an empty list. REQ-DEBOUNCE-2,
/// REQ-PBT-7.
List<String> _largeLiteralProblems(String fileName, String source) => [
  for (final (line, token, value) in _numericLiteralsIn(source))
    if (value >= 1000) '$fileName line $line: literal $token is 1,000 or more',
];

/// Why the source of the `lib/` file [fileName] breaks the REQ-DEBOUNCE-2
/// rule that the defaults appear only in `timing_config.dart`, or an empty
/// list. REQ-DEBOUNCE-2, REQ-PBT-7.
List<String> _defaultLiteralProblems(String fileName, String source) => [
  if (fileName != _defaultsFile)
    for (final (line, token, value) in _numericLiteralsIn(source))
      if (_isDefaultLiteral(token, value))
        '$fileName line $line: default literal $token outside $_defaultsFile',
];

void main() {
  setUpAll(() {
    // Guard REQ-TEST-7: the tests must run from the package root.
    final pubspec = File('pubspec.yaml');
    expect(
      pubspec.existsSync(),
      isTrue,
      reason: 'run `dart test` from packages/morse_core',
    );
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

    test('REQ-PURE-1 REQ-TEST-7 lib/ imports only allowed dart: libraries '
        'or relative paths', () {
      final files = _libFiles();
      expect(files, isNotEmpty);
      for (final file in files) {
        for (final (kind, uri, _) in _directives(file)) {
          final where = '${file.path}: $kind $uri';
          for (final prefix in _forbiddenImportPrefixes) {
            expect(
              uri.startsWith(prefix),
              isFalse,
              reason: '$where is forbidden',
            );
          }
          if (uri.startsWith('dart:')) {
            expect(
              _allowedDartLibraries,
              contains(uri),
              reason: '$where is not an allowed dart: library',
            );
          } else {
            expect(
              uri.contains(':'),
              isFalse,
              reason: '$where is not a relative path',
            );
          }
        }
      }
    });

    test('REQ-PURE-1 no lib/ file imports kiri_check, test or lints', () {
      for (final file in _libFiles()) {
        for (final (_, uri, _) in _directives(file)) {
          expect(
            uri,
            isNot(matches(RegExp(r'^package:(kiri_check|test|lints)/'))),
            reason: '${file.path} imports $uri',
          );
        }
      }
    });

    test('REQ-ENGINE-1 REQ-PURE-1 every Dart file under lib/, including '
        'lib/src/internal/, follows the import rules', () {
      final files = _libFiles();
      final internal = files
          .where((f) => f.uri.pathSegments.contains('internal'))
          .toList();
      // The scan must reach lib/src/internal/, or it passes vacuously.
      expect(internal, isNotEmpty, reason: 'no file under lib/src/internal/');
      expect(internal.map(_name), contains('event_rules.dart'));
      for (final file in files) {
        expect(
          _importProblems(file.path, _codeLines(file)),
          isEmpty,
          reason: file.path,
        );
      }
    });

    test('REQ-ENGINE-1 REQ-PURE-1 pubspec.yaml lists no dependencies', () {
      expect(_pubspecSection('dependencies'), isEmpty);
    });

    test('REQ-ENGINE-1 REQ-PBT-7 the import check catches a planted '
        'forbidden import and accepts a clean source', () {
      // Self-check on planted sources, so a broken check cannot pass
      // silently.
      List<String> check(String source) =>
          _importProblems('planted.dart', source.split('\n'));

      expect(check("import 'dart:io';"), hasLength(1));
      expect(check("import 'package:flutter/widgets.dart';"), hasLength(1));
      expect(
        check("import 'package:kiri_check/kiri_check.dart';"),
        hasLength(1),
      );
      expect(check("import 'dart:developer';"), hasLength(1));
      expect(check("export 'dart:html';"), isNotEmpty);
      expect(
        check(
          "import 'dart:math';\n"
          "import '../press.dart';\n"
          "import 'dart:ffi';",
        ),
        hasLength(1),
      );
      expect(
        check(
          "// import 'dart:io';\n"
          "import 'dart:collection';\n"
          "import 'dart:math' show max;\n"
          "import '../switch_event.dart';\n"
          "export 'src/press.dart';",
        ),
        isEmpty,
      );
    });
  });

  group('no I/O, clock, randomness or mutable globals', () {
    test('REQ-PURE-3 no lib/ file imports an I/O library', () {
      for (final file in _libFiles()) {
        for (final (_, uri, _) in _directives(file)) {
          expect(
            uri,
            isNot(
              anyOf(
                'dart:io',
                'dart:html',
                'dart:ffi',
                'dart:isolate',
                startsWith('package:'),
              ),
            ),
            reason: '${file.path} imports $uri',
          );
        }
      }
    });

    test('REQ-PURE-3 no lib/ file uses clock, random, file, network or '
        'environment APIs', () {
      for (final file in _libFiles()) {
        final lines = _codeLines(file);
        for (var i = 0; i < lines.length; i++) {
          expect(
            _impureIdentifier.hasMatch(lines[i]),
            isFalse,
            reason: '${file.path} line ${i + 1}: ${lines[i].trim()}',
          );
        }
      }
    });

    test(
      'REQ-PURE-3 every top-level and static variable is final or const',
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
      },
    );

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

    test('REQ-ENGINE-5 no Timing_Engine file, including lib/src/internal/, '
        'prints, logs or writes to stdout or stderr', () {
      final files = _timingFiles();
      // 19 type files plus at least event_rules.dart, or the scan is vacuous.
      expect(files.length, greaterThanOrEqualTo(20));
      expect(files.map(_name), contains('event_rules.dart'));
      for (final file in files) {
        expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
        expect(
          _outputProblems(file.path, file.readAsLinesSync()),
          isEmpty,
          reason: file.path,
        );
      }
    });

    test('REQ-ENGINE-5 REQ-PBT-7 the output check catches each planted '
        'violation and ignores near-misses', () {
      // Self-check on planted sources, so a broken check cannot pass
      // silently.
      List<String> check(String source) =>
          _outputProblems('planted.dart', source.split('\n'));

      expect(check("  print('x');"), hasLength(1));
      expect(check("import 'dart:developer';"), hasLength(1));
      expect(check("import 'dart:developer' as developer;"), hasLength(1));
      expect(check("  log('x');"), hasLength(1));
      expect(check("  developer.log('x');"), hasLength(1));
      expect(check("  stdout.write('x');"), hasLength(1));
      expect(check("  stderr.writeln('x');"), hasLength(1));
      expect(check("  final x = 1; print(x);"), hasLength(1));

      expect(check('  catalog(x);'), isEmpty);
      expect(check('  backlog(x);'), isEmpty);
      expect(check('  final printer = 1;'), isEmpty);
      expect(check('  /// print(x) is never called. REQ-ENGINE-5.'), isEmpty);
      expect(check('  // log(x);'), isEmpty);
      expect(check('  final y = 2; // stdout'), isEmpty);
      expect(check("  const m = 'print(x) to stderr';"), isEmpty);
      expect(check("import 'dart:math';"), isEmpty);
    });

    test('REQ-ENGINE-2 no Timing_Engine file, including lib/src/internal/, '
        'reads the clock, randomness, I/O or environment, or declares a '
        'mutable top-level or static variable', () {
      final files = _timingFiles();
      // 19 type files plus at least event_rules.dart, or the scan is vacuous.
      expect(files.length, greaterThanOrEqualTo(20));
      expect(
        files.where((f) => f.uri.pathSegments.contains('internal')),
        isNotEmpty,
        reason: 'no file under lib/src/internal/',
      );
      expect(files.map(_name), contains('event_rules.dart'));
      for (final file in files) {
        expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
        expect(
          _impurityProblems(file.path, file.readAsLinesSync()),
          isEmpty,
          reason: file.path,
        );
      }
    });

    test('REQ-ENGINE-2 REQ-PBT-7 the purity check catches each planted '
        'violation and accepts clean sources', () {
      // Self-check on planted sources, so a broken check cannot pass
      // silently.
      List<String> check(String source) =>
          _impurityProblems('planted.dart', source.split('\n'));

      expect(check('  final t = DateTime.now();'), hasLength(1));
      expect(check('  final s = Stopwatch();'), hasLength(1));
      expect(check('  final r = Random();'), hasLength(1));
      expect(check('var counter = 0;'), hasLength(1));
      expect(
        check('final class Counter {\n  static int n = 0;\n}'),
        hasLength(1),
      );

      expect(check('final int x = 0;'), isEmpty);
      expect(check('final class C {\n  static const n = 1;\n}'), isEmpty);
      expect(check('final class Counter {\n  int _count = 0;\n}'), isEmpty);
      expect(check('// DateTime'), isEmpty);
      expect(
        check('  /// Never reads DateTime or Random. REQ-ENGINE-2.'),
        isEmpty,
      );
      expect(check("  const m = 'no Stopwatch here';"), isEmpty);
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

  group('no time constants outside Timing_Config', () {
    test('REQ-DEBOUNCE-2 REQ-PBT-7 the Debouncer, Classifier, Calibrator and '
        'decoder sources contain no numeric literal of 1,000 or more', () {
      for (final name in _noLargeLiteralFiles) {
        final file = File('lib/src/$name');
        expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
        final source = file.readAsStringSync();
        // The scan must see code, or it passes vacuously.
        expect(
          _blankCommentsAndStrings(source).trim(),
          isNotEmpty,
          reason: name,
        );
        expect(_largeLiteralProblems(name, source), isEmpty, reason: name);
      }
    });

    test('REQ-DEBOUNCE-2 the defaults 30000 and 2.0 appear in '
        'timing_config.dart and in no other lib/ file', () {
      final files = _libFiles();
      expect(files.map(_name), contains(_defaultsFile));
      for (final file in files) {
        expect(
          _defaultLiteralProblems(_name(file), file.readAsStringSync()),
          isEmpty,
          reason: file.path,
        );
      }
      final tokens = [
        for (final (_, token, _) in _numericLiteralsIn(
          File('lib/src/$_defaultsFile').readAsStringSync(),
        ))
          token,
      ];
      expect(tokens, containsAll(['30000', '2.0']));
    });

    test('REQ-DEBOUNCE-2 REQ-PBT-7 the literal checks catch planted '
        'violations and ignore near-misses', () {
      // Self-check on planted sources, so a broken check cannot pass
      // silently.
      List<String> large(String source) =>
          _largeLiteralProblems('debouncer.dart', source);

      expect(large('  if (gap < 30000) return;'), hasLength(1));
      expect(large('  final mask = 0x100000;'), hasLength(1));
      expect(large('  final d = 30_000;'), hasLength(1));
      expect(large('  final d = 1e3;'), hasLength(1));
      expect(large('  final d = 1000.0;'), hasLength(1));
      expect(large('  final d = 1000;'), hasLength(1));
      expect(large('  final a = 1000, b = 0X3E8;'), hasLength(2));
      expect(large('  /* note */ final d = 5000; // 30000'), hasLength(1));

      expect(large('  final d = 999;'), isEmpty);
      expect(large('  final d = 0x3E7;'), isEmpty);
      expect(large('  final d = 999.9 + 1e2 + .5;'), isEmpty);
      expect(large("  const m = 'wait 30000 us';"), isEmpty);
      expect(large('  const m = "30000";'), isEmpty);
      expect(large("  const m = r'30000\\';"), isEmpty);
      expect(large("  const m = '''\n30000\n''';"), isEmpty);
      expect(large("  const m = 'it\\'s 30000';"), isEmpty);
      expect(large('  // final d = 30000;'), isEmpty);
      expect(large('  /// Waits 30,000 us, or 30000.'), isEmpty);
      expect(large('  final d = 1; // 30000'), isEmpty);
      expect(large('  /* 30000 */ final d = 1;'), isEmpty);
      expect(large('  /*\n  30000\n  /* nested 0x100000 */\n  */'), isEmpty);
      expect(large('  final unit1000 = unit;'), isEmpty);
      expect(large(r'  final $1000 = x.isEven;'), isEmpty);
      expect(large('  final d = dit + (dah - dit + 1) ~/ 2;'), isEmpty);

      // Line numbers survive blanking of a multi-line comment.
      expect(large('/*\n\n*/\nfinal d = 30000;'), [
        'debouncer.dart line 4: literal 30000 is 1,000 or more',
      ]);

      List<String> defaults(String fileName, String source) =>
          _defaultLiteralProblems(fileName, source);

      expect(defaults('classifier.dart', '  final f = 2.0;'), hasLength(1));
      expect(defaults('classifier.dart', '  final f = 2e0;'), hasLength(1));
      expect(defaults('live_decoder.dart', '  final d = 30000;'), hasLength(1));
      expect(defaults('press.dart', '  final d = 30_000;'), hasLength(1));
      expect(defaults('internal.dart', '  final d = 0x7530;'), hasLength(1));
      expect(defaults(_defaultsFile, '  final f = 2.0, d = 30000;'), isEmpty);
      expect(defaults('classifier.dart', '  final h = x ~/ 2;'), isEmpty);
      expect(defaults('classifier.dart', '  final f = 2.5;'), isEmpty);
      expect(defaults('classifier.dart', "  const m = '2.0';"), isEmpty);
      expect(defaults('classifier.dart', '  /// Default 2.0.'), isEmpty);
    });
  });

  group('file structure and exports', () {
    test('REQ-PURE-4 REQ-ENGINE-3 each lib/src/ file declares exactly one '
        'public class or enum named after the file', () {
      // _srcFiles() is not recursive, so lib/src/internal/ is outside this
      // rule (design Decision T5).
      final files = _srcFiles();
      expect(files, isNotEmpty);
      for (final file in files) {
        expect(
          _structureProblems(_name(file), _codeLines(file)),
          isEmpty,
          reason: file.path,
        );
      }
    });

    test('REQ-PURE-4 REQ-ENGINE-3 the file-structure check accepts one class '
        'or one enum and rejects anything else', () {
      // Self-check on planted sources, so a broken check cannot pass
      // silently.
      List<String> check(String fileName, String source) =>
          _structureProblems(fileName, source.split('\n'));

      expect(check('code_table.dart', 'final class CodeTable {\n}'), isEmpty);
      expect(
        check('gap_class.dart', 'enum GapClass {\n  insideLetter,\n}'),
        isEmpty,
      );
      expect(
        check(
          'gap_class.dart',
          '// enum Commented {}\nenum GapClass { a }\nenum _Hidden { b }',
        ),
        isEmpty,
      );
      expect(
        check(
          'morse_symbol.dart',
          'final class MorseSymbol {}\nenum SymbolKind { dit, dah }',
        ),
        hasLength(1),
      );
      expect(check('empty.dart', 'int f() => 0;'), hasLength(1));
      expect(check('gap_class.dart', 'enum GapKind { a }'), hasLength(1));
      expect(check('gap_class.dart', 'mixin GapClass {}'), hasLength(1));
      expect(
        check('gap_class.dart', 'extension GapClass on int {}'),
        hasLength(1),
      );
    });

    test('REQ-PURE-4 snake_case conversion matches the naming rule', () {
      expect(_snakeCase('CodeTable'), 'code_table');
      expect(_snakeCase('MorseFormatException'), 'morse_format_exception');
      expect(_snakeCase('MorseDecoder'), 'morse_decoder');
    });

    test('REQ-PURE-5 lib/morse_core.dart exports every public class in '
        'lib/src/', () {
      final exports = {
        for (final (kind, uri, rest) in _directives(
          File('lib/morse_core.dart'),
        ))
          if (kind == 'export') uri: rest,
      };
      for (final file in _srcFiles()) {
        final uri = 'src/${_name(file)}';
        expect(exports.keys, contains(uri), reason: '$uri is not exported');
        final combinators = exports[uri]!;
        for (final (_, name) in _publicTypesOf(file)) {
          expect(
            combinators,
            isNot(contains('hide')),
            reason: '$uri hides names',
          );
          if (combinators.contains('show')) {
            expect(
              combinators,
              contains(name),
              reason: '$uri does not show $name',
            );
          }
        }
      }
    });

    test('REQ-PURE-5 lib/morse_core.dart exports nothing under '
        'src/internal/', () {
      final exports = [
        for (final (kind, uri, _) in _directives(File('lib/morse_core.dart')))
          if (kind == 'export') uri,
      ];
      expect(exports, isNotEmpty);
      for (final uri in exports) {
        expect(uri, isNot(contains('src/internal/')), reason: 'exports $uri');
      }
    });

    test('REQ-ENGINE-4 REQ-PURE-6 lib/morse_core.dart exports exactly the '
        'public API', () {
      expect(_publicTypes, hasLength(23));
      final exported = _exportedPublicTypes(
        File('lib/morse_core.dart').readAsStringSync(),
        (uri) => _codeLines(File('lib/$uri')),
      );
      expect(
        exported.difference(_publicTypes),
        isEmpty,
        reason: 'exported but not in the REQ-ENGINE-4 list',
      );
      expect(
        _publicTypes.difference(exported),
        isEmpty,
        reason: 'in the REQ-ENGINE-4 list but not exported',
      );
    });

    test('REQ-ENGINE-4 REQ-PBT-7 the public-API check catches a planted '
        'extra or missing export', () {
      // Self-check on a planted library, so a broken check cannot pass
      // silently.
      final real = File('lib/morse_core.dart').readAsStringSync();
      List<String> read(String uri) => switch (uri) {
        'src/extra_type.dart' => ['final class ExtraType {}'],
        'src/extra_kind.dart' => ['enum ExtraKind { a }'],
        _ => _codeLines(File('lib/$uri')),
      };
      final withExtraClass = _exportedPublicTypes(
        "$real\nexport 'src/extra_type.dart';",
        read,
      );
      expect(withExtraClass.difference(_publicTypes), {'ExtraType'});
      final withExtraEnum = _exportedPublicTypes(
        "$real\nexport 'src/extra_kind.dart';",
        read,
      );
      expect(withExtraEnum.difference(_publicTypes), {'ExtraKind'});
      final withoutPress = _exportedPublicTypes(
        real.replaceFirst("export 'src/press.dart';", ''),
        read,
      );
      expect(_publicTypes.difference(withoutPress), {'Press'});
      final hidden = _exportedPublicTypes(
        real.replaceFirst(
          "export 'src/gap_class.dart';",
          "export 'src/gap_class.dart' hide GapClass;",
        ),
        read,
      );
      expect(_publicTypes.difference(hidden), {'GapClass'});
    });

    test('REQ-ENGINE-3 every Timing_Engine type has its snake_case.dart file '
        'in lib/src/ and is reachable through the single public import', () {
      final timingTypes = _publicTypes.difference(_morseCoreTypes);
      expect(timingTypes, hasLength(19));
      final exported = _exportedPublicTypes(
        File('lib/morse_core.dart').readAsStringSync(),
        (uri) => _codeLines(File('lib/$uri')),
      );
      for (final name in timingTypes) {
        final file = File('lib/src/${_snakeCase(name)}.dart');
        expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
        expect(_publicTypesOf(file).map((t) => t.$2), [
          name,
        ], reason: '${file.path} must declare exactly $name');
        expect(exported, contains(name), reason: '$name is not exported');
      }
      // The Type literals compile only through package:morse_core, so the
      // single import really gives every type.
      expect(_timingTypeLiterals.map((t) => '$t').toSet(), timingTypes);
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
        requirementId: 'REQ-ERR-1',
        offending: '!',
        position: 0,
      );
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
      expect(
        files.map(_name),
        containsAll(['pubspec.yaml', 'code_table.dart']),
      );
      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          expect(
            pattern.hasMatch(lines[i]),
            isFalse,
            reason: '${file.path} line ${i + 1}',
          );
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
      expect(names.toSet().difference(_publicTypes), isEmpty);
    });

    test('REQ-PURE-6 REQ-ENGINE-4 example/ imports only the public library '
        'and names only public types', () {
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
          expect(
            uri,
            'package:morse_core/morse_core.dart',
            reason: '${file.path} imports $uri',
          );
        }
        for (final line in _codeLines(file)) {
          used.addAll(_typeName.allMatches(_stripCode(line)).map((m) => m[0]!));
        }
      }
      expect(used.difference({..._publicTypes, ..._coreTypes}), isEmpty);
      // The scan must see at least one public type, or it is broken.
      expect(used.intersection(_publicTypes), isNotEmpty);
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

/// Doc. REQ-CODE-1.
enum Kind {
  /// REQ-CODE-1.
  first,

  second,

  /// REQ-CODE-1.
  @Deprecated('x')
  third('{'),

  /// No requirement cited.
  fourth(
    'y');

  /// REQ-CODE-1.
  const Kind([this.label = '']);

  /// REQ-CODE-1.
  final String label;

  /// REQ-CODE-1.
  bool get isFirst => this == first;
}

/// Doc. REQ-CODE-1.
enum Plain {
  /// REQ-CODE-1.
  on,

  off
}

/// Doc. REQ-CODE-1.
enum Short { x, y }

enum _HiddenKind { a, b }

enum _HiddenLong {
  c,
  d,
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
        'Kind',
        'first',
        'second',
        'third',
        'fourth',
        'Kind',
        'label',
        'isFirst',
        'Plain',
        'on',
        'off',
        'Short',
        'x',
        'y',
      ]);
      expect(_undocumented(declarations).map((d) => d.name), [
        'missing',
        'noId',
        'size',
        'topLevel',
        'second',
        'fourth',
        'off',
        'x',
        'y',
      ]);
    });

    test('REQ-PURE-7 every public declaration in lib/ has a /// comment '
        'citing a requirement ID', () {
      final all = <String>{};
      for (final file in _libFiles()) {
        final declarations = _publicDeclarations(file.readAsLinesSync());
        all.addAll(declarations.map((d) => d.name));
        for (final d in _undocumented(declarations)) {
          fail(
            '${file.path} line ${d.line}: ${d.name} has no /// comment '
            'citing REQ-<AREA>-<n>',
          );
        }
      }
      // The scanner must see the known public API, or it is broken.
      expect(
        all,
        containsAll([
          'library',
          ..._publicTypes,
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
        ]),
      );
    });

    test(
      'REQ-PURE-7 every requirement ID cited in a lib/ doc comment exists',
      () {
        var cited = 0;
        for (final file in _libFiles()) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (!lines[i].trim().startsWith('///')) continue;
            for (final m in _requirementId.allMatches(lines[i])) {
              cited++;
              expect(
                _knownIds,
                contains(m[0]),
                reason: '${file.path} line ${i + 1} cites ${m[0]}',
              );
            }
          }
        }
        expect(cited, greaterThan(0));
      },
    );

    test('REQ-ENGINE-6 every public declaration in a Timing_Engine file, '
        'enum values included, has a /// comment citing a known ID', () {
      final files = _timingFiles();
      // 19 type files plus at least event_rules.dart, or the scan is vacuous.
      expect(files.length, greaterThanOrEqualTo(20));
      final names = <String>{};
      for (final file in files) {
        expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
        final lines = file.readAsLinesSync();
        names.addAll(_publicDeclarations(lines).map((d) => d.name));
        expect(
          _timingDocProblems(file.path, lines),
          isEmpty,
          reason: file.path,
        );
      }
      // The scanner must see the timing types and their enum values.
      expect(
        names,
        containsAll([
          ..._publicTypes.difference(_morseCoreTypes),
          'press',
          'release',
          'dit',
          'dah',
          'insideLetter',
          'betweenWords',
          'wordSpace',
          'unknownLetter',
          'timestampOutOfRange',
          'pressOverlapsPrevious',
          'unsuitableWord',
          'durationTooLong',
          'firstEventViolation',
          'pairPresses',
        ]),
      );
    });

    test('REQ-ENGINE-6 the timing doc check catches a planted enum value '
        'without a doc comment or with an unknown ID', () {
      // Self-check on planted sources, so a broken check cannot pass
      // silently.
      List<String> check(String source) =>
          _timingDocProblems('planted.dart', source.split('\n'));

      const good = '''
/// REQ-TIMING-4.
enum GapClass {
  /// REQ-TIMING-4.
  insideLetter,

  /// REQ-CODE-1.
  betweenLetters,
}
''';
      expect(check(good), isEmpty);
      expect(check(good.replaceFirst('  /// REQ-CODE-1.\n', '')), [
        'planted.dart line 6: betweenLetters has no /// comment citing a '
            'known requirement ID',
      ]);
      expect(
        check(good.replaceFirst('REQ-CODE-1', 'REQ-TIMING-99')),
        hasLength(1),
      );
      expect(
        check(good.replaceFirst('/// REQ-TIMING-4.\nenum', 'enum')),
        hasLength(1),
      );
      expect(
        check(
          '/// REQ-LIVE-1.\nfinal class LiveDecoder {\n'
          '  void press(int t) {}\n}',
        ),
        hasLength(1),
      );
    });

    test('REQ-ENGINE-6 REQ-PBT-3 the adaptive-timing ID set has 96 '
        'well-formed IDs, none shared with morse-core', () {
      expect(timingRequirementIds, hasLength(96));
      expect(requirementIds, hasLength(68));
      expect(timingRequirementIds.intersection(requirementIds), isEmpty);
      for (final id in timingRequirementIds) {
        expect(
          _requirementId.matchAsPrefix(id)?.group(0),
          id,
          reason: '$id is not REQ-<AREA>-<n>',
        );
      }
      expect(_knownIds, hasLength(164));
    });
  });

  group('test names and skips', () {
    test('REQ-TEST-4 the test-name scanner joins literals and reads leading '
        'IDs', () {
      // Self-check of the scanner, so a broken pattern cannot pass silently.
      // The calls are built from parts so this file's scan does not see them.
      const t =
          'te'
          'st';
      const p =
          'prop'
          'erty';
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
      expect(
        byFile.keys.map((p) => File(p).uri.pathSegments.last),
        containsAll(['code_table_test.dart', 'properties_test.dart']),
      );
      var count = 0;
      byFile.forEach((path, names) {
        expect(names, isNotEmpty, reason: '$path has no test names');
        for (final name in names) {
          count++;
          final ids = _idsAtStart(name);
          expect(
            ids,
            isNotEmpty,
            reason: '$path: "$name" does not begin with REQ-<AREA>-<n>',
          );
          for (final id in ids) {
            expect(
              _knownIds,
              contains(id),
              reason: '$path: "$name" cites unknown $id',
            );
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

    test('REQ-ENGINE-8 REQ-PBT-3 every ID listed in REQ-PBT-1, REQ-PBT-2, '
        'REQ-PBT-6 and REQ-PBT-7, and each of REQ-ENGINE-1 to REQ-ENGINE-6, '
        'begins at least one test name', () {
      // The lists must match requirements.md, or the check is incomplete.
      expect(_pbt1Ids, hasLength(11));
      expect(_pbt2Ids, hasLength(51));
      expect(_pbt6Ids, hasLength(3));
      expect(_pbt7Ids, hasLength(4));
      final required = {
        ..._pbt1Ids,
        ..._pbt2Ids,
        ..._pbt6Ids,
        ..._pbt7Ids,
        ..._engine8Ids,
      };
      expect(required.difference(timingRequirementIds), isEmpty);
      final leading = {
        for (final names in _allTestNames().values)
          for (final name in names) ..._idsAtStart(name),
      };
      final missing = required.difference(leading).toList()..sort();
      expect(missing, isEmpty, reason: 'no test name begins with $missing');
    });

    test('REQ-TEST-5 no test file skips a test', () {
      // Self-check of the pattern.
      expect(
        _skipMarker.hasMatch(
          '${'sk'
              'ip'}: true',
        ),
        isTrue,
      );
      expect(
        _skipMarker.hasMatch(
          '@${'Sk'
              'ip'}()',
        ),
        isTrue,
      );
      expect(
        _skipMarker.hasMatch(
          'lines.${'sk'
              'ip'}(1)',
        ),
        isFalse,
      );
      final files = _allTestDartFiles();
      expect(files, isNotEmpty);
      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          expect(
            _skipMarker.hasMatch(lines[i]),
            isFalse,
            reason: '${file.path} line ${i + 1}: ${lines[i].trim()}',
          );
        }
      }
    });

    test(
      'REQ-PURE-9 each of REQ-PURE-1 to REQ-PURE-7 appears in a test name',
      () {
        final cited = {
          for (final names in _allTestNames().values)
            for (final name in names)
              ..._requirementId.allMatches(name).map((m) => m[0]!),
        };
        for (var n = 1; n <= 7; n++) {
          expect(
            cited,
            contains('REQ-PURE-$n'),
            reason: 'no test name cites REQ-PURE-$n',
          );
        }
      },
    );
  });
}
