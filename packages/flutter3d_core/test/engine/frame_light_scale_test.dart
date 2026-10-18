// The light scale `hdr_color` is in, as a stage outside the engine reads it:
// one number, the one every light the API takes in nits, lux or candela is
// turned into.
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

final class _Services with RenderServices {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('a light scale draws nothing');
}

final class _Frame extends FrameContext {
  _Frame()
    : super(
        device: FakeBackend(),
        services: _Services(),
        settings: const RenderSettings(),
        width: 1,
        height: 1,
      );
}

void main() {
  test('one unit of hdr_color is the luminance a default emissive shines '
      'at', () {
    // Mutation: answer any other factor and a stage adding light in nits
    // draws it brighter or dimmer than a material of the same nits.
    final frame = _Frame();
    expect(frame.nitsPerHdrUnit, RenderMaterial.defaultEmissiveStrength);
    // A default directional light is one unit of illuminance: π units of
    // luminance on a white diffuse surface, which is lux over π nits.
    expect(
      LightNode.defaultIntensity / frame.nitsPerHdrUnit,
      closeTo(3.14159265, 1e-6),
    );
  });
}
