/// Test-only mocks for the Expand flow: the Expansion_Client and the notice
/// store. They live only under `app/test/`, their names begin with `Mock`,
/// they make no network request and log nothing. REQ-APPTEST-3,
/// REQ-APPTEST-4.
library;

import 'dart:async';

import 'package:sounder/compose/expansion_client.dart';
import 'package:sounder/store/notice_store.dart';

/// An [ExpansionClient] that records every [expand] call and completes each
/// one only when the test says so. REQ-APPTEST-3, REQ-APPTEST-4.
final class MockExpansionClient implements ExpansionClient {
  /// The Sentence_Tokens of every [expand] call, in call order.
  /// REQ-APPTEST-3.
  final List<List<String>> calls = <List<String>>[];

  final List<Completer<ExpansionResult>> _pending =
      <Completer<ExpansionResult>>[];

  /// Records [tokens] and returns a future the test completes with [reply]
  /// or [fail]. REQ-WAIT-3, REQ-APPTEST-4.
  @override
  Future<ExpansionResult> expand(List<String> tokens) {
    calls.add(List<String>.unmodifiable(tokens));
    final completer = Completer<ExpansionResult>();
    _pending.add(completer);
    return completer.future;
  }

  /// Completes call [index] (0-based) as a 200 reply holding [candidates].
  /// REQ-CHOICE-1.
  void reply(int index, List<String> candidates) => _pending[index].complete(
    ExpansionReply(calls[index], List<String>.unmodifiable(candidates)),
  );

  /// Completes call [index] (0-based) as a failure of [kind]. REQ-FAIL-1.
  void fail(int index, ExpansionFailureKind kind) =>
      _pending[index].complete(ExpansionFailure(calls[index], kind));
}

/// A [NoticeStore] with a settable stored value that can be made to throw
/// on read, on write, or both. REQ-NOTICE-5, REQ-APPTEST-4.
final class MockNoticeStore implements NoticeStore {
  /// Creates a store holding [accepted]. REQ-NOTICE-4.
  MockNoticeStore({this.accepted = false, this.readError, this.writeError});

  /// The stored Notice_Acceptance. [accept] sets it to `true` unless
  /// [writeError] is set. REQ-NOTICE-2, REQ-NOTICE-4.
  bool accepted;

  /// When non-null, [isAccepted] throws it. REQ-NOTICE-5.
  Object? readError;

  /// When non-null, [accept] throws it and stores nothing. REQ-NOTICE-5.
  Object? writeError;

  /// How many times [isAccepted] was called. REQ-NOTICE-5.
  int readCalls = 0;

  /// How many times [accept] was called. REQ-NOTICE-2, REQ-NOTICE-3.
  int acceptCalls = 0;

  /// Returns [accepted], or throws [readError]. REQ-NOTICE-4, REQ-NOTICE-5.
  @override
  Future<bool> isAccepted() async {
    readCalls++;
    final error = readError;
    if (error != null) throw error;
    return accepted;
  }

  /// Stores `true`, or throws [writeError]. REQ-NOTICE-2, REQ-NOTICE-5.
  @override
  Future<void> accept() async {
    acceptCalls++;
    final error = writeError;
    if (error != null) throw error;
    accepted = true;
  }
}
