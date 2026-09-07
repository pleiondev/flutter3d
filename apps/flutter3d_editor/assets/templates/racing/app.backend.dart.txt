/// Which backend this build draws through.
///
/// **Through `flutter3d_backend`, not by naming one.** This used to export
/// `GpuRenderBackend` directly, with a written argument for it: a scaffolded
/// project is a desktop project until somebody decides otherwise, and the
/// conditional import the three games carry exists because they ship to a
/// browser too.
///
/// The argument covered the web and missed the other half. `openDevice` is not
/// only a compile-time choice between Impeller and WebGL — it is also the
/// *runtime* fallback to the software rasteriser when flutter_gpu will not
/// start, which happens on a machine whose driver refuses Impeller and on a
/// build whose shader bundle is stale. Naming one backend here means a
/// scaffolded project meets that as a window that draws nothing, which is the
/// failure this repository's own architecture document opens by describing.
///
/// One line, and the web build comes free with it.
library;

export 'package:flutter3d_app/flutter3d_app.dart' show openDevice;
