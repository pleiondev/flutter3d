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
import 'render_tool.dart' show ModelPictureTool;

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
  ///
  /// [extraTools] is [ModelMcpServer]'s own door, reachable only from here:
  /// the GUI application this socket is for is the one caller that has UI
  /// tools (`ui.setMode` and the rest, `mcp-16d`) to offer beside the
  /// ordinary document ones — `bin/model_mcp.dart`'s headless server never
  /// passes any, which is what keeps them out of that server's own
  /// `tools/list`.
  ///
  /// [onToolCall] is `tut-16`'s own door: screen 26's own tool-call feed —
  /// the GUI wants to know about every call an agent makes over this
  /// socket, the instant it answers, so [ModelMcpServer.onCall] is threaded
  /// straight through rather than this class watching calls a second way.
  static Future<ModelHttpServer> start({
    required ModelSession session,
    int port = 0,
    String? token,
    List<ModelPictureTool> extraTools = const <ModelPictureTool>[],
    void Function(
      String toolName,
      Map<String, Object?> arguments,
      PictureAnswer answer,
      Duration elapsed,
    )?
    onToolCall,
  }) async => ModelHttpServer._(
    await LoopbackMcpServer.start(
      serve: (channel) => ModelMcpServer(
        channel,
        session: session,
        extraTools: extraTools,
        onCall: onToolCall,
      ),
      port: port,
      token: token,
    ),
  );

  /// Closes the socket and the [ModelMcpServer] wired to it. Does not touch
  /// the session file — a caller that wrote one owns removing it too.
  Future<void> close() => _loopback.close();
}
