/// Loading the core natively: nothing to do — P9, phase 12.
///
/// The hook built the core into the app, and the first call finds it; this
/// is here so that the code that starts a world reads the same natively and
/// in the browser.
library;

import 'dart:typed_data';

/// Where the browser fetches the core from; unused natively.
const String defaultPhysicsCoreUrl =
    'assets/packages/flutter3d_physics_native/web/f3d_physics.wasm';

/// Nothing natively: the core is in the app already.
Future<void> loadPhysicsCore({
  Uint8List? bytes,
  String url = defaultPhysicsCoreUrl,
}) async {}

/// Always, natively.
bool get physicsCoreLoaded => true;
