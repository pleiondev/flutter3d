/// Two textures encoded in Dart and uploaded through the active device.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ProceduralTexturesDemo extends ShowcaseDemo {
  final SolidColorTexture _solid = SolidColorTexture(
    Vector4(0.12, 0.55, 0.92, 1.0),
  );
  static const CheckerboardTexture _checker = CheckerboardTexture(
    size: 64,
    cell: 8,
    light: 0xF0C86A,
    dark: 0x314A72,
  );

  late final Material _solidMaterial;
  late final Material _checkerMaterial;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.5
      ..pitch = 0.24
      ..yaw = 0.35;
    context.orbit.target.setValues(0.0, 0.8, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region encode
    final ByteData solidPixels = _solid.encode();
    final ByteData checkerPixels = _checker.encode();
    if (solidPixels.lengthInBytes != 4 ||
        checkerPixels.lengthInBytes != 64 * 64 * 4) {
      throw StateError('a procedural texture returned the wrong byte count');
    }
    // #endregion encode

    // #region upload
    _solidMaterial = Material(
      name: 'solid blue',
      baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
      albedo: _solid.upload(context.device),
      roughness: 0.42,
    );
    _checkerMaterial = Material(
      name: 'checkerboard',
      baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
      albedo: _checker.upload(context.device),
      albedoSampler: SamplerOptions.linearRepeat,
      roughness: 0.58,
    );
    // #endregion upload

    // #region scene
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.45, 0.54, 0.72)
      ..ambientIntensity = 0.14
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const SphereShape(radius: 1.05, segments: 36, rings: 18).build(),
          ),
          _solidMaterial,
          name: 'solid sphere',
        )..setPosition(-1.65, 1.05, 0.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const TorusShape(
              radius: 0.82,
              tubeRadius: 0.34,
              segments: 48,
              tubeSegments: 24,
            ).build(),
          ),
          _checkerMaterial,
          name: 'checker torus',
        )..setPosition(1.65, 1.05, 0.0),
      )
      ..add(
        LightNode(name: 'key', intensity: 3.3)
          ..setLocalForward(Vector3(-0.45, -0.82, -0.35)),
      );
    // #endregion scene
    return scene;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final Uint8List checker = _checker.encode().buffer.asUint8List();
    final bool twoColours =
        checker[0] != checker[_checker.cell * 4] ||
        checker[1] != checker[_checker.cell * 4 + 1] ||
        checker[2] != checker[_checker.cell * 4 + 2];
    if (_solidMaterial.albedo == null ||
        _checkerMaterial.albedo == null ||
        !twoColours ||
        frame.drawCalls < 2) {
      throw StateError('the procedural textures were not drawn');
    }
    // #endregion check
  }
}
