/// Why is the frame wrong, without guessing — `par-02`.
///
/// A headless frame in one of the renderer's own debug views, the raw
/// unclamped value of one pixel in it, what the frame graph actually ran,
/// and a scan for the first pixel that is not finite.
library;

export 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart' show PictureAnswer;

export 'src/diagnostic_renderer.dart';
export 'src/diagnostic_server.dart';
export 'src/diagnostic_session.dart' show describePass;
export 'src/diagnostic_tools.dart';
