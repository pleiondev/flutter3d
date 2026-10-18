// The field checks against a device that has no GPU: the refusal branch
// the software rasteriser never takes, since it has 3D textures.
import 'package:flutter3d_conformance/flutter3d_conformance.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

Future<void> _run(String name, GraphicsDevice device) =>
    fieldResidenceChecks.firstWhere((c) => c.name.contains(name)).run(device);

void main() {
  test('a device without 3D textures passes by refusing one by name', () async {
    // Mutation: return on a device without the feature without asking it.
    // A backend that hands out a flat texture for a volume would pass.
    await _run('3D texture', FakeBackend());
    await _run(
      '3D texture',
      FakeBackend(
        extraFeatures: const <DeviceFeature>[DeviceFeature.textureWrites],
      ),
    );
  });

  test('a device with them makes one of the field\'s shape', () async {
    final device = FakeBackend(
      extraFeatures: const <DeviceFeature>[
        DeviceFeature.texture3D,
        DeviceFeature.textureWrites,
      ],
    );
    await _run('3D texture', device);
    final made = device.calls.firstWhere((c) => c.name == 'createTexture');
    expect(
      (made.arguments! as TextureDescriptor).dimension,
      TextureDimension.d3,
    );
    expect(device.calls.where((c) => c.name == 'writeTexture'), hasLength(1));
  });

  test('a device without compute declines the buffer check', () {
    expect(
      () => _run('storage buffer', FakeBackend()),
      throwsA(isA<ConformanceDeclinedException>()),
    );
  });
}
