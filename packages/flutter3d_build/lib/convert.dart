/// Conversion as a library: [convertFiles] takes the bytes of an upload or
/// of an unpacked Unity, Godot or USD bundle and returns the engine's files
/// — `.f3d`, `.fmat`, `.f3dmat`, level documents with prefabs — with a
/// report of what mapped, what was approximated and what was dropped.
///
/// Plain Dart: no Flutter, and no external program. FBX, `.blend` and
/// binary USD need one, and are reported as unsupported here; the
/// `flutter3d convert` command line runs them when they are installed.
library;

export 'src/build_exceptions.dart' show SourceFormatException;
export 'src/convert.dart' show TextureFamily;
export 'src/convert/context.dart' show ModelSettings;
export 'src/convert/in_memory.dart'
    show ConversionResult, ConversionTarget, convertFiles;
export 'src/convert/report.dart';
