/// What `Renderer.create` insists on, and what it must not.
///
/// The engine resolves every shader entry point it needs up front and throws on
/// the first one missing, which is the right moment to fail: a renderer without
/// its shaders draws a black screen and a null somewhere later.
///
/// The point of this file is the *second* half — that the list it insists on is
/// the list it actually uses. Particles were on it for months and read by
/// nobody: `ParticleContributor` resolves its own stages off the device, so the
/// two fields the renderer stored were dead, and an application with no
/// particles could not start a renderer because of them.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';

void main() {
  Renderer build(FakeBackend device) {
    final texel = device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData(4),
    )!;
    return Renderer.create(
      device: device,
      fallbackAlbedo: texel,
      fallbackNormal: texel,
    );
  }

  test('a renderer starts without the particle stages', () {
    // An application that draws no particles should not have to ship their
    // shaders. This is what stops the engine core from naming an extension.
    expect(
      () => build(FakeBackend(
        missingShaders: <String>{'Particle', 'ParticleVertex'},
      )),
      returnsNormally,
    );
  });

  test('a renderer refuses without a stage it does use', () {
    // The other half: the check is still real. MeshVertex is not optional, and
    // the error names it rather than failing later with a blank frame.
    expect(
      () => build(FakeBackend(missingShaders: <String>{'MeshVertex'})),
      throwsA(isA<StateError>().having(
        (e) => e.message, 'message', contains('MeshVertex'))),
    );
  });
}
