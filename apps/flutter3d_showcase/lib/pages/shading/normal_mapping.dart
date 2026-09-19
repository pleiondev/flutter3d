/// A normal map: fine surface relief painted into a texture, with no extra
/// triangles.
///
/// Quoted by `normal_mapping.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class NormalMappingDemo extends ShowcaseDemo {
  double normalScale = 1.0;
  bool useMap = true;
  double sunTurn = 0.6;

  static const int _size = 128;
  static const int _cobbles = 4;

  late final Material _ball;
  late final LightNode _sun;
  late final TextureHandle _normalMap;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.2
      ..yaw = 0.0
      ..pitch = 0.1;
  }

  // #region texture
  /// A grid of round cobbles. Each texel stores the direction the surface
  /// faces there, x, y and z scaled from -1..1 into 0..255.
  ByteData _cobbleNormals() {
    final Uint8List bytes = Uint8List(_size * _size * 4);
    const int cell = _size ~/ _cobbles;
    for (var y = 0; y < _size; y++) {
      for (var x = 0; x < _size; x++) {
        final double u = ((x % cell) + 0.5) / cell * 2.0 - 1.0;
        final double v = 1.0 - ((y % cell) + 0.5) / cell * 2.0;
        final double r2 = u * u + v * v;
        final Vector3 n = r2 < 0.85
            ? Vector3(u * 0.9, v * 0.9, math.sqrt(1.0 - r2 * 0.81)).normalized()
            : Vector3(0.0, 0.0, 1.0);
        final int at = (y * _size + x) * 4;
        bytes[at] = ((n.x * 0.5 + 0.5) * 255).round();
        bytes[at + 1] = ((n.y * 0.5 + 0.5) * 255).round();
        bytes[at + 2] = ((n.z * 0.5 + 0.5) * 255).round();
        bytes[at + 3] = 255;
      }
    }
    return bytes.buffer.asByteData();
  }
  // #endregion texture

  @override
  Scene build(DemoContext context) {
    // #region upload
    final ByteData pixels = _cobbleNormals();
    _normalMap = context.device.createTextureFromPixels(
      width: _size,
      height: _size,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: pixels,
      mipLevels: MipChain.build(pixels, _size, _size),
    )!;
    // #endregion upload

    // #region material
    _ball = Material(
      name: 'cobbles',
      baseColor: Vector4(0.62, 0.6, 0.56, 1.0),
      roughness: 0.55,
      normal: _normalMap,
      normalSampler: SamplerOptions.trilinearRepeat,
      normalScale: normalScale,
    );
    // #endregion material

    // #region tangents
    final MeshData data = SphereShape(segments: 64, rings: 32)
        .build(layout: VertexLayout.positionNormalTexcoord)
        .withGeneratedTangents(target: VertexLayout.standard);
    final MeshNode ball = MeshNode(
      DeviceMesh.upload(context.device, data),
      _ball,
      name: 'ball',
    );
    // #endregion tangents

    _sun = LightNode(name: 'sun', intensity: 3.0);
    return Scene()
      ..add(ball)
      ..add(_sun);
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _ball
      ..normal = useMap ? _normalMap : null
      ..normalScale = normalScale;
    _sun.setLocalForward(Vector3(-math.sin(sunTurn), -0.3, -math.cos(sunTurn)));
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Normal scale',
      min: 0,
      max: 3,
      value: () => normalScale,
      onChanged: (double v) => normalScale = v,
    ),
    ToggleControl(
      'Normal map',
      value: () => useMap,
      onChanged: (bool v) => useMap = v,
    ),
    SliderControl(
      'Sun direction',
      min: -1.4,
      max: 1.4,
      value: () => sunTurn,
      onChanged: (double v) => sunTurn = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final Material material = scene.meshes.first.material;
    if (material.normal == null) {
      throw StateError('the ball has no normal map bound');
    }
    final MeshData? source = (scene.meshes.first.mesh as DeviceMesh).source;
    if (source == null || !source.layout.has(VertexLayout.tangent)) {
      throw StateError('the mesh carries no tangents for the map to use');
    }
    if (frame.drawCalls < 1) throw StateError('the ball was not drawn');
  }
}
