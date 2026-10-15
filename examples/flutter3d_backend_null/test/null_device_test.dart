/// The null backend from the engine's side: opened through a registry, a
/// material compiled for it, a bundle loaded on it, and the renderer
/// drawing a frame there.
///
///     dart test test/null_device_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_backend_null/flutter3d_backend_null.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/backend.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a registry opens it, and the registration takes it out', () async {
    final registry = DeviceRegistry<Object>();
    final compilers = MaterialCompilerRegistry();
    final registration = registerNullBackend(registry, compilers: compilers);
    expect(registry.backendNames, <String>[NullDevice.name]);
    expect(compilers.forBackend(NullDevice.name), isA<NullMaterialCompiler>());
    final device = await registry.open(width: 8, height: 8);
    expect(device, isA<NullDevice>());
    // The compiler is found by the id the device gives, exactly.
    // Mutation: name the compiler "Null".
    expect(
      compilers.forBackend((device as NullDevice).backendId),
      isA<NullMaterialCompiler>(),
    );

    registration.cancel();
    expect(registry.backendNames, isEmpty);
    expect(compilers.forBackend(NullDevice.name), isNull);
  });

  test(
    'a material its compiler wrote is answered by a bundle it loads',
    () async {
      // Mutation: answer only the bundle's stage list, and the material the
      // section carries is not found.
      final compiled = const NullMaterialCompiler().compile(
        const MaterialCompileRequest(
          name: 'glow',
          from: 'glow.f3dmat',
          source: 'material glow {}',
          stages: <MaterialStageSource>[
            MaterialStageSource(name: 'glow', fragment: true, glsl: ''),
          ],
        ),
      );
      final bundle = ShaderBundle(
        name: 'plugin',
        sdk: '',
        stages: const <ShaderBundleStage>[
          ShaderBundleStage('PlainVertex', fragment: false),
        ],
        sections: <String, ByteData>{nullSection: compiled.section},
      );
      final device = await NullDevice.open(width: 8, height: 8);
      final library = await device.loadShaders(bundle.encode());
      expect(library['PlainVertex'], isNotNull);
      expect(library['glow'], isNotNull);
      expect(library['missing'], isNull);
    },
  );

  test('the engine draws a frame on it, and each pipeline it draws with is '
      'told refused once', () async {
    // Mutation: report a refusal at every draw rather than once, and the
    // second frame tells the same pipelines again.
    final device = await NullDevice.open(width: 32, height: 24);
    final renderer = Renderer.create(device: device);
    final camera = CameraNode()..lookAt(Vector3(0.0, 0.0, -1.0));
    final scene = Scene()
      ..add(camera)
      ..add(
        MeshNode(
          DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1)).build()),
          RenderMaterial(name: 'box'),
        )..setPosition(0.0, 0.0, -4.0),
      );
    FrameResult frame() => renderer.render(
      width: 32,
      height: 24,
      scene: scene,
      views: <CameraView>[CameraView(camera: camera)],
    );

    final first = frame();
    expect(first.pipelineRefusals, isNotEmpty);
    expect(first.pipelineRefusals.map((r) => r.backend).toSet(), <String>{
      NullDevice.name,
    });
    final pixels = await device.readback(first.frame);
    expect(pixels.lengthInBytes, 32 * 24 * 4);

    expect(frame().pipelineRefusals, isEmpty);
    renderer.dispose();
    device.dispose();
  });
}
