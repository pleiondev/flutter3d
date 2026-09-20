/// A cut-out caster throws a cut-out shadow: the holes in a leaf's texture are
/// holes in its shadow too.
///
/// Quoted by `masked_shadow_casters.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

// #region texture
/// A grid of soft discs on a clear background: opaque in the middle of each
/// disc, fading to nothing at its rim.
final class DiscsTexture extends ProceduralTexture {
  const DiscsTexture({this.size = 64, this.cells = 4});

  @override
  final int size;
  final int cells;

  @override
  ByteData encode() {
    final Uint8List bytes = Uint8List(size * size * 4);
    final double cell = size / cells;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final double dx = (x + 0.5) % cell - cell / 2;
        final double dy = (y + 0.5) % cell - cell / 2;
        final double radius = Vector2(dx, dy).length / cell;
        final double alpha = ((0.5 - radius) / 0.35).clamp(0.0, 1.0);
        final int at = (y * size + x) * 4;
        bytes[at] = 70;
        bytes[at + 1] = 150;
        bytes[at + 2] = 70;
        bytes[at + 3] = (alpha * 255).round();
      }
    }
    return bytes.buffer.asByteData();
  }
}
// #endregion texture

final class MaskedShadowCastersDemo extends ShowcaseDemo {
  bool cutOut = true;
  double cutoff = 0.5;

  late final Material _leaves;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 8.0
      ..pitch = 0.75
      ..yaw = 0.4;
    context.orbit.target.setValues(0.5, 0.5, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.78, 0.76, 0.72, 1.0),
      roughness: 0.9,
      doubleSided: true,
    );

    // #region leaves
    _leaves = Material(
      name: 'leaves',
      albedo: const DiscsTexture().upload(context.device),
      alphaMode: MaterialAlphaMode.mask,
      alphaCutoff: cutoff,
      doubleSided: true,
      roughness: 0.8,
    );
    final MeshNode canopy = MeshNode(
      DeviceMesh.upload(
        context.device,
        const PlaneShape(width: 3, depth: 3).build(),
      ),
      _leaves,
      name: 'canopy',
    )..setPosition(-0.5, 1.6, 0.0);
    // #endregion leaves

    // #region sun
    final LightNode sun = LightNode(
      name: 'sun',
      intensity: 3.0,
      castsShadow: true,
    )..setLocalForward(Vector3(-0.5, -0.8, -0.3));
    // #endregion sun

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 10, depth: 10).build(),
          ),
          stone,
          name: 'ground',
        ),
      )
      ..add(canopy)
      ..add(sun);
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _leaves
      ..alphaMode = cutOut ? MaterialAlphaMode.mask : MaterialAlphaMode.opaque
      ..alphaCutoff = cutoff;
    // #endregion live
  }

  @override
  RenderSettings settings(DemoContext context) => const RenderSettings(
    shadows: ShadowSettings(cascades: 1, resolution: 1024),
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Cut out',
      value: () => cutOut,
      onChanged: (bool v) => cutOut = v,
    ),
    SliderControl(
      'Cutoff',
      min: 0.05,
      max: 0.95,
      value: () => cutoff,
      onChanged: (double v) => cutoff = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (_leaves.alphaMode != MaterialAlphaMode.mask || _leaves.albedo == null) {
      throw StateError('the canopy is not a masked caster');
    }
    if (!frame.passes.any((FramePass p) => p.name == 'directional shadows')) {
      throw StateError('the sun drew no shadow map');
    }
    if (frame.shadowCasters < 2) {
      throw StateError('the canopy and the ground were not both drawn');
    }
  }
}
