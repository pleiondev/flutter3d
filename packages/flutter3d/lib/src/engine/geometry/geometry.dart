/// CPU-side geometry layer: vertex layouts, mesh data and shape generators.
///
/// Nothing here depends on a graphics backend, so it is testable without a GPU
/// — and, because `dart:ui` does not exist in a standalone VM, compilable by
/// `dart compile exe`. That is what `tool/bench/bench.dart` needs in order to
/// measure this layer through the same AOT pipeline a release build uses.
///
/// **`device_mesh.dart` is deliberately not exported here.** It is the rest of
/// the geometry layer by subject matter, and it holds the two types that have
/// met a device — so exporting it would put `GraphicsDevice`, and through it
/// `package:flutter/widgets.dart`, behind every import of this file. It went
/// that way once; see `device_mesh.dart` for what it cost. Consumers that
/// upload meshes import it directly, and `flutter3d.dart` exports both, so the
/// package's public surface does not know the two files apart.
library;

export 'box_shapes.dart';
export 'lathe_shape.dart';
export 'mesh_builder.dart';
export 'mesh_data.dart';
export 'mesh_geometry.dart';
export 'mesh_tangents.dart';
export 'revolved_shapes.dart';
export 'shape.dart';
export 'vertex_layout.dart';
