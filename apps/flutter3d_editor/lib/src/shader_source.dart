/// The shader bundle `--dart-define=shaders=` names, loaded and kept
/// current — on a desktop. See `ShaderWatch` for the loop.
///
/// **A browser build has none, and refuses a define rather than ignoring
/// it.** Watching a bundle means asking a file for its modification time
/// twice a second, and a page has no file to ask; an editor asked to draw
/// with a bundle and drawing without it would look like the bundle having no
/// effect, which is the one thing this loop exists to make impossible.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

export 'shader_source_io.dart'
    if (dart.library.js_interop) 'shader_source_web.dart';

/// A bundle that is drawn with, and the two things done with its watching.
typedef WatchedShaders = ({
  LoadedShaderLibrary library,
  void Function() start,
  void Function() dispose,
});
