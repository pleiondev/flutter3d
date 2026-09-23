/// A material with no normal map shades the same whichever way its tangent
/// runs.
///
///     flutter test test/flat_normal_test.dart
///
/// **The fallback normal texture is not quite flat on its own.** It stores
/// 0.5 as byte 128, which decodes to 0.0039 rather than 0, so a surface with
/// no normal map was tilted by about a third of a degree along its tangent,
/// and two copies of one quad differing only in tangent shaded differently.
/// The renderer now sends a normal scale of zero with the fallback.
///
/// The light grazes the quad at eighty degrees, where N·L moves fastest with
/// the normal, so a third of a degree is several steps of a byte.
///
/// Mutation: send `material.normalScale` whether or not the material has a
/// normal map, in `renderer_mesh_encode.dart`.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 48;

Future<List<int>> _quadWithTangent(Vector4 tangent) async {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);

  final builder = MeshBuilder(VertexLayout.standard);
  int corner(double x, double y) => builder.addVertex(
    position: Vector3(x, y, 0.0),
    normal: Vector3(0.0, 0.0, 1.0),
    texcoord: Vector2(x * 0.5 + 0.5, 0.5 - y * 0.5),
    tangent: tangent,
  );
  builder.addQuad(
    corner(-1.0, -1.0),
    corner(1.0, -1.0),
    corner(1.0, 1.0),
    corner(-1.0, 1.0),
  );

  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, builder.build()),
        Material(name: 'quad', baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
      ),
    )
    ..add(
      LightNode(intensity: 4.0)
        ..setPosition(5.0, 0.0, 0.9)
        ..lookAt(Vector3.zero()),
    )
    ..add(CameraNode()..setPosition(0.0, 0.0, 2.5));

  final result = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
    settings: const RenderSettings(),
  );
  final bytes = await device.readPixels(result.frame);
  return <int>[for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i)];
}

void main() {
  test('a quad with no normal map shades the same for any tangent', () async {
    final alongX = await _quadWithTangent(Vector4(1.0, 0.0, 0.0, 1.0));
    final alongY = await _quadWithTangent(Vector4(0.0, 1.0, 0.0, 1.0));

    expect(alongX.any((int b) => b > 0), isTrue, reason: 'nothing was drawn');
    expect(alongY, alongX);
  });
}
