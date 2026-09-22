/// The four ways a material treats its alpha channel: opaque, mask, blend and
/// hashed.
///
/// Quoted by `alpha_modes.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AlphaModesDemo extends ShowcaseDemo {
  double opacity = 0.9;
  double cutoff = 0.5;
  bool doubleSided = false;

  static const int _size = 64;

  late final List<Material> _materials;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.0
      ..yaw = 0.0
      ..pitch = 0.05;
  }

  // #region texture
  /// White everywhere, with an alpha that is one at the centre and falls to
  /// zero at the rim: a soft disc.
  ByteData _softDisc() {
    final Uint8List bytes = Uint8List(_size * _size * 4);
    for (var y = 0; y < _size; y++) {
      for (var x = 0; x < _size; x++) {
        final double dx = (x + 0.5) / _size * 2.0 - 1.0;
        final double dy = (y + 0.5) / _size * 2.0 - 1.0;
        final double alpha = (1.0 - math.sqrt(dx * dx + dy * dy)).clamp(0, 1);
        final int at = (y * _size + x) * 4;
        bytes[at] = 255;
        bytes[at + 1] = 255;
        bytes[at + 2] = 255;
        bytes[at + 3] = (alpha * 255).round();
      }
    }
    return bytes.buffer.asByteData();
  }
  // #endregion texture

  @override
  Scene build(DemoContext context) {
    final TextureHandle disc = context.device.createTextureFromPixels(
      width: _size,
      height: _size,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: _softDisc(),
    )!;

    // #region materials
    _materials = <Material>[
      for (final MaterialAlphaMode mode in MaterialAlphaMode.values)
        Material(
          name: mode.name,
          baseColor: Vector4(0.95, 0.55, 0.2, opacity),
          albedo: disc,
          albedoSampler: SamplerOptions.linearClamp,
          alphaMode: mode,
        ),
    ];
    // #endregion materials

    // #region panels
    final DeviceMesh panel = DeviceMesh.upload(
      context.device,
      const PlaneShape(width: 1.4, depth: 1.4).build(),
    );
    final Quaternion upright = Quaternion.axisAngle(
      Vector3(1.0, 0.0, 0.0),
      math.pi / 2,
    );
    final Scene scene = Scene();
    for (var i = 0; i < _materials.length; i++) {
      scene.add(
        MeshNode(panel, _materials[i], name: _materials[i].name)
          ..setRotation(upright)
          ..setPosition((i - 1.5) * 1.6, 0.0, 0.0),
      );
    }
    // #endregion panels

    final MeshNode wall =
        MeshNode(
            DeviceMesh.upload(
              context.device,
              const PlaneShape(width: 9, depth: 3).build(),
            ),
            Material(name: 'wall', baseColor: Vector4(0.2, 0.35, 0.55, 1.0)),
            name: 'wall',
          )
          ..setRotation(upright)
          ..setPosition(0.0, 0.0, -0.6);
    return scene
      ..add(wall)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.2, -0.3, -1.0)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    for (final Material material in _materials) {
      material
        ..baseColor.w = opacity
        ..alphaCutoff = cutoff
        ..doubleSided = doubleSided;
    }
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Opacity',
      min: 0.1,
      max: 1,
      value: () => opacity,
      onChanged: (double v) => opacity = v,
    ),
    SliderControl(
      'Alpha cutoff',
      min: 0.05,
      max: 0.95,
      value: () => cutoff,
      onChanged: (double v) => cutoff = v,
    ),
    ToggleControl(
      'Double sided',
      value: () => doubleSided,
      onChanged: (bool v) => doubleSided = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final Set<MaterialAlphaMode> modes = <MaterialAlphaMode>{
      for (final MeshNode mesh in scene.meshes) mesh.material.alphaMode,
    };
    if (modes.length != MaterialAlphaMode.values.length) {
      throw StateError('the panels do not cover every alpha mode: $modes');
    }
    final int sceneDraws = frame.passes
        .where((FramePass pass) => pass.name == 'scene')
        .fold(0, (int sum, FramePass pass) => sum + pass.drawCalls);
    if (sceneDraws != scene.meshes.length) {
      throw StateError(
        'the scene pass drew $sceneDraws of ${scene.meshes.length} meshes',
      );
    }
  }
}
