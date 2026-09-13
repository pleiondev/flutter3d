/// The same [ModelMcpServer], reached over a local HTTP socket instead of
/// stdin/stdout — `mcp-13n`'s row: the GUI keeps one live [ModelSession] a
/// person is editing in a window, and hands an agent the same session rather
/// than a second, disconnected one a headless process would have to reopen
/// from disk.
///
/// **The transport is `flutter3d_mcp_kit`'s [LoopbackMcpServer]** — loopback
/// only, a token per server, one JSON-RPC message per request; see that file
/// for why each. What is here is only which server it serves.
library;

import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';

import 'model_server.dart';
import 'model_session.dart';

export 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart'
    show deleteMcpSessionFile, writeMcpSessionFile;

/// A [ModelMcpServer] listening on `127.0.0.1`, for [ModelHttpServer.start].
///
/// One instance owns one HTTP socket and one [ModelMcpServer] wired to it —
/// mirroring `bin/model_mcp.dart`'s one process, one [ModelSession], except
/// the process here is the GUI, already running for a person, and this is an
/// extra way in beside the window.
final class ModelHttpServer {
  ModelHttpServer._(this._loopback);

  final LoopbackMcpServer _loopback;

  /// The token every request must present — write this into the session file
  /// ([writeMcpSessionFile]) so whatever starts this can hand it to an agent.
  String get token => _loopback.token;

  /// The port this bound to — the one to put in the session file.
  int get port => _loopback.port;

  /// Binds `127.0.0.1:$port` and serves [session] there. See
  /// [LoopbackMcpServer.start] for [port] and [token].
  static Future<ModelHttpServer> start({
    required ModelSession session,
    int port = 0,
    String? token,
  }) async => ModelHttpServer._(
    await LoopbackMcpServer.start(
      serve: (channel) => ModelMcpServer(channel, session: session),
      port: port,
      token: token,
    ),
  );

  /// Closes the socket and the [ModelMcpServer] wired to it. Does not touch
  /// the session file — a caller that wrote one owns removing it too.
  Future<void> close() => _loopback.close();
}
