/// `withTextureTransform`: `KHR_texture_transform`, applied to a mesh's own
/// texture coordinates.
///
/// Quoted by `texture_transform.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class TextureTransformDemo extends ShowcaseDemo {
  late final MeshData _plain;
  late final MeshData _moved;

  @override
  Scene build(DemoContext context) {
    // #region checker
    // An 8x8 checker, small enough that scaling the transform below by
    // four makes the tiling obvious.
    final pixels = Uint8List(8 * 8 * 4);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final lit = ((x ~/ 2) + (y ~/ 2)).isEven;
        final o = (y * 8 + x) * 4;
        final value = lit ? 235 : 25;
        pixels[o] = value;
        pixels[o + 1] = value;
        pixels[o + 2] = value;
        pixels[o + 3] = 255;
      }
    }
    final albedo = context.device.createTextureFromPixels(
      width: 8,
      height: 8,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(pixels),
    );
    // #endregion checker

    // #region transform
    // `KHR_texture_transform`'s own order: scale, then rotate, then move.
    // Scaling by four here tiles the checker four times across the plane
    // instead of stretching one copy of it across the whole surface.
    _plain = PlaneShape(width: 2, depth: 2).build();
    final transform = TextureTransform(scale: Vector2(4.0, 4.0));
    _moved = withTextureTransform(_plain, transform);
    // #endregion transform

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(context.device, _moved),
          Material(albedo: albedo, roughness: 0.8),
          name: 'floor',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.0
      ..pitch = 0.9
      ..yaw = 0.4;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final layout = _plain.layout;
    final stride = layout.floatsPerVertex;
    final uvOffset = layout.floatOffsetOf(VertexLayout.texcoord.name);
    // The plane's corner at U=1 should come back at U=4, the same
    // arithmetic checked independently of whatever `withTextureTransform`
    // did internally.
    final cornerOffset = stride + uvOffset;
    final sourceU = _plain.vertices[cornerOffset];
    final movedU = _moved.vertices[cornerOffset];
    if ((movedU - sourceU * 4.0).abs() > 1e-6 || sourceU == 0.0) {
      throw StateError('the transform did not scale U by four');
    }
    if (_moved.vertices.length != _plain.vertices.length) {
      throw StateError('the transform changed the vertex count');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the floor was not drawn');
    }
    // #endregion check
  }
}
