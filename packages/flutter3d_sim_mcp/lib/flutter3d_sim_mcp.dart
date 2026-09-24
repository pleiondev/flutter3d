/// Two servers over one level and one renderer.
///
/// `ai-00`: a level an agent can play blind, over MCP — of whatever game a
/// host hands the session as a `HeadlessGame` ([SimMcpServer]).
///
/// `par-02`: why a frame of it is wrong, without guessing — a headless frame
/// in one of the renderer's own debug views, the raw unclamped value of one
/// pixel, what the frame graph actually ran, and a scan for the first pixel
/// that is not finite ([DiagnosticMcpServer]). Genre-agnostic: its
/// `EntityRegistry` is a parameter nothing here fills in.
///
/// They were two packages with the same dependency closure, and a picture from
/// the first was already the second's `lit` frame.
///
/// See `pubspec.yaml` for why these servers need Flutter — unlike
/// `flutter3d_editor_mcp` and `flutter3d_model_mcp` — and speak their protocol
/// over a socket rather than over literal stdio.
library;

export 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart' show PictureAnswer;

export 'src/diagnostic_renderer.dart';
export 'src/diagnostic_server.dart';
export 'src/diagnostic_session.dart' show describePass;
export 'src/diagnostic_tools.dart';
export 'src/playtest.dart';
export 'src/reading_predicate.dart';
export 'src/sim_renderer.dart';
export 'src/sim_server.dart';
export 'src/sim_session.dart';
export 'src/sim_tools.dart';
