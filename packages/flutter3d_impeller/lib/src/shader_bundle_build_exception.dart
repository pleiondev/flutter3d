/// The one exception compiling the shader bundle throws, apart from the
/// compiling itself so the package's library can export it without reaching
/// `dart:io`.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ResourceException;

/// Thrown on any failure compiling the bundle — `hook/build.dart` wraps it as
/// a [BuildError][], `bin/build_shader_bundle.dart` prints it and exits
/// non-zero. Plain rather than a `package:hooks` type, because this file
/// has no reason to depend on hooks at all.
///
/// [BuildError]: https://pub.dev/documentation/hooks/latest/hooks/BuildError-class.html
///
/// When `impellerc` itself refused a stage, [cause] is the
/// `ShaderCompileException` read from what it said: the stage, the line and
/// column of each error and the source line, for a tool to point at.
final class ShaderBundleBuildException extends ResourceException {
  const ShaderBundleBuildException(this.message, {this.cause});
  @override
  final String message;
  @override
  final Object? cause;
  @override
  String toString() => message;
}
