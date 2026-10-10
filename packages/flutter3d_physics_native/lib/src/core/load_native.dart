/// Loading the core natively: nothing to do — P9, phase 12.
///
/// The hook built the core into the app, and the first call finds it; this
/// is here so that the code that starts a world reads the same natively and
/// in the browser.
library;

import 'dart:typed_data';

/// Where the browser fetches the core and its worker from; unused natively.
const String defaultPhysicsCoreUrl =
    'assets/packages/flutter3d_physics_native/web/f3d_physics.wasm';
const String defaultPhysicsCoreThreadsUrl =
    'assets/packages/flutter3d_physics_native/web/f3d_physics_threads.wasm';
const String defaultPhysicsWorkerUrl =
    'assets/packages/flutter3d_physics_native/web/f3d_worker.js';

/// Nothing natively: the core is in the app already, and starts its own
/// threads when a world asks for them.
Future<void> loadPhysicsCore({
  Uint8List? bytes,
  String url = defaultPhysicsCoreUrl,
  int threads = 1,
  String threadsUrl = defaultPhysicsCoreThreadsUrl,
  String workerUrl = defaultPhysicsWorkerUrl,
}) async {}

/// Always, natively.
bool get physicsCoreLoaded => true;

/// The most threads a world can step on: natively as many as it asks for,
/// up to sixty-four.
int get physicsCoreThreads => 64;
