/// `pro-sc-08`'s pointer half: a sculpting drag turned into `SculptStroke`s
/// inside one transaction — the same shape `weight_paint_session.dart` gives
/// the weight brush, and for the same reason.
///
/// **A drag is one undo step.** The transaction opens on the pointer going
/// down and closes on it coming up; every sample in between runs its own
/// one-point `SculptStroke` through `ModelHistory.run`, which folds into the
/// open transaction rather than pushing a step of its own. A hundred pointer
/// samples are one ⌘Z, which is `ui-29`'s own "a stroke — a transaction".
///
/// **The surface is built once, at the start of the drag, and never refitted
/// mid-stroke.** A tree rebuilt as the vertices move would let a brush chase
/// the surface it is pushing: each sample hits geometry the sample before it
/// displaced, and a stroke held in one place digs rather than settling. So
/// the ray is cast against the shape as it was when the pointer went down —
/// the stroke plane every sculpting tool locks for exactly this reason — and
/// `weight_paint_session.dart`'s own doc comment says the same thing about
/// its posed snapshot.
///
/// **World in, object out.** A viewport ray is in world space and
/// `SculptStroke.points` are in the mesh's own, so the surface is built from
/// world positions and the hit is carried back through the object's inverse
/// world transform. Getting this wrong is invisible on a model at the origin
/// and obvious on one that has been moved, which is why it is a line of its
/// own rather than an assumption.
library;

import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter3d_core/geometry.dart' show TriangleBvh;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

import 'element_picking.dart' show PickingView;
import 'modeler_cubit.dart';

/// Which brush a sculpt rail tool id arms — `sculpt.draw` to [BrushKind.draw]
/// and so on, with anything else reading as the draw brush.
///
/// **A table rather than a parse.** `id.split('.').last` would turn a
/// misspelt or renamed id into a `BrushKind` that does not exist and throw
/// at the call site instead of here; a switch says which eight ids exist and
/// has somewhere to put the ninth when there is one.
BrushKind brushKindOf(String? tool) => switch (tool) {
  'sculpt.clay' => BrushKind.clay,
  'sculpt.smooth' => BrushKind.smooth,
  'sculpt.flatten' => BrushKind.flatten,
  'sculpt.inflate' => BrushKind.inflate,
  'sculpt.grab' => BrushKind.grab,
  'sculpt.pinch' => BrushKind.pinch,
  'sculpt.crease' => BrushKind.crease,
  _ => BrushKind.draw,
};

/// The rail tool id that arms [kind] — [brushKindOf]'s own other direction,
/// for a palette button that arms a brush by pressing it.
String sculptToolOf(BrushKind kind) => 'sculpt.${kind.name}';

/// One sculpting drag: the surface it hit-tests against, the object it is
/// sculpting, and the transaction it opened.
class SculptSession {
  SculptSession({required this.cubit, required this.history});

  final ModelerCubit cubit;

  /// The current document — a callback rather than a held reference, the
  /// same reason `WeightPaintSession.history` is one.
  final ModelHistory Function() history;

  TriangleBvh? _surface;
  int? _objectId;
  Matrix4? _toObject;

  /// The point the last sample landed on, in the mesh's own space — what
  /// `grab` needs as its previous centre, and what a caller draws a cursor
  /// at. Null between strokes.
  Vector3? get lastPoint => _lastPoint;
  Vector3? _lastPoint;

  /// Whether a stroke is open: a transaction is on the history.
  bool get isActive => _surface != null;

  /// Pointer went down. Builds the surface, opens the transaction and takes
  /// the first sample. Answers whether the stroke actually started — false
  /// when there is nothing under the pointer to sculpt.
  bool pointerDown({
    required PickingView view,
    required Offset at,
    required int objectId,
    required BrushKind kind,
    required double radiusPixels,
    required double strength,
    required BrushFalloff falloff,
    required bool symmetryX,
    required bool inverted,
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
    return _sculpt(
      view: view,
      at: at,
      kind: kind,
      radiusPixels: radiusPixels,
      strength: strength,
      falloff: falloff,
      symmetryX: symmetryX,
      inverted: inverted,
    );
  }

  /// One more sample of an open stroke. A no-op when none is.
  bool pointerMove({
    required PickingView view,
    required Offset at,
    required BrushKind kind,
    required double radiusPixels,
    required double strength,
    required BrushFalloff falloff,
    required bool symmetryX,
    required bool inverted,
  }) {
    if (!isActive) return false;
    return _sculpt(
      view: view,
      at: at,
      kind: kind,
      radiusPixels: radiusPixels,
      strength: strength,
      falloff: falloff,
      symmetryX: symmetryX,
      inverted: inverted,
    );
  }

  /// Closes the transaction — one step for however many samples the drag
  /// made. A no-op when nothing is open.
  void pointerUp() {
    if (!isActive) return;
    _surface = null;
    _objectId = null;
    _toObject = null;
    _lastPoint = null;
    history().endTransaction();
  }

  bool _sculpt({
    required PickingView view,
    required Offset at,
    required BrushKind kind,
    required double radiusPixels,
    required double strength,
    required BrushFalloff falloff,
    required bool symmetryX,
    required bool inverted,
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
    final Vector3 point = toObject.transformed3(Vector3.copy(hit.point));
    // `grab` drags from where the last sample was, and a stroke's very first
    // sample has nowhere to drag from — so the first point of a grab moves
    // nothing, the same way a drag of zero length does.
    final Vector3? previous = _lastPoint;
    _lastPoint = point;

    cubit.ran(
      SculptStroke(
        objectId: objectId,
        kind: kind,
        radius: radius,
        // The inverted end of a stylus is the same stroke with the sign
        // turned round — `InputPolicy`'s own `ToolStroke.erase`, which every
        // drawing application on every platform already agrees means this.
        strength: inverted ? -strength : strength,
        points: <Vector3>[
          if (previous != null && kind == BrushKind.grab) previous,
          point,
        ],
        falloff: falloff,
        symmetryX: symmetryX,
      ),
    );
    return true;
  }

  /// A triangle tree over [mesh]'s own surface, in world space.
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
