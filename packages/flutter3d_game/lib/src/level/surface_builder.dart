import 'dart:typed_data';

import 'brush_surface.dart';

/// Accumulates one material's triangles.
///
/// An implementation detail of [BrushGeometry]: the mutable, growable form a
/// [BrushSurface] passes through while its faces are being emitted, before it
/// is frozen into typed arrays by [finish].
final class SurfaceBuilder {
  SurfaceBuilder(this.material, {required this.castsShadow});

  final String material;
  final bool castsShadow;
  final List<double> _positions = <double>[];
  final List<double> _normals = <double>[];
  final List<double> _texcoords = <double>[];
  final List<double> _tangents = <double>[];
  final List<int> _indices = <int>[];

  int get vertexCount => _positions.length ~/ 3;
  bool get isNotEmpty => _indices.isNotEmpty;

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
    double v,
  ) {
    _positions.addAll(<double>[x, y, z]);
    _normals.addAll(<double>[nx, ny, nz]);
    _texcoords.addAll(<double>[u, v]);
    _tangents.addAll(<double>[tx, ty, tz, -1.0]);
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

  BrushSurface finish() => BrushSurface(
        material: material,
        castsShadow: castsShadow,
        positions: Float32List.fromList(_positions),
        normals: Float32List.fromList(_normals),
        texcoords: Float32List.fromList(_texcoords),
        tangents: Float32List.fromList(_tangents),
        indices: Uint32List.fromList(_indices),
      );
}
