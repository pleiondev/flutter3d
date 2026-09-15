/// Wires a weight-paint brush's pointer-down/move/up to `PaintWeights` —
/// T4.1's own `history.beginTransaction()` / one command per move /
/// `endTransaction()`, the UI half that command was left unwired for.
///
/// **One transaction per drag, the same shape `transform_session.dart`
/// already gives a gizmo drag.** The transaction opens on the first sample
/// and closes on the pointer going up; every sample in between runs its own
/// `PaintWeights` through `ModelHistory.run`, which folds into the open
/// transaction rather than pushing a step of its own — `history.dart`'s own
/// doc comment describes exactly this shape, and `weight_paint_session_test.
/// dart`'s own "one drag, one step" pins it directly against this class.
///
/// **The posed surface is this class's own, not the caller's.** Built once
/// on [WeightPaintSession.pointerDown] from the engine's live, posed
/// skeleton — `brush_hit.dart`'s own reason — and read by every
/// [WeightPaintSession.pointerMove] after it; a caller never sees a
/// `TriangleBvh` at all.
library;

import 'dart:ui' show Offset;

import 'package:flutter3d/flutter3d.dart' show Skeleton;
import 'package:flutter3d_geometry/flutter3d_geometry.dart' show TriangleBvh;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'brush_hit.dart';
import 'element_picking.dart' show PickingView;
import 'modeler_cubit.dart';
import 'staging.dart';
import 'weight_mirror.dart';

/// Which of `weights.paint`/`weights.assign` is armed, read off
/// [ModelerReady.tool] — `PaintWeights` itself calls this `mode`; the rail's
/// own two ids (`ui/tools.dart`) are what a stroke actually arms.
PaintWeightsMode paintWeightsModeOf(String? tool) =>
    tool == 'weights.assign' ? PaintWeightsMode.assign : PaintWeightsMode.paint;

/// One brush drag's own state: the posed surface it hit-tests against, and
/// which object/skeleton/joint the stroke it opened is for.
class WeightPaintSession {
  WeightPaintSession({
    required this.cubit,
    required this.history,
    required this.stage,
  });

  final ModelerCubit cubit;

  /// The current document — a callback, not a held reference, for the same
  /// reason `TransformSession.history` is one.
  final ModelHistory Function() history;

  /// The current stage — read for [ModelerStage.sync]'s own live, posed
  /// [Skeleton], which is what a bent [BendSliderBar] pose actually moves.
  final ModelerStage Function() stage;

  TriangleBvh? _surface;
  int? _objectId;
  int? _skeletonIndex;
  int? _joint;

  /// Whether a stroke is currently open — a transaction is on the history.
  bool get isActive => _surface != null;

  /// Pointer went down: builds the posed surface fresh from the live engine
  /// skeleton, opens the transaction, and paints the first sample if the ray
  /// lands on the mesh.
  ///
  /// Answers the vertex nearest the hit, for a caller to show its
  /// influences — or null when the target has no paintable mesh, no bound
  /// skeleton, no such joint, or the first sample's own ray missed the mesh
  /// entirely, in which case nothing opened at all.
  int? pointerDown({
    required PickingView view,
    required Offset at,
    required int objectId,
    required int skeletonIndex,
    required int joint,
    required double radiusPixels,
    required double strength,
    required PaintWeightsMode mode,
    required bool mirror,
    required bool normalize,
  }) {
    if (isActive) return null;
    final target = _resolve(
      objectId: objectId,
      skeletonIndex: skeletonIndex,
      joint: joint,
    );
    if (target == null) return null;

    _surface = buildPosedBrushSurface(
      mesh: target.mesh,
      skeleton: target.engineSkeleton,
      projectSkeleton: target.projectSkeleton,
    );
    _objectId = objectId;
    _skeletonIndex = skeletonIndex;
    _joint = joint;

    history().beginTransaction();
    final int? hit = _paint(
      view: view,
      at: at,
      radiusPixels: radiusPixels,
      strength: strength,
      mode: mode,
      mirror: mirror,
      normalize: normalize,
    );
    // A first sample that hit nothing still leaves the transaction open —
    // `endTransaction` on an empty one costs nothing and leaves no step, per
    // its own doc comment — so a drag that starts in empty space and only
    // reaches the mesh a few pixels later still becomes one undo step.
    return hit;
  }

