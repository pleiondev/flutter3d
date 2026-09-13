/// An MCP server reached over a local HTTP socket instead of stdin and
/// stdout — so an application a person already has open can hand an agent the
/// live session in its window rather than a second, disconnected one a
/// headless process would have to reopen from disk.
///
/// **The server does not know this exists.** [LoopbackMcpServer.start] builds
/// whatever server [serve] builds, wired to a [StreamChannel] that happens to
/// be backed by HTTP requests instead of a pipe; nothing reaches into the
/// server to make it transport-aware. It lived in `flutter3d_model_mcp` as that
/// server's own, where any second application wanting the same would have had
/// to copy it.
///
/// **One JSON-RPC message per HTTP request, not a persistent duplex socket.**
/// `dart:io`'s [HttpServer] gives a full-duplex byte stream only per
/// connection, and `package:json_rpc_2`'s `Peer` underneath every server
/// already frames one message per element of a [StreamChannel]. A `POST`
/// carrying one request or notification, answered with the one reply it
/// produced (or, for a notification, no body at all), is the smallest transport
/// that satisfies that framing. What it cannot do is push a server-initiated
/// message with no request to answer; see [_PendingReplies].
///
/// **127.0.0.1 only, always** — never [InternetAddress.anyIPv4]. A session a
/// server holds is a document an agent can read, write, undo and export, and
/// the only thing standing between that and anyone else on the network is
/// this binding staying loopback-only. [LoopbackMcpServer.start] takes no
/// address for exactly that reason.
///
/// **A random token, minted per server and required on every request.**
/// Loopback-only keeps this off the network, not off every other process on
/// the same machine. A request is accepted when its `Authorization` header
/// (`Bearer`, then the token) or its `token` query parameter carries the
/// token, and nothing else is.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:stream_channel/stream_channel.dart';

/// A server listening on `127.0.0.1`.
final class LoopbackMcpServer {
  LoopbackMcpServer._(
    this._server,
    this._peerIncoming,
    this._peerOutgoing,
    this.token,
  );

  final HttpServer _server;
  final StreamController<String> _peerIncoming;
  final StreamController<String> _peerOutgoing;

  /// The token every request must present — write this into the session file
  /// ([writeMcpSessionFile]) so whatever starts this can hand it to an agent.
  final String token;

  /// The port this bound to — the one to put in the session file, since
  /// [start]'s own `port: 0` (ephemeral) means the caller cannot know it in
  /// advance.
  int get port => _server.port;

