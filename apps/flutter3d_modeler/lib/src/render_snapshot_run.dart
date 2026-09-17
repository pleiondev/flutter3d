/// `pro-rn-04`'s own half of the render button: `pro-rn-02`'s tiled job,
/// run over the project the screen is showing.
///
/// **On a device of its own rather than the viewport's.** A snapshot is a
/// different size from the window and renders in tiles; borrowing the live
/// device would mean resizing the thing a person is looking at, and a
/// software device costs nothing to make and nothing to lose when the render
/// is thrown away.
///
/// **Framed the way `render` frames it**, so the picture the panel shows and
/// the picture an agent asks for are the same picture.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart' show PerspectiveProjection;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart';

GraphicsDevice _cpuDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// A PNG of [project] at [width]×[height], rendered in [tiles]×[tiles] tiles.
///
/// [onProgress] is called with `0..1` as the tiles land, which is what the
/// panel draws over the picture.
Future<Uint8List> renderSnapshotOf(
  ModelProject project, {
  required int width,
  required int height,
  int tiles = 1,
  void Function(double done)? onProgress,
}) {
  // The frame has to divide into the tiles or a tile is not a whole number
  // of pixels — `RenderPreset` asserts it, and answering with one tile is
  // better than throwing at a person who pressed a button.
  final int grid = width % tiles == 0 && height % tiles == 0 ? tiles : 1;
  return RenderSnapshotJob(
    project,
    RenderPreset(
      width: width,
      height: height,
      camera: snapshotCameraFor(project),
      tilesX: grid,
      tilesY: grid,
    ),
    tileDevice: _cpuDevice,
  ).run(onProgress: onProgress);
}

/// Where a camera stands to see all of [project] from the three-quarter
/// view — the same framing `renderProject` uses.
SnapshotCamera snapshotCameraFor(ModelProject project) {
  Aabb3? box;
  for (final ModelObject object in project.objects) {
    final Aabb3? local = _boundsOf(object.geometry);
    if (local == null) continue;
    final Aabb3 world = Aabb3.copy(local)
      ..transform(worldTransformOf(project, object.id));
    box = box == null ? world : (box..hull(world));
  }
  final Vector3 centre = box?.center ?? Vector3.zero();
  final double radius = box == null
      ? 1.0
      : math.max(box.min.distanceTo(box.max) / 2, 1e-5);
  const double fovY = math.pi / 4;
  final double distance = radius / math.sin(fovY / 2) * 1.2;
  // The iso view's own yaw and pitch, the ones `RenderProjectView.iso`
  // carries.
  const double yaw = math.pi / 4;
  const double pitch = math.pi / 6;
  final Vector3 offset = Vector3(
    math.sin(yaw) * math.cos(pitch),
    math.sin(pitch),
    math.cos(yaw) * math.cos(pitch),
  )..scale(distance);
  return SnapshotCamera(
    position: centre + offset,
    target: centre,
    projection: PerspectiveProjection(
      fovYRadians: fovY,
      near: math.max(distance * 0.01, 1e-6),
      far: distance * 10.0 + 10.0,
    ),
  );
}

/// [geometry]'s own local bounding box, or null where it has none.
Aabb3? _boundsOf(Geometry geometry) {
  final Vector3 min = Vector3.all(double.infinity);
  final Vector3 max = Vector3.all(double.negativeInfinity);
  var any = false;
  void grow(Vector3 at) {
    any = true;
    Vector3.min(min, at, min);
    Vector3.max(max, at, max);
  }

  switch (geometry) {
    case EditedGeometry(:final mesh):
      final Vector3 at = Vector3.zero();
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        if (!mesh.isVertexAlive(v)) continue;
        grow(mesh.positionOf(v, at));
      }
    case ParametricGeometry(:final shape):
      final built = shape.drawn.build();
      final Vector3 at = Vector3.zero();
      for (var v = 0; v < built.vertexCount; v++) {
        grow(built.positionAt(v, at));
      }
    case ImportedGeometry(:final data):
      final Vector3 at = Vector3.zero();
      for (var v = 0; v < data.vertexCount; v++) {
        grow(data.positionAt(v, at));
      }
    case SocketGeometry():
      break;
  }
  return any ? Aabb3.minMax(min, max) : null;
}
