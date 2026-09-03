/// A sampler asking for more taps than this context has is clamped here,
/// before the call, and nowhere else.
///
///     flutter test --platform chrome test/anisotropy_test.dart
///
/// **The failure this exists for produces the right picture.**
/// `TEXTURE_MAX_ANISOTROPY_EXT` above what `EXT_texture_filter_anisotropic`
/// reports is `INVALID_VALUE`: the call is dropped, the taps stay as they
/// were, and the draw goes on to sample the texture perfectly well. Nothing in
/// the frame says so — WebGL reports rejection only into an error queue nobody
/// on the draw path reads. So the conformance suite, which asks whether the
/// picture arrived, cannot see this one; it takes reading the queue, which is
/// a thing only this backend has.
///
/// Chrome only, and on a real context rather than a mock, for the reason
/// `compressed_texture_test.dart` gives at more length: what is being asked is
/// whether a driver accepts a specific enum with a specific value, which is
/// exactly what a mock cannot answer.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A full-screen triangle whose corners all read the second texel.
final Float32List _triangle = Float32List.fromList(<double>[
  -1, -1, 0.5, 1, 1, 1, 1, 0.75, 0.5, //
  3, -1, 0.5, 1, 1, 1, 1, 0.75, 0.5,
  -1, 3, 0.5, 1, 1, 1, 1, 0.75, 0.5,
]);

final Uint16List _indices = Uint16List.fromList(<int>[0, 1, 2]);

WebGlDevice _device() {
  final device = WebGlDevice.create(
    width: 8,
    height: 8,
    sources: engineShaders,
  );
  if (device == null) fail('no WebGL2 context in this browser');
  return device;
}

/// Black then white, side by side. Sampled at u = 0.75 a bind that landed
/// comes back white, and one that was dropped leaves the clear colour.
TextureHandle _twoTexels(WebGlDevice device) {
  final pixels = ByteData(2 * 4);
  for (var i = 0; i < 4; i++) {
    pixels.setUint8(i, i == 3 ? 255 : 0);
    pixels.setUint8(4 + i, 255);
  }
  final texture = device.createTextureFromPixels(
    width: 2,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: pixels,
  );
  if (texture == null) fail('a two-texel texture could not be uploaded');
  return texture;
}

/// Draws the triangle through a trilinear sampler asking for [taps], and
/// answers the red channel at the centre.
Future<int> _drawThrough(WebGlDevice device, int taps) async {
  final texture = _twoTexels(device);
  final target = device.createTexture(
    const RenderTargetSpec(
      width: 8,
      height: 8,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  final vertex = device.shaders['ParticleVertex']!;
  final fragment = device.shaders['ParticleTextured']!;

  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          clearValue: Vector4(0.0, 1.0, 0.0, 1.0),
        ),
      ],
    ),
  );
  pass
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindPipeline(device.createPipeline(vertex, fragment))
    ..bindUniformBlock(vertex, 'ParticleInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindUniformBlock(fragment, 'FogInfo', <String, Float32List>{
      'fog': Float32List(4),
      'eye': Float32List(4),
    })
    ..bindTexture(
      fragment,
      'particle_texture',
      texture,
      sampler: SamplerOptions.trilinearRepeat.withAnisotropy(taps),
    )
    ..bindVertexData(ByteData.sublistView(_triangle), 3)
    ..bindIndexData(ByteData.sublistView(_indices), IndexType.int16, 3)
    ..draw();
  pass.submit();

  final read = await device.readPixels(target);
  if (read == null) fail('the target could not be read back at $taps taps');
  return read.buffer.asUint8List()[(4 * 8 + 4) * 4];
}

void main() {
  test('a request above the ceiling leaves no error behind', () async {
    final device = _device();
    device.debugDrainErrors('setup');

    // Above whatever this browser answers, by construction. Unclamped, this is
    // the value the extension rejects.
    await _drawThrough(device, device.maxAnisotropy * 2);

    expect(
      device.debugDrainErrors('after an above-ceiling anisotropic bind'),
      isNull,
      reason:
          'the taps were forwarded to texParameterf unclamped: the call '
          'was dropped with INVALID_VALUE and the texture kept whatever '
          'filtering the last bind left on it',
    );
    device.dispose();
  });

  test('and draws the same picture as a request the device can meet', () async {
    // The other half of the promise. An error-free clamp that clamped to
    // nothing — by skipping the bind, say — would pass the check above.
    final device = _device();

    final atCeiling = await _drawThrough(device, device.maxAnisotropy);
    final beyond = await _drawThrough(device, device.maxAnisotropy * 2);

    expect(beyond, atCeiling);
    expect(beyond, greaterThan(128), reason: 'neither draw sampled anything');
    device.dispose();
  });

  test('a context without the extension answers one tap, not zero', () {
    // `maxAnisotropy` is a count, and one means "no anisotropic filtering
    // here" rather than "unknown". The encoder skips the parameter entirely at
    // one, because the enum is unknown to a context without the extension and
    // setting it would be INVALID_ENUM on every single bind.
    final device = _device();

    expect(device.maxAnisotropy, greaterThanOrEqualTo(1));
    device.dispose();
  });
}
