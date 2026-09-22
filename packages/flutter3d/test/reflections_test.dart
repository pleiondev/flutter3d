/// Screen-space reflections land where the ray went.
///
///     flutter test test/reflections_test.dart
///
/// The first thing in this tree to compare a pixel of this effect against
/// anything. Until it existed the march was covered by the fact that
/// `('FullscreenVertex', 'Reflections')` links, which says nothing about where
/// a reflection lands — and two independent things about the march were wrong
/// for as long as that was the whole of the coverage.
///
/// **One: the march read the surface buffer upside down.** Screen position came
/// out of clip space as `ndc.xy * 0.5 + 0.5`, where every other lookup in the
/// engine uses `0.5 - ndc.y * 0.5` against an origin-adjusted matrix. The two
/// agree in a browser, whose row zero is at the bottom, and are mirrored about
/// the middle of the frame on Impeller and here. That is why the effect "did
/// not work": it marched into the reflection of the frame.
///
/// **Two: the thickness was compared in window depth.** A hit needs the ray to
/// be *behind* what was drawn at the pixel it lands on, and to be behind it by
/// less than the surface is thick. The first is an ordering and window depth
/// answers it exactly; the second is a distance and window depth cannot answer
/// it at all, because a fixed difference in it is centimetres against the near
/// plane and metres across the room. Both were being asked of one subtraction.
///
/// The scene is a polished floor with one bright cube standing on it, drawn
/// with `debugOnly` so the frame holds the reflection and nothing else. Every
/// lit pixel is then a pixel the march claimed a hit on, which is what makes a
/// count mean something.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

/// A polished floor with a bright cube standing on it.
///
/// The floor is a slab rather than a plane so the march has something with a
/// thickness to step into, and its roughness is well under the shader's
/// `polish` cut-off of 0.18 — a rough floor reflects nothing by design, and a
/// fixture that forgot that would compare two black frames and agree.
///
/// The cube is emissive rather than lit: what the reflection is *of* has to be
/// bright whatever the lights do, or a hit and a miss differ by a few levels of
/// grey and no threshold tells them apart.
({Scene scene, CameraNode camera}) _mirrorRoom() {
  final scene = Scene()..ambientIntensity = 0.15;
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(12.0, 0.4, 12.0)).build(),
      ),
      Material(
        name: 'floor',
        baseColor: Vector4(0.05, 0.05, 0.06, 1.0),
        lighting: LightingModel.lambert,
        roughness: 0.05,
      ),
      name: 'floor',
    )..setPosition(0.0, -0.2, 0.0),
  );

  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build(),
      ),
      Material(
        name: 'beacon',
        baseColor: Vector4(0.0, 0.0, 0.0, 1.0),
        emissive: Vector3(1.0, 0.35, 0.1),
        lighting: LightingModel.lambert,
        roughness: 0.9,
      ),
      name: 'beacon',
    )..setPosition(0.0, 0.5, 0.0),
  );

  // Low and in front, so the strip of floor between the camera and the cube
  // fills the bottom of the frame. That strip is the only place a reflection of
  // the cube can land.
  final camera = CameraNode()
    ..setPosition(0.0, 1.1, -3.6)
    ..lookAt(Vector3(0.0, 0.35, 0.0));
  return (scene: scene, camera: camera);
}

/// Reflections showing only what the march found.
///
/// [thickness] is in world metres, and the stride is fixed at 0.1 so the two
/// can be compared: a thickness under the stride is a surface a step can jump
/// clean over, and one above it is a surface a step must land in.
RenderSettings _settings({required bool on, double thickness = 0.15}) =>
    RenderSettings(
      bloom: const BloomSettings(enabled: false),
      shadows: const ShadowSettings(enabled: false),
      reflections: ReflectionSettings(
        enabled: on,
        steps: 48,
        stride: 0.1,
        thickness: thickness,
        intensity: 1.0,
        debugOnly: true,
      ),
    );

