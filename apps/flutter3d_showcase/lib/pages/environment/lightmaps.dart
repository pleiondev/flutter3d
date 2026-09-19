/// A baked lightmap: indirect light stored in a texture ahead of time, read
/// through a second coordinate the vertex colour carries.
///
/// Quoted by `lightmaps.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

const int _lightmapSize = 4;

final class LightmapsDemo extends ShowcaseDemo {
  bool baked = true;

  late final MeshData _floorMesh;
  late final ByteData _lightmapPixels;
  late final TextureHandle _lightmap;
  late final Material _floor;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.55
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
    context.orbit.apply();
  }

  @override
  Scene build(DemoContext context) {
    // #region uv
    _floorMesh = const PlaneShape(width: 3, depth: 3).build();
    _useTexcoordAsLightmapUv(_floorMesh);
    // #endregion uv

    // #region bake
    _lightmapPixels = _bakeBrightCorner();
    _lightmap = context.device.createTextureFromPixels(
      width: _lightmapSize,
      height: _lightmapSize,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: _lightmapPixels,
    )!;
    _floor = Material(name: 'floor', baseColor: Vector4(0.8, 0.8, 0.8, 1.0))
      ..lightmap = _lightmap;
    // #endregion bake

    final MeshNode floor = MeshNode(
      DeviceMesh.upload(context.device, _floorMesh),
      _floor,
      name: 'floor',
    )..lightmapped = true;

    return Scene()
      ..ambientIntensity = 0.0
      ..add(floor);
  }

  // #region live
  @override
  void update(DemoContext context, double dt) {
    _floor.lightmap = baked ? _lightmap : null;
  }
  // #endregion live

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Lightmap on',
      value: () => baked,
      onChanged: (bool v) => baked = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final MeshNode floor = scene.meshes.first;
    if (!floor.lightmapped) {
      throw StateError('the floor was never marked lightmapped');
    }
    final VertexLayout layout = _floorMesh.layout;
    final int stride = layout.floatsPerVertex;
    final int uvAt = layout.floatOffsetOf(VertexLayout.texcoord.name);
    final int colorAt = layout.floatOffsetOf(VertexLayout.color.name);
    for (var v = 0; v < _floorMesh.vertexCount; v++) {
      final int base = v * stride;
      final bool matches =
          _floorMesh.vertices[base + colorAt] ==
              _floorMesh.vertices[base + uvAt] &&
          _floorMesh.vertices[base + colorAt + 1] ==
              _floorMesh.vertices[base + uvAt + 1];
      if (!matches) {
        throw StateError('vertex $v carries a tint, not its lightmap UV');
      }
    }
    final int bright = _lightmapPixels.getUint8(0);
    final int stride2 = _lightmapSize * 4;
    final int lastRow = stride2 * (_lightmapSize - 1);
    final int dark = _lightmapPixels.getUint8(
      lastRow + (_lightmapSize - 1) * 4,
    );
    if (bright <= dark) {
      throw StateError('the baked lightmap has no bright corner to read');
    }
  }
}

/// Copies each vertex's texture coordinate into its colour, which is the
/// place `MeshNode.lightmapped` reads a lightmap at.
void _useTexcoordAsLightmapUv(MeshData mesh) {
  final VertexLayout layout = mesh.layout;
  final int stride = layout.floatsPerVertex;
  final int uvAt = layout.floatOffsetOf(VertexLayout.texcoord.name);
  final int colorAt = layout.floatOffsetOf(VertexLayout.color.name);
  for (var v = 0; v < mesh.vertexCount; v++) {
    final int base = v * stride;
    mesh.vertices[base + colorAt] = mesh.vertices[base + uvAt];
    mesh.vertices[base + colorAt + 1] = mesh.vertices[base + uvAt + 1];
  }
}

/// A small lightmap, RGBM-encoded: bright over the corner at UV (0, 0) and
/// dim everywhere else, so the two ends of the bake read differently.
ByteData _bakeBrightCorner() {
  final ByteData pixels = ByteData(_lightmapSize * _lightmapSize * 4);
  for (var y = 0; y < _lightmapSize; y++) {
    for (var x = 0; x < _lightmapSize; x++) {
      final bool corner = x == 0 && y == 0;
      final (int, int, int) rgb = corner ? (64, 48, 16) : (2, 2, 3);
      final int at = (y * _lightmapSize + x) * 4;
      pixels
        ..setUint8(at, rgb.$1)
        ..setUint8(at + 1, rgb.$2)
        ..setUint8(at + 2, rgb.$3)
        ..setUint8(at + 3, 255);
    }
  }
  return pixels;
}
