import 'dart:async';
import 'dart:convert';

/// Waits for [duration], then completes. The real one (`Future.delayed`) is
/// provided by the Key_Screen controller; tests inject a mock. Keeps this
/// file free of timers (REQ-COMPOSE-1). REQ-WAIT-5.
typedef Delay = Future<void> Function(Duration duration);

/// The status code and body text of one `/expand` reply. REQ-WAIT-3.
final class TransportResponse {
  /// A reply with HTTP [status] and [body] text. REQ-WAIT-3.
  const TransportResponse(this.status, this.body);

  /// The HTTP status code. REQ-FAIL-1.
  final int status;

  /// The reply body, decoded as UTF-8 text. REQ-FAIL-1.
  final String body;
}

/// Sends the request body to the Worker. Implemented in `lib/net/`, so this
/// file does no I/O (REQ-COMPOSE-1). REQ-WAIT-3.
abstract interface class ExpansionTransport {
  /// One same-origin POST of [jsonBody] to /expand with Content-Type
  /// application/json. REQ-WAIT-3.
  Future<TransportResponse> postExpand(String jsonBody);
}

/// How one expansion request ended. Carries the [tokens] it was sent for, so
/// the caller can tell a stale reply from the newest. REQ-WAIT-3, REQ-FAIL-1.
sealed class ExpansionResult {
  /// Base constructor for a result for [tokens]. REQ-WAIT-3.
  const ExpansionResult(this.tokens);

  /// The Sentence_Tokens the request was sent for. Unmodifiable. REQ-WAIT-3.
  final List<String> tokens;
}

/// A 200 reply with a readable `candidates` list. The candidates are not yet
/// validated; the caller does that (REQ-CHOICE-1). REQ-FAIL-1.
final class ExpansionReply extends ExpansionResult {
  /// A reply for [tokens] holding [candidates]. REQ-FAIL-1.
  const ExpansionReply(super.tokens, this.candidates);

  /// The string items of the reply's `candidates` list, in order.
  /// Unmodifiable. REQ-FAIL-1.
  final List<String> candidates;
}

/// Why a request failed. REQ-WAIT-5, REQ-FAIL-1.
enum ExpansionFailureKind {
  /// No reply within the client timeout (6 s). REQ-WAIT-5.
  timeout,

  /// The transport threw. REQ-FAIL-1.
  network,

  /// The reply status was not 200. REQ-FAIL-1.
  status,

  /// The body was not JSON, or not an object with a `candidates` list.
  /// REQ-FAIL-1.
  unreadable,
}

/// A request that ended without candidates, for [kind]. REQ-FAIL-1.
final class ExpansionFailure extends ExpansionResult {
  /// A failure for [tokens] of [kind]. REQ-FAIL-1.
  const ExpansionFailure(super.tokens, this.kind);

  /// Why the request failed. REQ-FAIL-1.
  final ExpansionFailureKind kind;
}

/// Asks the Worker to expand Sentence_Tokens into candidate sentences.
/// REQ-WAIT-3.
abstract interface class ExpansionClient {
  /// Sends [tokens] and completes with how the request ended. Transport and
  /// reply errors become an [ExpansionFailure], not a future error.
  /// REQ-WAIT-3, REQ-WAIT-5, REQ-FAIL-1.
  Future<ExpansionResult> expand(List<String> tokens);
}

/// The [ExpansionClient] used by the app: builds the body, races the
/// [ExpansionTransport] against an injected [Delay], and parses the reply.
/// It does not validate candidates, logs nothing and keeps no state between
/// requests. Pure Dart, no timer of its own. REQ-WAIT-3, REQ-WAIT-5,
/// REQ-FAIL-1, REQ-FAIL-4, REQ-COMPOSE-1.
final class TransportExpansionClient implements ExpansionClient {
  /// A client sending through [transport] that ends a request as a timeout
  /// once [delay] of [timeout] completes. REQ-WAIT-3, REQ-WAIT-5.
  /// Callers name the arguments `transport`, `delay` and `timeout`.
  TransportExpansionClient({
    required this._transport,
    required this._delay,
    this._timeout = const Duration(seconds: 6),
  });

  final ExpansionTransport _transport;
  final Delay _delay;
  final Duration _timeout;

  /// Sends `{"tokens":[...]}` once and completes with the first of the
  /// parsed reply or a timeout. A late reply after the timeout is ignored.
  /// REQ-WAIT-3, REQ-WAIT-5, REQ-FAIL-1, REQ-FAIL-4.
  @override
  Future<ExpansionResult> expand(List<String> tokens) {
    final sent = List<String>.unmodifiable(tokens);
    final body = jsonEncode({'tokens': sent});
    // Both futures are mapped so that neither completes with an error; a
    // transport error after the timeout is therefore never unhandled.
    final reply =
        Future<TransportResponse>.sync(() => _transport.postExpand(body))
            .then<ExpansionResult>(
              (response) => _parse(sent, response),
              onError: (Object _) =>
                  ExpansionFailure(sent, ExpansionFailureKind.network),
            );
    final timedOut = _delay(_timeout).then<ExpansionResult>(
      (_) => ExpansionFailure(sent, ExpansionFailureKind.timeout),
    );
    return Future.any([reply, timedOut]);
  }

  static ExpansionResult _parse(List<String> tokens, TransportResponse r) {
    if (r.status != 200) {
      return ExpansionFailure(tokens, ExpansionFailureKind.status);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(r.body);
    } on FormatException {
      return ExpansionFailure(tokens, ExpansionFailureKind.unreadable);
    }
    if (decoded is! Map || decoded['candidates'] is! List) {
      return ExpansionFailure(tokens, ExpansionFailureKind.unreadable);
    }
    final items = decoded['candidates'] as List;
    return ExpansionReply(
      tokens,
      List<String>.unmodifiable(items.whereType<String>()),
    );
  }
}
