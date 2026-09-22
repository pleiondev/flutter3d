import 'dart:convert';

import 'package:http/http.dart' as http;

import 'xapi_exception.dart';
import 'xapi_lrs_config.dart';
import 'xapi_statement.dart';

/// Sends one [XapiStatement] at a time to an LRS.
///
/// A `PUT` with the statement's own `id` as the `statementId` query
/// parameter (xAPI spec §Data — Resources), not a `POST`: `PUT` is the
/// idempotent form, so retrying a submission that timed out but actually
/// landed cannot double a student's record the way a second `POST` could.
final class XapiClient {
  XapiClient({required this.lrs, http.Client? httpClient})
    : _http = httpClient ?? http.Client(),
      _ownsHttpClient = httpClient == null;

  final XapiLrsConfig lrs;

  final http.Client _http;
  final bool _ownsHttpClient;

  Future<void> send(XapiStatement statement) async {
    final uri = lrs.statementsEndpoint.replace(
      queryParameters: {'statementId': statement.id},
    );
    final response = await _http.put(
      uri,
      headers: {
        'Authorization': lrs.authorizationHeader,
        'Content-Type': 'application/json',
        'X-Experience-API-Version': '1.0.3',
      },
      body: jsonEncode(statement.toJson()),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw XapiException(
        'PUT $uri failed with HTTP ${response.statusCode}: '
        '${response.body}',
      );
    }
  }

  /// Frees the HTTP client this client created, when it created one itself.
  void close() {
    if (_ownsHttpClient) _http.close();
  }
}
