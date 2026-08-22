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

import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';
import 'package:flutter3d/src/engine/scene/scene.dart';
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

  test('the fallbacks it is not given are white and the neutral normal', () {
    // **Every application in this repository passed the same two**, uploaded on
    // the spot — four `main.dart`s did it twice each — so the required
    // arguments were a question with one answer. They are still parameters: a
    // renderer drawing into somebody else's colour space may want its white
    // somewhere other than 1.0.
    final device = FakeBackend();

    final renderer = Renderer.create(device: device);

    expect(renderer.fallbackAlbedo, isNotNull);
    expect(renderer.fallbackNormal, isNotNull);
    expect(device.uploadedPixels.length, 2);
    expect(device.uploadedPixels[0].buffer.asUint8List(),
        <int>[255, 255, 255, 255],
        reason: 'an untextured surface is not its own base colour');
    // (0, 0, 1) encoded into 0..1: sampling it perturbs nothing, which is why
    // the shader needs no "has a normal map" branch.
    expect(device.uploadedPixels[1].buffer.asUint8List(),
        <int>[128, 128, 255, 255],
        reason: 'the default normal map is not flat');
  });

  test('and the ones it is given are the ones it uses', () {
    final device = FakeBackend();
    final texel = device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData(4),
    )!;

    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel,
      fallbackNormal: texel,
    );

    expect(renderer.fallbackAlbedo, same(texel));
    expect(renderer.fallbackNormal, same(texel));
    expect(device.uploadedPixels.length, 1,
        reason: 'it uploaded a fallback it had been handed');
  });

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

  test('a frame is drawn into a texture nothing is still reading', () {
    // **A frame you could watch being drawn.** The composite writes the picture
    // a caller presents, and presenting hands *that same allocation* to
    // Flutter, which composites on its own thread on its own schedule — so the
    // next frame's clear and passes land in the texture the screen is reading.
    // On a moving scene nobody sees it; on a still one it flickers, which is
    // how it was found: an editor holding a level with the camera parked.
    //
    // **A ring of a fixed depth is a guess, and every depth was wrong.** Three
    // flickered, eight flickered less, sixteen stopped it on one machine —
    // which says nothing about the next, because the depth depends on the
    // display's rate, the build's speed and how far behind the GPU is. So the
    // depth is not chosen: a texture comes back when the backend says the work
    // that read it is done.
    final device = FakeBackend()..completesImmediately = false;
    final renderer = Renderer.create(device: device);
    final scene = Scene()..add(CameraNode());
    final view = RenderView(camera: scene.cameras.single);

    Object? drawFrame() => renderer
        .render(
          width: 64,
          height: 64,
          scene: scene,
          views: <RenderView>[view],
        )
        .frame
        .backend;

    // Nothing has finished, so each frame needs a texture of its own.
    final frames = <Object?>[for (var i = 0; i < 4; i++) drawFrame()];
    expect(frames.toSet(), hasLength(4),
        reason: 'a frame was drawn into a texture the last one handed over');
    expect(renderer.framesInFlight, 4);

    // As frames finish, their textures come back and the count stops climbing:
    // the depth is what this machine turned out to need.
    for (var i = 0; i < 6; i++) {
      device.finishOldestFrame();
      drawFrame();
    }
    expect(renderer.framesInFlight, 4,
        reason: 'it kept allocating after the finished ones came back');

    // And a backend that finishes as it goes needs exactly one.
    final quick = FakeBackend();
    final other = Renderer.create(device: quick);
    final quickScene = Scene()..add(CameraNode());
    for (var i = 0; i < 5; i++) {
      other.render(
        width: 64,
        height: 64,
        scene: quickScene,
        views: <RenderView>[RenderView(camera: quickScene.cameras.single)],
      );
    }
    expect(other.framesInFlight, 1,
        reason: 'a synchronous backend was given a rotation it cannot need');
  });
}
