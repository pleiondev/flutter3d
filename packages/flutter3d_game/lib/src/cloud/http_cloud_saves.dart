import 'package:http/http.dart' as http;

import 'cloud_save_store.dart';

/// Saves kept on a server the game's makers run, over plain HTTP.
///
/// ## The protocol
///
/// One resource per slot, at `<base>/saves/<game>/<slot>`:
///
/// | | |
/// |---|---|
/// | `GET` | `200` with the document and an `ETag`, or `404` for none |
/// | `PUT` | the document, with `If-Match: <etag>` to replace a copy or `If-None-Match: *` to create one; `200`, `201` or `204` with the new `ETag`, or `412` when another device wrote first |
///
/// That is all of it, on purpose: conditional requests are what HTTP already
/// has for "write this unless somebody else did", and any server — a function
/// behind a CDN, a few lines of shelf — can answer them.
///
/// **An `ETag` is required, not hoped for.** Without one a write cannot say
/// what it replaces, and the one thing this store is for — two devices not
/// overwriting each other — would rest on luck. A server that sends none is
/// refused, saying so.
///
/// Who the player is goes in [headers], asked for on every request so a token
/// that expired between two syncs is fetched again by whoever owns it.
final class HttpCloudSaves implements CloudSaveStore {
  HttpCloudSaves({
    required this.base,
    required this.game,
    this.headers,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// Where the server is. Slots are below `saves/<game>/` under it.
  final Uri base;

  /// Which game's saves, so one server can keep several.
  final String game;

  /// The headers that say who the player is, usually an `Authorization`.
  final Future<Map<String, String>> Function()? headers;

  final http.Client _client;
  final bool _ownsClient;

  @override
  String get name => base.host.isEmpty ? 'the save server' : base.host;

  Uri _slot(String slot) => base.replace(
    pathSegments: <String>[
      ...base.pathSegments.where((segment) => segment.isNotEmpty),
      'saves',
      game,
      slot,
    ],
  );

  @override
  Future<CloudFetch> fetch(String slot) async {
    final uri = _slot(slot);
    try {
      final response = await _client.get(uri, headers: await _headers());
      return switch (response.statusCode) {
        404 => const CloudEmpty(),
        200 => switch (response.headers['etag']) {
          final etag? => CloudDocument(response.body, version: etag),
          null => CloudUnavailable(
            '$name sent the save without an ETag, so a write could not tell '
            'whether another device wrote in between',
          ),
        },
        final status => CloudUnavailable('GET $uri answered $status'),
      };
    } on Exception catch (error) {
      return CloudUnavailable('$name could not be reached ($error)');
    }
  }

  @override
  Future<CloudPut> put(
    String slot,
    String document, {
    String? replacing,
  }) async {
    final uri = _slot(slot);
    try {
      final response = await _client.put(
        uri,
        headers: <String, String>{
          ...await _headers(),
          'Content-Type': 'application/json',
          if (replacing != null)
            'If-Match': replacing
          else
            'If-None-Match': '*',
        },
        body: document,
      );
      return switch (response.statusCode) {
        412 => const CloudMoved(),
        200 || 201 || 204 => switch (response.headers['etag']) {
          final etag? => CloudStored(version: etag),
          null => CloudUnavailable(
            '$name kept the save but sent no ETag for it',
          ),
        },
        final status => CloudUnavailable('PUT $uri answered $status'),
      };
    } on Exception catch (error) {
      return CloudUnavailable('$name could not be reached ($error)');
    }
  }

  Future<Map<String, String>> _headers() async =>
      await headers?.call() ?? const <String, String>{};

  /// Frees the HTTP client, when this made it.
  void close() {
    if (_ownsClient) _client.close();
  }
}