  /// One more sample of an already-open stroke. A no-op, answering null,
  /// when nothing is open — a move reported after the ray missed on the way
  /// down and nothing ever started.
  int? pointerMove({
    required PickingView view,
    required Offset at,
    required double radiusPixels,
    required double strength,
    required PaintWeightsMode mode,
    required bool mirror,
    required bool normalize,
  }) {
    if (!isActive) return null;
    return _paint(
      view: view,
      at: at,
      radiusPixels: radiusPixels,
      strength: strength,
      mode: mode,
      mirror: mirror,
      normalize: normalize,
    );
  }

  /// Closes the transaction — one undo step for however many samples the
  /// drag made, `history.dart`'s own collapse. A no-op when nothing is open.
  void pointerUp() {
    if (!isActive) return;
    _surface = null;
    _objectId = null;
    _skeletonIndex = null;
    _joint = null;
    history().endTransaction();
  }

  int? _paint({
    required PickingView view,
    required Offset at,
    required double radiusPixels,
    required double strength,
    required PaintWeightsMode mode,
    required bool mirror,
    required bool normalize,
  }) {
    final TriangleBvh? surface = _surface;
    final int? objectId = _objectId;
    final int? skeletonIndex = _skeletonIndex;
    final int? joint = _joint;
    if (surface == null ||
        objectId == null ||
        skeletonIndex == null ||
        joint == null) {
      return null;
    }
    final hit = surface.raycast(view.rayThrough(at));
    if (hit == null) return null;

    final double radius = view.worldWidthAt(
      at,
      pixels: radiusPixels,
      distance: hit.distance,
    );
    // Valid by construction: `_resolve` already checked `skeletonIndex`
    // against `history().project.skeletons` before this session opened, and
    // the two stay fixed for the whole drag.
    final PaintMirror? mirrorArg = !mirror
        ? null
        : PaintMirror(
            axis: 0,
            jointMirror: jointMirrorMapByName(
              history().project,
              history().project.skeletons[skeletonIndex],
            ),
          );

    cubit.ran(
      PaintWeights(
        objectId: objectId,
        skeletonIndex: skeletonIndex,
        joint: joint,
        samples: <BrushSample>[BrushSample(center: hit.point, radius: radius)],
        strength: strength,
        mode: mode,
        mirror: mirrorArg,
        normalize: normalize,
      ),
    );
    return nearestVertexOfTriangle(surface, hit.triangle, hit.point);
  }

  ({EditMesh mesh, Skeleton engineSkeleton, ProjectSkeleton projectSkeleton})?
  _resolve({
    required int objectId,
    required int skeletonIndex,
    required int joint,
  }) {
    final ModelProject project = history().project;
    final List<ProjectSkeleton> skeletons = project.skeletons;
    if (skeletonIndex < 0 || skeletonIndex >= skeletons.length) return null;
    final ProjectSkeleton projectSkeleton = skeletons[skeletonIndex];
    if (!projectSkeleton.joints.contains(joint)) return null;
    final EditMesh? mesh = switch (project[objectId]?.geometry) {
      EditedGeometry(:final mesh) => mesh,
      _ => null,
    };
    if (mesh == null) return null;
    final Skeleton? engineSkeleton = stage().sync?.nodeOf(objectId)?.skeleton;
    if (engineSkeleton == null) return null;
    return (
      mesh: mesh,
      engineSkeleton: engineSkeleton,
      projectSkeleton: projectSkeleton,
    );
  }
}
