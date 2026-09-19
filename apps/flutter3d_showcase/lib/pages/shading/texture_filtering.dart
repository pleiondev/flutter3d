/// Anisotropic filtering: a checkerboard floor that stays sharp toward the
/// horizon.
///
/// Quoted by `texture_filtering.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class TextureFilteringDemo extends ShowcaseDemo {
  int anisotropyChoice = 3;

  static const List<int> _levels = <int>[1, 2, 4, 8, 16];
  static const int _size = 256;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.0
      ..yaw = 0.0
      ..pitch = 0.07;
    context.orbit.target.setValues(0.0, 0.2, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region texture
    final ByteData pixels = const CheckerboardTexture(
      size: _size,
      cell: 16,
    ).encode();
    final TextureHandle checks = context.device.createTextureFromPixels(
      width: _size,
      height: _size,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: pixels,
      mipLevels: MipChain.build(pixels, _size, _size),
    )!;
    // #endregion texture

    // #region floor
    final Material floor = Material(
      name: 'checks',
      albedo: checks,
      albedoSampler: SamplerOptions.trilinearRepeat,
      roughness: 0.9,
    );
    final MeshNode ground = MeshNode(
      DeviceMesh.upload(
        context.device,
        const PlaneShape(width: 60, depth: 60).build(),
      ),
      floor,
      name: 'floor',
    );
    // #endregion floor

    return Scene()
      ..add(ground)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.3, -1.0, -0.4)),
      );
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    anisotropy: _levels[anisotropyChoice],
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Anisotropy',
      options: <String>[for (final int level in _levels) '${level}x'],
      index: () => anisotropyChoice,
      onChanged: (int i) => anisotropyChoice = i,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final Material floor = scene.meshes.first.material;
    if (floor.albedoSampler?.mipFilter != MipFilter.linear) {
      throw StateError('the floor sampler does not blend mip levels');
    }
    if (_levels[anisotropyChoice] <= 1) {
      throw StateError('anisotropy is off, so nothing here is filtered');
    }
    if (frame.drawCalls < 1) throw StateError('the floor was not drawn');
  }
}
