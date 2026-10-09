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
final class ShaderBundleBuildException extends ResourceException {
  const ShaderBundleBuildException(this.message);
  @override
  final String message;
  @override
  String toString() => message;
}
