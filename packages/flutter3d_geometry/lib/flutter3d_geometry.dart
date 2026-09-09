/// CPU-side geometry: vertex layouts, mesh data, shape generators and the ray
/// arithmetic that reads them.
///
/// **A package rather than a directory, because a program with no Flutter SDK
/// has to be able to say `MeshData`.** Everything here was `flutter3d/lib/src/
/// engine/geometry` and `engine/math`, and everything here already named
/// Flutter nowhere at all — but `flutter3d` depends on the Flutter SDK, so a
/// plain `dart pub get` of anything that reached for this vocabulary through
/// the engine resolved a Flutter dependency it could not use. A modeller's
/// core, the tool an agent speaks to, and a bench compiled by `dart compile
/// exe` all want the same twelve files and none of them wants a widget.
/// `flutter3d` exports this package whole, so the engine's public surface is
/// unchanged by the move.
///
/// **`device_mesh.dart` stayed behind, and it is the line the split was made
/// along.** It is the rest of the geometry layer by subject matter, and it
/// holds the two types that have met a device — `GraphicsDevice`, and through
/// it `package:flutter/widgets.dart`. It stays in `flutter3d`, which is the
/// package that may name those. Consumers that upload meshes import it from
/// there, and `flutter3d.dart` exports both, so an application does not know
/// the two files apart.
library;

export 'src/box_shapes.dart';
export 'src/intersections.dart';
export 'src/lathe_shape.dart';
export 'src/mesh_builder.dart';
export 'src/mesh_data.dart';
export 'src/mesh_geometry.dart';
export 'src/mesh_tangents.dart';
export 'src/morph_blend.dart';
export 'src/morph_texture.dart';
export 'src/revolved_shapes.dart';
export 'src/shape.dart';
export 'src/triangle_bvh.dart';
export 'src/vertex_layout.dart';
