/// A node's own values for its material's parameters reach its draw, and
/// only its own.
///
///     flutter test test/node_parameters_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/software.dart' show materialLanguageCompiler;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

const int _size = 32;

const String _paint = '''
material Paint {
  uniform vec3 paint = vec3(1.0, 0.0, 0.0);
  fragment {
    return vec4(paint, 1.0);
  }
}
''';

const ParameterKey<LinearColor> _paintKey = ParameterKey<LinearColor>(
  'paint',
  ParameterType.color,
);

ByteData _bundle() => ShaderBundle(
  name: 'materials',
  sdk: '',
  stages: <ShaderBundleStage>[ShaderBundleStage('Paint', fragment: true)],
  sections: <String, ByteData>{
    ShaderBundle.materialSection: encodeMaterialSection(<String, String>{
      'Paint': _paint,
    }),
  },
).encode();

/// The middle pixel's red and blue, of a frame of [node] alone.
Future<(double, double)> _center(
  CpuDevice device,
  Renderer renderer,
  MeshNode node,
) async {
  final camera = CameraNode()..setPosition(0.0, 0.0, 3.0);
  final scene = Scene()
    ..add(camera)
    ..add(node);
  final result = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: const RenderSettings(
      bloom: BloomSettings(enabled: false),
      tonemap: false,
      look: LookSettings(dither: 0.0),
    ),
  );
  final pixels = await device.readback(result.frame);
  final at = ((_size ~/ 2) * _size + _size ~/ 2) * 4;
  return (pixels.getUint8(at) / 255.0, pixels.getUint8(at + 2) / 255.0);
}

void main() {
  test('a node draws with its own values, its material with its own', () async {
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
      materialCompiler: materialLanguageCompiler,
    );
    final bytes = _bundle();
    final library = await device.loadShaders(bytes);
    final bundled = BundledMaterials.read(bytes);
    final renderer = Renderer.create(device: device, materials: library);
    final material = RenderMaterial(
      lighting: bundled['Paint'],
      parameters: bundled.parameters('Paint'),
    );
    final mesh = DeviceMesh.upload(device, CuboidShape().build());

    final blue = MeshNode(mesh, material)
      ..parameters = (MaterialParameters(schema: bundled.schema('Paint'))
        ..set(_paintKey, const LinearColor(0.0, 0.0, 1.0)));
    // Mutation: bind the material's own map whatever the node says, and
    // this cube is red.
    final (blueRed, blueBlue) = await _center(device, renderer, blue);
    expect(blueRed, closeTo(0.0, 0.01));
    expect(blueBlue, closeTo(1.0, 0.01));

    final plain = MeshNode(mesh, material);
    final (plainRed, plainBlue) = await _center(device, renderer, plain);
    expect(plainRed, closeTo(1.0, 0.01));
    expect(plainBlue, closeTo(0.0, 0.01));
  });
}
