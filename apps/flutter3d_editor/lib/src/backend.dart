/// Which backend this build draws through.
///
/// **One, and no conditional.** The other three applications choose between
/// Impeller and WebGL at compile time because they ship to a browser as well as
/// to a desktop. This one opens a file, changes it and writes it back over
/// itself, which a browser will not do — so there is no web build to choose
/// for, and a `backend_web.dart` here would be a file that exists to be
/// unreachable.
library;

export 'package:flutter3d_impeller/flutter3d_impeller.dart'
    show GpuRenderBackend;
