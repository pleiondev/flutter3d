/// `pro-pt-05`'s pointer half: a texture-painting drag turned into
/// `PaintStroke`s inside one transaction — `sculpt_session.dart`'s own shape,
/// over the paint command instead of the sculpt one.
///
/// **A drag is one undo step**, the same rule every brush in this
/// application keeps.
///
/// **The surface is built once at the start of the drag.** Painting does not
/// move the surface, so unlike a sculpting stroke there is nothing for a
/// refit to catch up with — the tree is built once because building it per
/// sample would cost the mesh sixty times a second, not because the geometry
/// would drift.
library;

import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter3d_core/geometry.dart' show TriangleBvh;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

import 'element_picking.dart' show PickingView;
import 'modeler_cubit.dart';

/// One painting drag.
class PaintSession {
  PaintSession({required this.cubit, required this.history});

  final ModelerCubit cubit;

  /// The current document — a callback rather than a held reference, the
  /// same reason `SculptSession.history` is one.
  final ModelHistory Function() history;

  TriangleBvh? _surface;
  int? _objectId;
  Matrix4? _toObject;

  /// Whether a stroke is open.
  bool get isActive => _surface != null;

  /// Pointer went down. Answers whether the stroke started — false when
  /// there is nothing under the pointer to paint.
  bool pointerDown({
    required PickingView view,
    required Offset at,
    required int objectId,
    required double radiusPixels,
    required List<double> colour,
    required double strength,
    required int layer,
    int? maskImage,
  }) {
    if (isActive) return false;
    final ModelProject project = history().project;
    final EditMesh? mesh = switch (project[objectId]?.geometry) {
      EditedGeometry(:final mesh) => mesh,
      _ => null,
    };
    if (mesh == null) return false;

    final Matrix4 toWorld = worldTransformOf(project, objectId);
    _surface = _surfaceOf(mesh, toWorld);
    _objectId = objectId;
    _toObject = Matrix4.inverted(toWorld);

    history().beginTransaction();
    return _paint(
      view: view,
      at: at,
      radiusPixels: radiusPixels,
      colour: colour,
      strength: strength,
      layer: layer,
      maskImage: maskImage,
    );
  }

  /// One more sample of an open stroke.
  bool pointerMove({
    required PickingView view,
    required Offset at,
    required double radiusPixels,
    required List<double> colour,
    required double strength,
    required int layer,
    int? maskImage,
  }) {
    if (!isActive) return false;
    return _paint(
      view: view,
      at: at,
      radiusPixels: radiusPixels,
      colour: colour,
      strength: strength,
      layer: layer,
      maskImage: maskImage,
    );
  }

  /// Closes the transaction — one step for the whole drag.
  void pointerUp() {
    if (!isActive) return;
    _surface = null;
    _objectId = null;
    _toObject = null;
    history().endTransaction();
  }

  bool _paint({
    required PickingView view,
    required Offset at,
    required double radiusPixels,
    required List<double> colour,
    required double strength,
    required int layer,
    int? maskImage,
  }) {
    final TriangleBvh? surface = _surface;
    final int? objectId = _objectId;
    final Matrix4? toObject = _toObject;
    if (surface == null || objectId == null || toObject == null) return false;
    final hit = surface.raycast(view.rayThrough(at));
    if (hit == null) return false;

    final double radius = view.worldWidthAt(
      at,
      pixels: radiusPixels,
      distance: hit.distance,
    );
    cubit.ran(
      PaintStroke(
        objectId: objectId,
        samples: <PaintSample>[
          PaintSample(
            centre: toObject.transformed3(Vector3.copy(hit.point)),
            radius: radius,
          ),
        ],
        colour: colour,
        layer: layer,
        strength: strength,
        maskImage: maskImage,
      ),
    );
    return true;
  }

  /// A triangle tree over [mesh]'s own surface, in world space — the same
  /// helper `SculptSession` keeps, repeated rather than shared because the
  /// two sessions have no other reason to know about each other.
  static TriangleBvh _surfaceOf(EditMesh mesh, Matrix4 toWorld) {
    final plan = MeshLayoutPlan()..build(mesh);
    final rows = plan.indices;
    final indices = Uint32List(rows.length);
    for (var i = 0; i < rows.length; i++) {
      indices[i] = plan.gpuVertexToVertex[rows[i]];
    }
    final positions = Float32List(mesh.vertexSlotCount * 3);
    final at = Vector3.zero();
    for (var v = 0; v < mesh.vertexSlotCount; v++) {
      if (!mesh.isVertexAlive(v)) continue;
      mesh.positionOf(v, at);
      toWorld.transform3(at);
      positions[v * 3] = at.x;
      positions[v * 3 + 1] = at.y;
      positions[v * 3 + 2] = at.z;
    }
    return TriangleBvh.fromArrays(positions, indices);
  }
}
