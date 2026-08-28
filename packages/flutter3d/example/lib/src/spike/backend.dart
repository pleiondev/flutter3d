/// Which backend this build talks to.
///
/// The example is the same application on both: the same scenes, the same
/// lights, the same golden definitions. Only the device differs, and this is
/// the one file that knows which.
///
/// Conditional because a backend package cannot merely be unused on the wrong
/// platform — `flutter3d_impeller` reaches `flutter_gpu`, which reaches
/// `dart:ffi`, which does not exist on the web. An import is enough to fail the
/// build, so the choice has to be made where imports are resolved.
///
/// That is a different case from choosing a backend at runtime, which this
/// engine deliberately does not do by import: a device arrives at
/// `Renderer.create` as a value, and a test hands it a fake. Here there is no
/// third implementation wanted and no fake displaced — there is a library that
/// cannot be compiled for this target.
library;

export 'backend_impeller.dart' if (dart.library.js_interop) 'backend_web.dart';
