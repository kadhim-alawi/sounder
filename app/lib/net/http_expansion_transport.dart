import 'dart:convert';

import 'package:http/http.dart' as http;

import '../compose/expansion_client.dart';

/// The [ExpansionTransport] used by the hosted app: one same-origin
/// `POST /expand` through `package:http`. It logs nothing (no body, no
/// tokens) and keeps no state. Errors from the client propagate; the
/// Expansion_Client maps them to a network failure. REQ-WAIT-3, REQ-FAIL-4.
final class HttpExpansionTransport implements ExpansionTransport {
  /// A transport that sends through [client]. The caller owns [client] and
  /// closes it. REQ-WAIT-3.
  HttpExpansionTransport(this._client);

  final http.Client _client;

  /// Posts [jsonBody] to `/expand` on the page's own origin with
  /// `Content-Type: application/json` and returns the status code and the
  /// body decoded as UTF-8 (malformed bytes replaced, never thrown).
  /// REQ-WAIT-3, REQ-FAIL-4.
  @override
  Future<TransportResponse> postExpand(String jsonBody) async {
    final response = await _client.post(
      Uri.base.resolve('/expand'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonBody,
    );
    return TransportResponse(
      response.statusCode,
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
  }
}
