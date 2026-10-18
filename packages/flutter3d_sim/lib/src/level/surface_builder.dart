import 'dart:typed_data';

import 'brush.dart';
import 'brush_surface.dart';

/// Accumulates one material's triangles.
///
/// An implementation detail of [BrushGeometry]: the mutable, growable form a
/// [BrushSurface] passes through while its faces are being emitted, before it
/// is frozen into typed arrays by [finish].
final class SurfaceBuilder {
  /// An empty builder for [material]'s triangles, without lightmap
  /// coordinates unless [lightmapped].
  SurfaceBuilder(
    this.material, {
    required this.shadowCasting,
    this.drawOrder = 0,
    this.depthLayer = 0,
    this.lightmapped = false,
    this.brush,
  });

  /// The level material every triangle here is drawn with.
  final String material;

  /// How the finished surface takes part in the shadow pass.
  final ShadowCasting shadowCasting;

  /// [Brush.drawOrder] of every brush these triangles came from.
  final int drawOrder;

  /// The depth layer of every brush these triangles came from — see
  /// [Brush.depthLayer].
  final int depthLayer;

  /// The one brush these triangles belong to, when every brush is its own
  /// surface. See [BrushSurface.brush].
  final int? brush;

  /// Whether the vertices carry a second texture coordinate into the
  /// lightmap. See [BrushSurface.lightmapUvs].
  final bool lightmapped;

  final List<double> _positions = <double>[];
  final List<double> _normals = <double>[];
  final List<double> _texcoords = <double>[];
  final List<double> _tangents = <double>[];
  final List<double> _lightmapUvs = <double>[];
  final List<int> _indices = <int>[];

  /// Count of vertices added so far; the index the next one gets.
  int get vertexCount => _positions.length ~/ 3;

  /// Whether any triangle has been added.
  bool get isNotEmpty => _indices.isNotEmpty;

  /// Adds a vertex at ([x], [y], [z]) metres with normal ([nx], [ny],
  /// [nz]), tangent ([tx], [ty], [tz]) of handedness −1 and texture
  /// coordinate ([u], [v]). The lightmap coordinate is kept only when
  /// [lightmapped].
  void addVertex(
    double x,
    double y,
    double z,
    double nx,
    double ny,
    double nz,
    double tx,
    double ty,
    double tz,
    double u,
    double v, {
    double lightmapU = 0.0,
    double lightmapV = 0.0,
  }) {
    _positions.addAll(<double>[x, y, z]);
    _normals.addAll(<double>[nx, ny, nz]);
    _texcoords.addAll(<double>[u, v]);
    _tangents.addAll(<double>[tx, ty, tz, -1.0]);
    if (lightmapped) _lightmapUvs.addAll(<double>[lightmapU, lightmapV]);
  }

  /// One triangle over three corners added in order.
  void addTriangle(int first) {
    _indices.addAll(<int>[first, first + 1, first + 2]);
  }

  /// Two triangles over four corners added in order.
  void addQuad(int first) {
    _indices.addAll(<int>[
      first,
      first + 1,
      first + 2,
      first,
      first + 2,
      first + 3,
    ]);
  }

  /// The triangles so far, frozen into typed arrays.
  BrushSurface finish() => BrushSurface(
    material: material,
    shadowCasting: shadowCasting,
    drawOrder: drawOrder,
    depthLayer: depthLayer,
    positions: Float32List.fromList(_positions),
    normals: Float32List.fromList(_normals),
    texcoords: Float32List.fromList(_texcoords),
    tangents: Float32List.fromList(_tangents),
    lightmapUvs: lightmapped ? Float32List.fromList(_lightmapUvs) : null,
    indices: Uint32List.fromList(_indices),
    brush: brush,
  );
}
