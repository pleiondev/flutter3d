/// `tut-00`'s driven-screenshot pipeline: parse a scenario, call the
/// modeler's own MCP tools over `mcp-16d`'s loopback socket, and screenshot
/// the window they leave on screen. See `bin/shoot.dart` for the CLI this
/// library backs, and `tut-00` in `doc/model-editor-plan.md` for why.
library;

export 'src/mcp_client.dart';
export 'src/mcp_session.dart';
export 'src/scenario.dart';
export 'src/shoot_runner.dart';
export 'src/window_capture.dart';
