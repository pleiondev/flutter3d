/// The look the composite puts on a frame: grading, vignette, grain, dispersion.
///
///     flutter test test/look_test.dart
///
/// Rendered rather than asserted on the settings object, because the thing worth
/// pinning is not that a field holds a number — it is that the number reaches the
/// picture, reaches it in the right place, and that leaving it alone changes
/// nothing at all.
///
/// **The last of those is the one that matters most.** Thirty golden images in
/// this repository composite through this pass. Every knob has to default to an
/// operation that cancels *exactly* — multiplying by one, adding zero — and not
/// merely to something close, or every reference image moves by a bit.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 64;

({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera})
_room() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  final scene = Scene();
  // A wall filling the view, mid grey and unlit, so every pixel of the frame
  // carries the same value: anything the composite does then shows up as a
  // difference between pixels rather than being lost in the shading.
  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(60.0, 60.0, 1.0)).build(),
      ),
      Material(
        name: 'wall',
        baseColor: Vector4(0.5, 0.5, 0.5, 1.0),
        lighting: LightingModel.unlit,
      ),
      name: 'wall',
    )..setPosition(0.0, 0.0, -10.0),
  );

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.1,
      far: 100.0,
    ),
  );
  camera.lookAt(Vector3(0.0, 0.0, -1.0));
  scene.add(camera);

  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
  );
}

Future<Uint8List> _draw(
  ({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) it,
  RenderSettings settings,
) async {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[
      RenderView(camera: it.camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: settings,
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

/// The red channel at a pixel.
int _red(Uint8List pixels, int x, int y) => pixels[(y * _width + x) * 4];

void main() {
  group('a look nobody asked for', () {
    test('is neutral by construction', () {
      // The settings object's own answer, which the renderer reads to decide
      // whether there is anything to do. Mutation: give any field a default
      // that is not its identity — fails here before it can fail a golden.
      expect(const LookSettings().isNeutral, isTrue);
    });

    test('and every knob taken alone breaks that', () {
      // Mutation: leave one field out of `isNeutral` — fails on that field.
      expect(const LookSettings(contrast: 1.1).isNeutral, isFalse);
      expect(const LookSettings(saturation: 0.9).isNeutral, isFalse);
      expect(const LookSettings(temperature: 0.2).isNeutral, isFalse);
      expect(const LookSettings(vignette: 0.3).isNeutral, isFalse);
      expect(const LookSettings(grain: 0.02).isNeutral, isFalse);
      expect(const LookSettings(chromaticAberration: 0.004).isNeutral, isFalse);
    });

    test('and changes the frame by not one byte', () async {
      // **The promise the goldens rest on.** Not "close enough": identical.
      //
      // Mutation: make the contrast pivot `(c - 0.5) * k + 0.5` unconditional
      // with `k` defaulting to 0.999, or centre the grain on 0.5 instead of 0 —
      // either is invisible to the eye and fails here immediately.
      final it = _room();
      final without = await _draw(it, const RenderSettings());
      final neutral = await _draw(
        it,
        const RenderSettings(look: LookSettings()),
      );

      expect(neutral, equals(without));
    });
  });

  group('a vignette', () {
    test('darkens the corners and leaves the middle alone', () async {
      // Mutation: drop the `clamp` on the radius, or measure it from the corner
      // instead of the centre — the middle darkens and this fails.
      final it = _room();
      final plain = await _draw(it, const RenderSettings());
      final dark = await _draw(
        it,
        const RenderSettings(look: LookSettings(vignette: 0.8)),
      );

      expect(
        _red(dark, _width ~/ 2, _height ~/ 2),
        equals(_red(plain, _width ~/ 2, _height ~/ 2)),
        reason: 'the centre is the one place a vignette must not touch',
      );
      expect(
        _red(dark, 1, 1),
        lessThan(_red(plain, 1, 1)),
        reason: 'the corner is the one place it must',
      );
    });

    test('and reaches the corner harder than the edge', () async {
      // The falloff is radial, so a corner is further from the centre than the
      // middle of an edge and has to be darker. Mutation: use the larger of the
      // two axes instead of the length — corner and edge come out equal.
      final it = _room();
      final dark = await _draw(
        it,
        const RenderSettings(look: LookSettings(vignette: 0.8)),
      );

      expect(_red(dark, 1, 1), lessThan(_red(dark, _width ~/ 2, 1)));
    });
  });

  group('grading', () {
    test('pivots contrast about mid grey rather than about black', () async {
      // **This is the assertion that tells the two implementations apart.** The
      // obvious version of contrast is `c * k`, which pivots about black and so
      // brightens everything — an exposure change wearing a contrast label. A
      // pivot at mid grey pushes values apart *around* it: below the pivot they
      // darken, above it they brighten.
      //
      // This wall lands at about 0.30 in the working space — measured, not
      // assumed, since exposure and the tone map both sit between the material
      // and here — which is below the pivot. So raising contrast must make it
      // **darker**. Under `c * k` it would come out brighter, and that is the
      // mutation: drop the `- 0.5` and `+ 0.5` and this fails.
      final it = _room();
      final plain = await _draw(it, const RenderSettings());
      final punchy = await _draw(
        it,
        const RenderSettings(look: LookSettings(contrast: 1.6)),
      );

      final middle = _red(plain, _width ~/ 2, _height ~/ 2);
      expect(
        _red(punchy, _width ~/ 2, _height ~/ 2),
        lessThan(middle),
        reason: 'a value below the pivot darkens; about black it would not',
      );
    });

    test('and saturation at zero leaves grey behind', () async {
      // Mutation: mix towards the wrong end — a grey wall would stay grey
      // either way, so this uses a coloured one to tell the two apart.
      final it = _room();
      (it.scene.root.children.first as MeshNode).material.baseColor.setValues(
        0.9,
        0.2,
        0.2,
        1.0,
      );

      final plain = await _draw(it, const RenderSettings());
      final grey = await _draw(
        it,
        const RenderSettings(look: LookSettings(saturation: 0.0)),
      );

      final x = _width ~/ 2;
      final y = _height ~/ 2;
      final i = (y * _width + x) * 4;
      expect(
        grey[i],
        closeTo(grey[i + 1], 2),
        reason: 'red and green agree when nothing is saturated',
      );
      expect(
        _red(plain, x, y),
        greaterThan(grey[i]),
        reason: 'and the red wall was redder before',
      );
    });
  });
}
