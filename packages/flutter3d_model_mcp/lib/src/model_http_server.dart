/// The same [ModelMcpServer], reached over a local HTTP socket instead of
/// stdin/stdout — `mcp-13n`'s row: the GUI keeps one live [ModelSession] a
/// person is editing in a window, and hands an agent the same session rather
/// than a second, disconnected one a headless process would have to reopen
/// from disk.
///
/// **[ModelSession] still does not know this exists.** Everything below is a
/// second adapter beside [ModelMcpServer]'s own stdio one in
/// `bin/model_mcp.dart` — a [ModelMcpServer] is built exactly the same way,
/// wired to a [StreamChannel] that happens to be backed by HTTP requests
/// instead of a pipe's stdin and stdout. Nothing here reaches into
/// [ModelSession] or [ModelMcpServer] to make either transport-aware.
///
/// **One JSON-RPC message per HTTP request, not a persistent duplex socket.**
/// `dart:io`'s [HttpServer] gives a full-duplex byte stream only per
/// connection, and the protocol this wraps — [Peer] from `package:json_rpc_2`,
/// underneath [ModelMcpServer] — already frames one message per element of a
/// [StreamChannel]. A `POST` carrying one request or notification, answered
/// with the one reply that request produced (or, for a notification, no body
/// at all) is the smallest transport that satisfies that framing without
/// hand-rolling chunked duplex streaming for a local, one-client, ordinarily-
/// synchronous session. What this cannot do — and what a person driving this
/// same server over stdio does not get either, since nothing here registers
/// resources or logging that would need one — is push a server-initiated
/// message with no request to answer; see [_PendingReplies]'s own doc
/// comment.
///
/// **127.0.0.1 only, always** — never [InternetAddress.anyIPv4]. `mcp-13n`'s
/// row names this as a real requirement, not a style preference: a project
/// open in this session is a file an agent can read, write, undo and export,
/// and the only thing standing between that and anyone else on the same
/// network is this binding staying loopback-only. [start] does not take an
/// address parameter for exactly that reason — there is nothing here for a
/// caller to widen.
///
/// **A random token, minted per server and required on every request.**
/// Loopback-only keeps this off the network, not off every other process on
/// the same machine — anything else running as this user could otherwise
/// reach a project no dialog ever asked it to open. [start] accepts every
/// request whose `Authorization: Bearer <token>` header or `?token=` query
/// parameter carries the token it minted, and nothing else.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:stream_channel/stream_channel.dart';

import 'model_server.dart';
import 'model_session.dart';

/// A [ModelMcpServer] listening on `127.0.0.1`, for [ModelHttpServer.start].
///
/// One instance owns one HTTP socket and one [ModelMcpServer] wired to it —
/// mirroring `bin/model_mcp.dart`'s one process, one [ModelSession], except
/// the process here is the GUI, already running for a person, and this is an
/// extra way in beside the window.
final class ModelHttpServer {
  ModelHttpServer._(
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

  /// Binds `127.0.0.1:$port` — `0` (the default) picks any free port, which
  /// is what a caller that only ever reads [port] back out and writes it to
  /// the session file wants; a fixed `--mcp-port` value is for a caller (a
  /// script waiting on a known port) that would rather fail loudly on
  /// collision than silently bind elsewhere.
  ///
  /// [token] is minted internally when omitted — the only case any real
  /// caller needs; a caller passing one in is a test that wants to know it
  /// ahead of time.
  static Future<ModelHttpServer> start({
    required ModelSession session,
    int port = 0,
    String? token,
  }) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
    );
    final String actualToken = token ?? _randomToken();

    // The channel [ModelMcpServer] is built on. Its own [Peer] reads
    // [incoming.stream] and writes replies to [outgoing.sink] — precisely
    // the shape `stdioChannel` gives the stdio server, minus the newline
    // framing, since an HTTP body is already one message with no separator
    // needed.
    final StreamController<String> incoming = StreamController<String>();
    final StreamController<String> outgoing = StreamController<String>();

    // Every reply (or server-to-client request, though this server never
    // sends one) [Peer] writes is matched back to the HTTP request that is
    // still waiting on it by JSON-RPC `id` — not by arrival order, so an
    // agent that ever pipelines two calls without waiting still gets each
    // reply on the right connection. A message with no `id` is a
    // notification travelling server-to-client; nothing here has an open
    // connection to put it on, so it is dropped rather than queued forever —
    // the same nothing-to-push-it-to gap [start]'s own doc comment names.
    final _PendingReplies pending = _PendingReplies();
    outgoing.stream.listen((String message) {
      final Object? id = _idOf(message);
      if (id != null) pending.resolve(id, message);
    });

    ModelMcpServer(
      StreamChannel<String>(incoming.stream, outgoing.sink),
      session: session,
    );

    final ModelHttpServer result = ModelHttpServer._(
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
      // A reply already in flight ([response.write] above) has committed the
      // status line — setting one again here would throw a second error out
      // of a handler already failing on its first, so this is best-effort.
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

  /// Closes the socket and the [ModelMcpServer] wired to it. Does not touch
  /// the session file — a caller that wrote one owns removing it too, since
  /// only it knows whether another server still points at the same file.
  Future<void> close() async {
    await _server.close(force: true);
    await _peerIncoming.close();
    await _peerOutgoing.close();
  }
}

/// Matches a [Peer]'s replies back to the HTTP request awaiting each one, by
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

/// Where this GUI's own running [ModelHttpServer] can be found, written by
/// [writeMcpSessionFile] beside the app's existing session state — this
/// package stays plain Dart (`flutter3d_model_mcp`'s own pubspec says why:
/// no build here may depend on the Flutter SDK), so it takes the directory
/// as a plain path rather than resolving `apps/flutter3d_modeler`'s own
/// per-platform application-support directory itself. The caller wiring
/// `--mcp-port` into the GUI already has that directory, beside the autosave
/// slot `AutosaveController` writes into.
///
/// Written after the socket is already bound, since [port] and [token] both
/// come from the running [ModelHttpServer] — a session file naming a port
/// nothing is listening on yet would race whatever reads it. Synchronous,
/// matching every other write in this repository's own session/autosave
/// path (`FileBinaryStorage.write`, `ModelSession.save`) — a file this small
/// is not worth an event-loop round trip for.
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
