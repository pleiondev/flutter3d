/// Where a snapshot's camera stands and what it looks at.
///
/// `ModelProject` carries no camera of its own — `doc-03`'s own shape is
/// `{profile, objects, materials, images, skeletons, clips, nextId}`, and a
/// live viewport's `CameraNode` is `ModelerStage`'s, not the document's. A
/// snapshot needs a view all the same, so [RenderPreset] states one rather
/// than inventing a "default camera" a caller would have to know to override.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

/// A camera pose, described as a value rather than as a live [CameraNode] —
/// [RenderSnapshotJob] builds its own node from this once per tile, on its
/// own [CpuDevice], and a node built on one device cannot draw on another.
final class SnapshotCamera {
  const SnapshotCamera({
    required this.position,
    required this.target,
    this.up,
    this.projection = const PerspectiveProjection(),
  });

  /// Eye position, in world space.
  final Vector3 position;

  /// What the camera looks at. Together with [position] this is a look-at
  /// pair, the same shape `CameraNode.lookAt` already takes.
  final Vector3 target;

  /// World up, or null for `CameraNode.lookAt`'s own default.
  final Vector3? up;

  /// How the camera's frustum maps onto the frame — perspective by default,
  /// but an orthographic turntable render asks for [OrthographicProjection]
  /// just as validly.
  final Projection projection;
}

/// What a [RenderSnapshotJob] is asked for — `pro-rn-02`'s own row.
///
/// **Not `RenderSettings` alone.** A live viewport already has a resolution —
/// its own window's — and never asks for more samples than one screen
/// pixel. A snapshot has neither: its resolution is whatever the export
/// dialog says, and supersampling is the one knob screen 12's own mockup
/// used to call "samples" before decision 2026-09-09 renamed it to what it
/// actually is. [settings] is everything a frame already knows how to be
/// asked for; the four fields beside it are what a snapshot adds on top.
final class RenderPreset {
  const RenderPreset({
    required this.width,
    required this.height,
    required this.camera,
    this.ssaa = 1,
    this.settings = const RenderSettings(),
    this.tilesX = 1,
    this.tilesY = 1,
    this.clearColor,
  }) : assert(width > 0 && height > 0, 'width and height must be positive'),
       assert(
         ssaa == 1 || ssaa == 2,
         'ssaa must be 1 or 2 — this row asks for exactly those two, and a '
         'tracer that would want more sits outside the plan (decision '
         '2026-09-09)',
       ),
       assert(tilesX > 0 && tilesY > 0, 'a grid needs at least one tile'),
       assert(
         width % tilesX == 0,
         'width must divide evenly by tilesX, or a tile would not be a '
         'whole number of pixels wide',
       ),
       assert(
         height % tilesY == 0,
         'height must divide evenly by tilesY, or a tile would not be a '
         'whole number of pixels tall',
       );

  /// The snapshot's own width, after any supersampling has already been
  /// resolved back down — the size the PNG this job returns is encoded at.
  final int width;

  final int height;

  final SnapshotCamera camera;

  /// 1 for no supersampling, 2 for a linear 2×2 supersample resolved back
  /// down to [width] × [height] — `pro-rn-02`'s own "SSAA ×1/×2".
  final int ssaa;

  /// The frame-graph passes to run, and everything else a frame already
  /// takes a setting for — bloom, shadows, ambient occlusion, reflections.
  /// Reused as-is rather than narrowed, since a snapshot is still one frame
  /// and `pro-eng-05`'s `FrameResult.passes` already reports which of them
  /// this settings value actually kept.
  final RenderSettings settings;

  /// The grid a large snapshot renders as, one tile at a time — `pro-eng-04`'s
  /// own `TiledProjection`, stitched afterwards. `(1, 1)` — the default — is
  /// one tile the size of the whole frame, which is the same code path with
  /// nothing to stitch.
  final int tilesX;
  final int tilesY;

  final Vector4? clearColor;
}
