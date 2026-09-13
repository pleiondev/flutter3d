/// `ai-00`: a shooter level an agent can play blind, over MCP.
///
/// See `pubspec.yaml` for why this server needs Flutter — unlike
/// `flutter3d_editor_mcp` and `flutter3d_model_mcp` — and speaks its
/// protocol over a socket rather than over literal stdio.
library;

export 'src/playtest.dart';
export 'src/sim_renderer.dart';
export 'src/sim_server.dart';
export 'src/sim_session.dart';
export 'src/sim_tools.dart';
