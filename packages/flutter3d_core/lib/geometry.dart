/// CPU-side geometry: vertex layouts, mesh data, shape generators and the ray
/// arithmetic that reads them.
///
/// **A library of `flutter3d_core`, importable on its own.** A modeller's
/// editable mesh, the tool an agent speaks to and a bench compiled by `dart
/// compile exe` all want to say `MeshData` without the renderer, and a caller
/// that imports only this library gets only this library. It was
/// `flutter3d_geometry` until the package boundary turned out to protect
/// nothing a library does not.
///
/// **`DeviceMesh` is not here.** It is the rest of the geometry layer by
/// subject matter, but it holds the one type that has met a device, so it
/// lives with the renderer (`src/engine/geometry/device_mesh.dart`) and
/// `flutter3d_core.dart` exports both.
library;

export 'src/geometry/box_shapes.dart';
export 'src/geometry/intersections.dart';
export 'src/geometry/lathe_shape.dart';
export 'src/geometry/mesh_builder.dart';
export 'src/geometry/mesh_data.dart';
export 'src/geometry/mesh_geometry.dart';
export 'src/geometry/mesh_tangents.dart';
export 'src/geometry/morph_blend.dart';
export 'src/geometry/morph_texture.dart';
export 'src/geometry/polyline_shape.dart';
export 'src/geometry/revolved_shapes.dart';
export 'src/geometry/shape.dart';
export 'src/geometry/triangle_bvh.dart';
export 'src/geometry/vertex_cache_optimizer.dart';
export 'src/geometry/vertex_layout.dart';
