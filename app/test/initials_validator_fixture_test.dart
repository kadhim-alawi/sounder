// Fixture loop for the Dart_Validator (REQ-VALIDATOR-2, REQ-APPTEST-1).
//
// Reads the shared Validator_Fixture, which the TS_Validator also reads in
// `worker/test/validator.test.ts`, checks its schema shape as
// `worker/test/fixture_coverage.test.ts` does, and asserts that
// `isValidCandidate` returns each case's recorded result. Failure messages
// name the case id, never the candidate text.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sounder/compose/initials_validator.dart';

/// The fixture path relative to `app/`, the working directory of
/// `flutter test` (REQ-APPTEST-1).
const _fixturePath = '../fixtures/expansion_validator.json';

const _rootKeys = ['cases', 'version'];
const _caseKeys = ['candidate', 'id', 'tags', 'tokens', 'valid'];
final _idPattern = RegExp(r'^[a-z0-9-]+$');
final _tokenPattern = RegExp(r'^[A-Za-z]{1,8}$');

List<String> _sortedKeys(Map<String, dynamic> m) => m.keys.toList()..sort();

/// Label for a case: its id when it has one, else its index.
String _label(Object? c, int index) =>
    c is Map<String, dynamic> && c['id'] is String
        ? c['id'] as String
        : '#$index';

void main() {
  final Object? root = jsonDecode(File(_fixturePath).readAsStringSync());
  final rawCases = root is Map<String, dynamic> && root['cases'] is List
      ? root['cases'] as List
      : const <Object?>[];

  group('REQ-VALIDATOR-2, REQ-APPTEST-1: Validator_Fixture schema shape', () {
    test('REQ-VALIDATOR-2, REQ-APPTEST-1: root has exactly version 1 and a '
        'non-empty cases list', () {
      expect(root, isA<Map<String, dynamic>>());
      final m = root as Map<String, dynamic>;
      expect(_sortedKeys(m), _rootKeys);
      expect(m['version'], 1);
      expect(m['cases'], isA<List>());
      expect(rawCases, isNotEmpty);
    });

    test('REQ-VALIDATOR-2, REQ-APPTEST-1: every case has exactly the keys '
        'id, tags, tokens, candidate, valid with the right types', () {
      final problems = <String>[];
      for (var i = 0; i < rawCases.length; i++) {
        final c = rawCases[i];
        final name = _label(c, i);
        if (c is! Map<String, dynamic>) {
          problems.add('case $name is not an object');
          continue;
        }
        if (!_sameStrings(_sortedKeys(c), _caseKeys)) {
          problems.add('case $name keys ${_sortedKeys(c)}');
        }
        final id = c['id'];
        if (id is! String || !_idPattern.hasMatch(id)) {
          problems.add('case $name id pattern');
        }
        final tags = c['tags'];
        if (tags is! List || tags.isEmpty || !tags.every((t) => t is String)) {
          problems.add('case $name tags');
        }
        final tokens = c['tokens'];
        if (tokens is! List ||
            tokens.isEmpty ||
            tokens.length > 12 ||
            !tokens.every((t) => t is String && _tokenPattern.hasMatch(t))) {
          problems.add('case $name tokens');
        }
        if (c['candidate'] is! String) {
          problems.add('case $name candidate type');
        }
        if (c['valid'] is! bool) problems.add('case $name valid type');
      }
      expect(problems, isEmpty);
    });

    test('REQ-VALIDATOR-2, REQ-APPTEST-1: case ids are unique', () {
      final seen = <String>{};
      final duplicates = <String>[];
      for (var i = 0; i < rawCases.length; i++) {
        final id = _label(rawCases[i], i);
        if (!seen.add(id)) duplicates.add(id);
      }
      expect(duplicates, isEmpty);
    });
  });

  test('REQ-VALIDATOR-2, REQ-APPTEST-1: the Dart_Validator returns the '
      'expected result for every fixture case', () {
    expect(rawCases, isNotEmpty);
    final mismatches = <String>[];
    for (var i = 0; i < rawCases.length; i++) {
      final c = rawCases[i] as Map<String, dynamic>;
      final tokens = (c['tokens'] as List).cast<String>();
      final candidate = c['candidate'] as String;
      final expected = c['valid'] as bool;
      final actual = isValidCandidate(tokens, candidate);
      if (actual != expected) {
        mismatches.add('${_label(c, i)}: expected $expected, got $actual');
      }
    }
    expect(mismatches, isEmpty, reason: 'fixture cases that failed, by id');
  });
}

/// Element-wise equality of two string lists.
bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