  /// Binds `127.0.0.1:$port` and wires the server [serve] builds to it.
  ///
  /// `0` (the default) picks any free port, which is what a caller that reads
  /// [port] back out and writes it to a session file wants; a fixed port is for
  /// a script waiting on a known one that would rather fail loudly on a
  /// collision than bind elsewhere. [token] is minted when omitted — the only
  /// case a real caller needs; a caller passing one is a test that wants to
  /// know it ahead of time.
  static Future<LoopbackMcpServer> start({
    required void Function(StreamChannel<String> channel) serve,
    int port = 0,
    String? token,
  }) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
    );
    final String actualToken = token ?? _randomToken();

    // The channel the server is built on. Its `Peer` reads [incoming.stream]
    // and writes replies to [outgoing.sink] — the shape `stdioChannel` gives a
    // process, minus the newline framing, since an HTTP body is already one
    // message with no separator needed.
    final StreamController<String> incoming = StreamController<String>();
    final StreamController<String> outgoing = StreamController<String>();

    // Every reply is matched back to the HTTP request still waiting on it by
    // JSON-RPC `id`, not by arrival order, so an agent that pipelines two
    // calls still gets each reply on the right connection. A message with no
    // `id` is a notification travelling server-to-client; nothing here has an
    // open connection to put it on, so it is dropped rather than queued
    // forever.
    final _PendingReplies pending = _PendingReplies();
    outgoing.stream.listen((String message) {
      final Object? id = _idOf(message);
      if (id != null) pending.resolve(id, message);
    });

    serve(StreamChannel<String>(incoming.stream, outgoing.sink));

    final LoopbackMcpServer result = LoopbackMcpServer._(
      server,
      incoming,
      outgoing,
      actualToken,
    );

    server.listen((HttpRequest request) async {
      await _handle(
        request,
        token: actualToken,
        incoming: incoming.sink,
        pending: pending,
      );
    });

    return result;
  }

  static Future<void> _handle(
    HttpRequest request, {
    required String token,
    required StreamSink<String> incoming,
    required _PendingReplies pending,
  }) async {
    final HttpResponse response = request.response;
    try {
      if (request.method != 'POST') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.write('POST a JSON-RPC message here');
        return;
      }
      if (_presentedToken(request) != token) {
        response.statusCode = HttpStatus.unauthorized;
        response.write('missing or wrong token');
        return;
      }

      final String body = await utf8.decoder.bind(request).join();
      final Object? id = _idOf(body);
      if (id == null) {
        // A notification: `Peer` never answers one, so there is nothing to
        // wait for — `202` says the message landed, not that anything ran
        // yet.
        incoming.add(body);
        response.statusCode = HttpStatus.accepted;
        return;
      }

      final Future<String> reply = pending.await_(id);
      incoming.add(body);
      response.headers.contentType = ContentType.json;
      response.write(await reply);
    } catch (error) {
      // A reply already in flight has committed the status line — setting one
      // again here would throw a second error out of a handler already failing
      // on its first, so this is best-effort.
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.write('$error');
      } catch (_) {
        // Too late to change the status; [response.close] below still runs.
      }
    } finally {
      await response.close();
    }
  }

  static String? _presentedToken(HttpRequest request) {
    final String? header = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (header != null && header.startsWith('Bearer ')) {
      return header.substring('Bearer '.length);
    }
    return request.uri.queryParameters['token'];
  }

  static String _randomToken() {
    final Random random = Random.secure();
    return base64Url.encode(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  /// Closes the socket and the channel the server was wired to. Does not touch
  /// the session file — a caller that wrote one owns removing it too, since
  /// only it knows whether another server still points at the same file.
  Future<void> close() async {
    await _server.close(force: true);
    await _peerIncoming.close();
    await _peerOutgoing.close();
  }
}

/// Matches a `Peer`'s replies back to the HTTP request awaiting each one, by
/// JSON-RPC `id` rather than arrival order.
final class _PendingReplies {
  final Map<Object?, Completer<String>> _byId = <Object?, Completer<String>>{};

  Future<String> await_(Object? id) {
    final completer = Completer<String>();
    _byId[id] = completer;
    return completer.future;
  }

  void resolve(Object? id, String message) {
    _byId.remove(id)?.complete(message);
  }
}

Object? _idOf(String message) {
  try {
    final Object? decoded = json.decode(message);
    return decoded is Map<String, Object?> ? decoded['id'] : null;
  } on FormatException {
    return null;
  }
}

/// Where an application's own running [LoopbackMcpServer] can be found,
/// written beside the application's existing session state.
///
/// Takes the directory as a plain path rather than resolving a per-platform
/// application-support directory, because this package stays plain Dart and
/// the application wiring a server in already has that directory. Written
/// after the socket is bound, since [port] and [token] both come from the
/// running server — a file naming a port nothing is listening on yet would
/// race whatever reads it.
void writeMcpSessionFile(
  File file, {
  required int port,
  required String token,
}) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    json.encode(<String, Object?>{'port': port, 'token': token}),
  );
}

/// Removes the session file [writeMcpSessionFile] wrote — called once the
/// server it named is no longer listening, so nothing reads a port that has
/// gone stale.
void deleteMcpSessionFile(File file) {
  if (file.existsSync()) file.deleteSync();
}
