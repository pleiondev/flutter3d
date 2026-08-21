/// Which backend this build draws through.
///
/// One, and no conditional: a project made from a template is a desktop project
/// until somebody decides otherwise, and the two-file conditional import the
/// three games carry exists because they ship to a browser as well. Adding that
/// back is two files and a line in `pubspec.yaml`, and the games are the worked
/// example.
library;

export 'package:flutter3d_impeller/flutter3d_impeller.dart'
    show GpuRenderBackend;
