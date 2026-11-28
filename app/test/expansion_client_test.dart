import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:morse_core/morse_core.dart';
import 'package:sounder/compose/expansion_client.dart';
import 'package:sounder/compose/sentence_tokens.dart';

/// Records every body sent and returns a reply future the test completes.
/// Makes no network request. REQ-APPTEST-4.
final class MockExpansionTransport implements ExpansionTransport {
  final List<String> bodies = [];
  final List<Completer<TransportResponse>> replies = [];

  @override
  Future<TransportResponse> postExpand(String jsonBody) {
    bodies.add(jsonBody);
    final reply = Completer<TransportResponse>();
    replies.add(reply);
    return reply.future;
  }
}

/// A [Delay] whose futures complete only when the test says so, standing in
/// for the 6-second timer. REQ-APPTEST-4, REQ-WAIT-5.
final class MockDelay {
  final List<Duration> durations = [];
  final List<Completer<void>> waits = [];

  Future<void> call(Duration duration) {
    durations.add(duration);
    final wait = Completer<void>();
    waits.add(wait);
    return wait.future;
  }

  void elapse() => waits.last.complete();
}

void main() {
  late MockExpansionTransport transport;
  late MockDelay delay;
  late TransportExpansionClient client;

  setUp(() {
    transport = MockExpansionTransport();
    delay = MockDelay();
    client = TransportExpansionClient(transport: transport, delay: delay.call);
  });

  const tokens = ['I', 'w', 'tea'];

  test('REQ-WAIT-3: the body is {"tokens":[...]} holding the Sentence_Tokens',
      () {
    final items = [
      const DecodedItem.letter('I'),
      const DecodedItem.wordSpace(),
      const DecodedItem.letter('W'),
      const DecodedItem.wordSpace(),
      const DecodedItem.letter('T'),
      const DecodedItem.letter('E'),
      const DecodedItem.letter('A'),
    ];
    final check = sentenceTokens(items);
    expect(check, isA<TokensReady>());
    final sentenceTokensList = (check as TokensReady).tokens;

    unawaited(client.expand(sentenceTokensList));

    expect(transport.bodies, hasLength(1));
    expect(
      transport.bodies.single,
      jsonEncode({'tokens': sentenceTokensList}),
    );
    final decoded = jsonDecode(transport.bodies.single) as Map;
    expect(decoded.keys, ['tokens']);
    expect(decoded['tokens'], sentenceTokensList);
  });

  test('REQ-WAIT-5: the client waits 6 seconds by default', () {
    unawaited(client.expand(tokens));
    expect(delay.durations, [const Duration(seconds: 6)]);
  });

  test('REQ-FAIL-1: a 200 reply keeps the string items in order', () async {
    final result = client.expand(tokens);
    transport.replies.single.complete(const TransportResponse(
      200,
      '{"candidates":["I want tea.",3,"I wish to talk.",null,'
          '"I would try."]}',
    ));
    final reply = await result;
    expect(reply, isA<ExpansionReply>());
    reply as ExpansionReply;
    expect(reply.candidates, ['I want tea.', 'I wish to talk.', 'I would try.']);
    expect(reply.tokens, tokens);
  });

  test('REQ-FAIL-1: a non-200 status is a status failure', () async {
    final result = client.expand(tokens);
    transport.replies.single.complete(
      const TransportResponse(503, '{"candidates":["I want tea."]}'),
    );
    final failure = await result;
    expect(failure, isA<ExpansionFailure>());
    expect((failure as ExpansionFailure).kind, ExpansionFailureKind.status);
    expect(failure.tokens, tokens);
  });

  for (final (label, body) in [
    ('not JSON', 'not json'),
    ('a JSON list', '["I want tea."]'),
    ('an object without candidates', '{"other":[]}'),
    ('candidates that are not a list', '{"candidates":"I want tea."}'),
  ]) {
    test('REQ-FAIL-1: a 200 body that is $label is unreadable', () async {
      final result = client.expand(tokens);
      transport.replies.single.complete(TransportResponse(200, body));
      final failure = await result;
      expect(failure, isA<ExpansionFailure>());
      expect(
        (failure as ExpansionFailure).kind,
        ExpansionFailureKind.unreadable,
      );
    });
  }

  test('REQ-FAIL-1: a transport error is a network failure', () async {
    final result = client.expand(tokens);
    transport.replies.single.completeError(StateError('offline'));
    final failure = await result;
    expect(failure, isA<ExpansionFailure>());
    expect((failure as ExpansionFailure).kind, ExpansionFailureKind.network);
  });

  test('REQ-WAIT-5, REQ-FAIL-1: no reply before the delay is a timeout',
      () async {
    final result = client.expand(tokens);
    delay.elapse();
    final failure = await result;
    expect(failure, isA<ExpansionFailure>());
    expect((failure as ExpansionFailure).kind, ExpansionFailureKind.timeout);
    expect(failure.tokens, tokens);
  });

  test('REQ-WAIT-5: a late reply after the timeout does not change the result',
      () async {
    final result = client.expand(tokens);
    delay.elapse();
    final first = await result;
    transport.replies.single.complete(
      const TransportResponse(200, '{"candidates":["I want tea."]}'),
    );
    await pumpEventQueue();
    expect((first as ExpansionFailure).kind, ExpansionFailureKind.timeout);
    expect(await result, same(first));
  });

  test('REQ-WAIT-5: a late transport error after the timeout is not raised',
      () async {
    final result = client.expand(tokens);
    delay.elapse();
    final first = await result;
    transport.replies.single.completeError(StateError('offline'));
    await pumpEventQueue();
    expect(await result, same(first));
    expect((first as ExpansionFailure).kind, ExpansionFailureKind.timeout);
  });

  test('REQ-WAIT-5: a reply before the delay wins', () async {
    final result = client.expand(tokens);
    transport.replies.single.complete(
      const TransportResponse(200, '{"candidates":["I want tea."]}'),
    );
    final reply = await result;
    delay.elapse();
    await pumpEventQueue();
    expect(reply, isA<ExpansionReply>());
    expect(await result, same(reply));
  });
}
