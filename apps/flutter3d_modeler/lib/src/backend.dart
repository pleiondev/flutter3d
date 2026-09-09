/// Which backend this build draws through.
///
/// **Through `flutter3d_backend`, not by naming one**, for the reason the
/// template's own note gives: `openDevice` is a compile-time choice between
/// Impeller and WebGL *and* the run-time fallback to the software rasteriser
/// when flutter_gpu will not start. A modeller that named a backend would be a
/// modeller that does not open in a browser — and the browser is a platform of
/// the first version here rather than a later one.
library;

export 'package:flutter3d_app/flutter3d_app.dart' show openDevice;
