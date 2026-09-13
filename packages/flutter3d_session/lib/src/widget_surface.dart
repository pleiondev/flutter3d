import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Matrix4;
import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'widget_surface_pipeline.dart';

/// `wg-01`: a live Flutter widget as a mesh in the 3D scene, the node
/// `WidgetSurfacePipeline`'s own docstring names as not yet built.
///
/// A [WidgetSurfacePipeline] draws to an offscreen canvas and takes a pointer
/// at a UV on it; this is the other half — a [MeshNode] carrying that canvas
/// as its [Material.albedo], sized and placed in world space, so the level
/// document can put a scrolling list or a text field on a wall the same way
/// it puts a torch on one.
final class WidgetSurface {
  WidgetSurface({
    required Widget child,
    required this.device,
    this.width = 1.0,
    this.height = 1.0,
    double pixelsPerMetre = 512.0,
    String? name,
  }) : pipeline = WidgetSurfacePipeline(
         child: child,
         width: (width * pixelsPerMetre).round(),
         height: (height * pixelsPerMetre).round(),
       ),
       node = MeshNode(
         DeviceMesh.upload(
           device,
           PlaneShape(width: width, depth: height).build(),
         ),
         Material(name: name, lighting: LightingModel.unlit),
         name: name,
       ) {
    // Stands the plane up and points its front — `PlaneShape`'s own normal,
    // +Y — down -Z at yaw nought, the same convention
    // `flutter3d_bridge`'s `ActorVisuals.yawFor` already documents for an
    // entity's forward direction. Verified by
    // `widget_surface_orientation_test.dart`, not only reasoned about: pitch
    // sign is exactly the kind of thing that reads right and draws backwards.
    node.setRotationYawPitchRoll(0.0, -math.pi / 2, 0.0);
  }

  /// Where the pipeline's frames are uploaded.
  final GraphicsDevice device;

  /// The widget's own render pipeline — `wg-00`, held rather than rebuilt.
  final WidgetSurfacePipeline pipeline;

  /// The mesh this surface draws onto. Add it to a [Scene] like any other
  /// node; nothing about it is special once it is placed.
  final MeshNode node;

  /// World-space size, metres.
  final double width;
  final double height;

  double _yaw = 0.0;

  /// Facing, about world Y — the same field an [EntityDef] already carries,
  /// so a level's `yaw` on a `widget_surface` entity needs no translation.
  double get yaw => _yaw;
  set yaw(double value) {
    _yaw = value;
    node.setRotationYawPitchRoll(value, -math.pi / 2, 0.0);
  }

  void setPosition(Vector3 at) => node.setPositionFrom(at);

  /// How many times the pipeline has actually redrawn — `wg-01`'s own
  /// diagnostic counter, the pipeline's [WidgetSurfacePipeline.redrawCount]
  /// read back through the node a game actually holds.
  int get redrawCount => pipeline.redrawCount;

  /// Whether anything has ever been uploaded — [pipeline] draws its very
  /// first frame inside its own constructor and is therefore not dirty on
  /// this call's first look at it (see [WidgetSurfacePipeline]'s own
  /// doc-comment), so a widget that never changes after that would upload
  /// nothing at all without this forcing the one exception.
  bool _uploaded = false;

  /// Runs the pipeline once and, if it drew a new frame — or this is the
  /// first call, uploading the frame the pipeline already drew for itself
  /// on construction — uploads that frame as the mesh's texture. Call once
  /// per game frame; a frame in which nothing inside the widget changed and
  /// which is not the first call costs one boolean check and nothing else,
  /// because [WidgetSurfacePipeline.redrawIfDirty] already is that cheap —
  /// `wg-00`'s own measurement is what this relies on rather than re-proves.
  Future<void> tick() async {
    final dirty = pipeline.redrawIfDirty();
    if (!dirty && _uploaded) return;
    _uploaded = true;
    final image = await pipeline.currentImage();
    try {
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null) return;
      final handle = device.createTextureFromPixels(
        width: image.width,
        height: image.height,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: pixels,
      );
      if (handle != null) node.material.albedo = handle;
    } finally {
      image.dispose();
    }
  }

  /// Where a world-space point on this surface's own plane lands in its
  /// pipeline's UV space, or `null` when the point is not on the plane
  /// (beyond [epsilon] out of its local Y) or falls outside its bounds.
  ///
  /// An [ui.Offset] rather than a [Vector2] because the only place this ever
  /// goes is [WidgetSurfacePipeline.dispatchAtUv], which already wants one —
  /// a caller raycasting a hit and handing the result straight to the
  /// pipeline should not need to convert between the two.
  ///
  /// **The exact inverse of how `PlaneShape` placed its own vertices**
  /// (`(u - 0.5) * width`, `(v - 0.5) * depth`), read back through the
  /// node's own [SceneNode.worldMatrix] rather than a second, hand-derived
  /// rotation — so this stays correct under whatever [yaw] is set to,
  /// without this class re-deriving the plane's own geometry.
  ///
  /// [epsilon] wants to be at least the half-thickness of whatever collision
  /// proxy a caller raycasts against: a proxy is usually thicker than this
  /// plane so a shot does not graze past it, and a hit on its near face
  /// therefore lands slightly off the plane's own `y = 0` even when it is
  /// squarely on the surface.
  ui.Offset? uvAt(Vector3 worldPoint, {double epsilon = 0.05}) {
    final inverse = Matrix4.copy(node.worldMatrix)..invert();
    final local = worldPoint.clone();
    inverse.transform3(local);
    if (local.y.abs() > epsilon) return null;
    final u = local.x / width + 0.5;
    // Flipped against `PlaneShape`'s own `v` (which runs with local Z, and
    // therefore with world Y once the plane is stood up): a pipeline's `v`
    // is top-down, screen fashion, so this makes a widget's own top edge
    // the physical top of the wall it is mounted on — the only reading a
    // level author could mean by "put this the right way up".
    final v = 0.5 - local.z / height;
    // A point exactly on an edge round-trips through the inverse matrix a
    // hair outside [0, 1] as often as not — this class's own tests hit
    // that on a plain corner, not an adversarial one — so the bound is
    // tested with a tolerance and the return value is clamped rather than
    // handed back a hair over 1.0 for a tap that was squarely on the edge.
    const tolerance = 1e-4;
    if (u < -tolerance || u > 1.0 + tolerance) return null;
    if (v < -tolerance || v > 1.0 + tolerance) return null;
    return ui.Offset(u.clamp(0.0, 1.0), v.clamp(0.0, 1.0));
  }

  /// Releases the pipeline's element tree and takes the mesh out of whatever
  /// scene it is in — the two things a `dispose()` on either half already
  /// does on its own, done together because nothing here outlives its mesh.
  void dispose() {
    pipeline.dispose();
    node.removeFromParent();
  }
}
