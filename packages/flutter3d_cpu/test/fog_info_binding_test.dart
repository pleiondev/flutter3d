/// A stage that reads no `FragInfo` still gets the fog.
///
///     dart test test/fog_info_binding_test.dart
///
/// `color.glsl` declares `FogInfo`, so every stage that writes its colour
/// through `WriteSurface` keeps it. The renderer bound it only beside
/// `FragInfo`, and a stage of one's own that reads no material inputs, like
/// the example's stripes, was drawn with it unbound: no fog, and a surface
/// depth of nought. WebGL2 named the block at every draw of `loaded-shader`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 16;

/// Red, written the way a stage of one's own writes it: through `WriteSurface`
/// and nothing else.
final class _Red implements CpuFragmentShader {
  const _Red();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) => writeLit(
    c,
    v,
    b,
    colour: Vector3(1.0, 0.0, 0.0),
    alpha: 1.0,
    normal: Vector3(0.0, 0.0, 1.0),
    roughness: 1.0,
  );
}

const LightingModel _red = LightingModel(
  'Red',
  'Red',
  usesFragInfo: false,
  usesAlbedoTexture: false,
  usesMaterialMaps: false,
  usesMetallicRoughnessMap: false,
  usesMaterialParameters: false,
  usesFogInfo: true,
);

/// The centre of a red wall three metres off, under [fog].
Vector3 _centre(FogSettings fog) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(<String, CpuStage>{
      ...builtinCpuShaders(),
      'Red': const CpuStage.fragment(_Red()),
    }),
  );
  final camera = CameraNode()..setPosition(0.0, 0.0, 0.0);
  final scene = Scene()
    ..ambientIntensity = 0.0
    ..add(camera)
    ..add(
      MeshNode(
          DeviceMesh.upload(
            device,
            const PlaneShape(width: 8, depth: 8).build(),
          ),
          Material(lighting: _red, doubleSided: true),
        )
        ..setPosition(0.0, 0.0, -3.0)
        ..setRotationYawPitchRoll(0.0, math.pi / 2, 0.0),
    );
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      fog: fog,
    ),
  );
  final pixels = device.readHdrPixels(result.frame);
  final at = ((_size ~/ 2) * _size + _size ~/ 2) * 4;
  return Vector3(pixels[at], pixels[at + 1], pixels[at + 2]);
}

void main() {
  test('the model says it reads the fog, and defaults to FragInfo', () {
    expect(_red.usesFogInfo, isTrue);
    expect(LightingModel.normals.usesFogInfo, isFalse);
    expect(LightingModel.pbr.usesFogInfo, isTrue);
  });

  test('a stage without FragInfo is fogged', () {
    // Mutation: bind FogInfo only beside FragInfo, as it was. The fogged wall
    // comes back as red as the clear one.
    final clear = _centre(const FogSettings());
    final fogged = _centre(
      FogSettings(color: Vector3(0.0, 0.0, 1.0), density: 2.0),
    );
    expect(clear.x, greaterThan(0.5), reason: 'the wall is not there');
    expect(clear.z, lessThan(0.05));
    // Three metres at two per metre leaves e^-6 of the wall's own colour.
    expect(fogged.x, lessThan(0.05));
    expect(fogged.z, greaterThan(0.5));
  });
}
