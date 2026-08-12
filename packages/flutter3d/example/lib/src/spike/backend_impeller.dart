/// The Impeller backend, on the platforms that have it.
library;

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';

/// Builds the device this application draws through.
///
/// [width] and [height] are ignored here: Impeller renders into textures the
/// engine allocates and Flutter composites the result, so there is no surface
/// to size. The WebGL implementation needs them, because there the surface is a
/// canvas it creates itself.
GraphicsDevice createBackend({required int width, required int height}) =>
    GpuRenderBackend.create();

/// What to call this build in a diagnostic.
const String kBackendName = 'impeller';