Future<Uint8List> _draw(RenderSettings settings) async {
  final it = cpuTestDevice(width: _width, height: _height);
  final renderer = Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );
  final room = _mirrorRoom();
  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: room.scene,
    views: <RenderView>[RenderView(camera: room.camera)],
    settings: settings,
  );
  final pixels = await it.device.readPixels(frame.frame);
  expect(pixels, isNotNull);
  return pixels!.buffer.asUint8List();
}

/// Pixels the march claimed a hit on.
int _hits(Uint8List rgba) {
  var lit = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i] + rgba[i + 1] + rgba[i + 2] > 12) lit++;
  }
  return lit;
}

/// The band of rows holding hits, top first.
({int first, int last}) _band(Uint8List rgba) {
  var first = _height, last = -1;
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final i = (y * _width + x) * 4;
      if (rgba[i] + rgba[i + 1] + rgba[i + 2] <= 12) continue;
      if (y < first) first = y;
      if (y > last) last = y;
    }
  }
  return (first: first, last: last);
}

void main() {
  test('off is exactly off', () async {
    // The claim every recorded golden rests on. Reflections are off in all but
    // one of them, and "off" has to mean the frame is the frame that was
    // recorded, not one that resembles it.
    final without = await _draw(_settings(on: false));
    final plain = await _draw(
      const RenderSettings(
        bloom: BloomSettings(enabled: false),
        shadows: ShadowSettings(enabled: false),
      ),
    );
    expect(
      without,
      orderedEquals(plain),
      reason: 'a disabled reflection changed the picture',
    );
  });

  test('the polished floor holds the cube upside down under it', () async {
    // The effect existing at all, which nothing had ever asked. With
    // `debugOnly` the frame is black except where the march found something, so
    // a black frame is an effect that does nothing — which is what this
    // returned before the origin convention was fixed.
    //
    // Mutation: put the old screen mapping back — `sv = ny * 0.5 + 0.5` in the
    // march and `vv * 2.0 - 1.0` in `worldFrom`. The march reads the frame
    // mirrored top to bottom, finds nothing that has anything to do with the
    // ray, and the count goes from 570 to **0**.
    final frame = await _draw(_settings(on: true));
    final hits = _hits(frame);
    expect(
      hits,
      greaterThan(400),
      reason:
          'the march found $hits pixels: a polished floor with a bright cube '
          'standing on it is reflecting nothing',
    );

    // And it is below the cube rather than anywhere else. The cube's silhouette
    // ends around row 47; the reflection begins there, at the foot of the cube,
    // and runs to the bottom edge — which is what the mirror image of something
    // standing on a floor looks like. A march that found the right number of
    // hits in the wrong half of the frame would pass the count alone, and the
    // mirrored march it replaced found them nowhere at all.
    final band = _band(frame);
    expect(band.first, inInclusiveRange(42, 52));
    expect(band.last, greaterThan(_height - 6));
  });

  test('the thickness is a distance in metres', () async {
    // The half that made the effect wrong rather than absent, and the reason
    // this is asserted as a *ratio between two thicknesses* rather than as a
    // picture: a thickness compared in window depth still produces a plausible
    // reflection here. What it cannot do is respond to the number.
    //
    // A thickness of 0.005 m is a twentieth of the stride: a step of 0.1 m
    // straddles a surface that thin nearly every time, so almost nothing is
    // found. At 0.15 m — a little over the stride — every step that crosses a
    // surface lands inside it and the whole mirror image appears.
    //
    // Mutation: compare `nz - sceneDepth` against `thickness`, which is what
    // this did. 0.005 of window depth is the better part of a metre at this
    // range, so the thin setting finds as much as the thick one: **575 against
    // 32**, and the assertion below goes red on the first line.
    final thin = _hits(await _draw(_settings(on: true, thickness: 0.005)));
    final thick = _hits(await _draw(_settings(on: true, thickness: 0.15)));
    expect(
      thin,
      lessThan(100),
      reason:
          'a surface five millimetres thick caught $thin pixels of a march '
          'that steps ten centimetres at a time: the thickness is not being '
          'read as a distance',
    );
    expect(
      thick,
      greaterThan(thin * 4),
      reason:
          'thickening the surface thirtyfold took the hits from $thin to '
          '$thick: the number is not reaching the comparison',
    );
  });
}
