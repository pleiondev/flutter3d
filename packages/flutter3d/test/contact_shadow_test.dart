/// A box resting on a plane gains a seam at the join — `gfx-76n`.
///
///     flutter test test/contact_shadow_test.dart
///
/// **What the shadow map cannot do at any resolution.** A box meets a floor
/// along a line, and the shadow that belongs at that line is a texel of the map
/// or less. Raising the resolution moves it closer to right without arriving;
/// raising the bias far enough to stop the acne a tight contact produces
/// detaches the shadow from the box, which is the familiar look of a prop
/// floating a centimetre above the floor. So the first few centimetres are
/// marched against the depth the scene already wrote instead.
///
/// Three things have to hold, and they are the three the occlusion pass beside
/// this one is held to:
///
///   * off is *exactly* off, because every golden in the repository was
///     recorded against a multiplier of one;
///   * the floor right against the box goes darker than the floor a little way
///     off, under the same light;
///   * a scene with nothing directional in it draws no seam, because there is
///     nothing to march toward and a direction invented for the occasion would
///     put a dark edge under everything.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const int _width = 80;
const int _height = 64;

({CpuDevice device, Renderer renderer}) _engine() {
  final it = cpuTestDevice(width: _width, height: _height);
  return (
    device: it.device,
    renderer: Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    ),
  );
}

/// A box standing on a floor, lit by one sun low to the left.
///
/// Low on purpose: the sun's own shadow is what a map would draw, and the point
/// of the row is the millimetres the map misses, so the light comes in at a
/// slant where a march of a quarter of a metre reaches the box from the floor
/// beside it. The map itself is off in every case below — with it on, the seam
/// this test measures would sit inside a shadow the map already drew, and the
/// test would be measuring the map.
({Scene scene, CameraNode camera}) _boxOnPlane({
  required bool sun,
  bool sunCasts = true,
}) {
  final scene = Scene()..ambientIntensity = 0.35 * Photometric.legacyUnit;
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  MeshNode slab(Vector3 size, Vector3 at, String name) => MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: size).build()),
    RenderMaterial(
      name: name,
      baseColor: LinearColor.fromSrgb(0.75, 0.75, 0.75, 1.0),
      lighting: LightingModel.lambert,
    ),
    name: name,
  )..setPosition(at.x, at.y, at.z);

  // The floor's top face is y = 0; the box sits on it, half a metre a side, so
  // its own centre is at y = 0.25 and it touches along four lines.
  scene.add(slab(Vector3(8.0, 0.4, 8.0), Vector3(0.0, -0.2, 0.0), 'floor'));
  scene.add(slab(Vector3(0.5, 0.5, 0.5), Vector3(0.0, 0.25, 0.0), 'box'));

  if (sun) {
    scene.add(
      LightNode(
          type: LightType.directional,
          intensity: 2.0 * Photometric.legacyUnit,
          castsShadow: sunCasts,
          name: 'sun',
        )
        // Pointing down and to the right, so the sun is up and to the left and
        // the floor on the box's right is the side the seam belongs on.
        ..setLocalForward(Vector3(0.55, -0.83, -0.1)),
    );
  } else {
    // A lamp instead, so the scene is lit but nothing directional is in it. A
    // scene with no lights at all would take the default light, which *is*
    // directional and would not test this.
    scene.add(
      LightNode(
        type: LightType.point,
        intensity: 8.0 * Photometric.legacyUnit,
        range: 12.0,
        name: 'lamp',
      )..setPosition(-2.0, 2.5, -1.0),
    );
  }

  final camera = CameraNode()
    ..setPosition(0.0, 0.9, -2.6)
    ..lookAt(Vector3(0.0, 0.1, 0.0));
  return (scene: scene, camera: camera);
}

/// A thin plate held a few centimetres over a floor, the sun low behind it —
/// the hem of a cloth, in the shape that drew a comb.
///
/// The plate's shadow lands on the floor in front of it, toward the camera,
/// and its edge runs across the screen. Every pixel along that edge marches
/// from a different offset of the 4 x 4 pattern, and with nothing to average
/// them the edge is exactly as ragged as the pattern.
({Scene scene, CameraNode camera}) _plateOverFloor() {
  final scene = Scene()..ambientIntensity = 0.35 * Photometric.legacyUnit;
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  MeshNode slab(Vector3 size, Vector3 at, String name) => MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: size).build()),
    RenderMaterial(
      name: name,
      baseColor: LinearColor.fromSrgb(0.75, 0.75, 0.75, 1.0),
      lighting: LightingModel.lambert,
    ),
    name: name,
  )..setPosition(at.x, at.y, at.z);

  scene
    ..add(slab(Vector3(8.0, 0.4, 8.0), Vector3(0.0, -0.2, 0.0), 'floor'))
    // Two centimetres thick, its underside three centimetres off the floor.
    ..add(slab(Vector3(1.4, 0.02, 0.6), Vector3(0.0, 0.04, 0.0), 'plate'))
    ..add(
      LightNode(
          type: LightType.directional,
          intensity: 1.0 * Photometric.legacyUnit,
          castsShadow: false,
          name: 'sun',
        )
        // Low and behind the plate, so its shadow falls toward the camera.
        ..setLocalForward(Vector3(0.1, -0.5, -0.85)),
    );

  final camera = CameraNode()
    ..setPosition(0.0, 1.6, -1.5)
    ..lookAt(Vector3(0.0, 0.0, -0.3));
  return (scene: scene, camera: camera);
}

RenderSettings _settings({required bool contact}) => RenderSettings(
  bloom: const BloomSettings(enabled: false),
  // Off throughout: with it on, the seam would sit inside a shadow the map
  // drew and this test would be measuring the map.
  shadows: const ShadowSettings(enabled: false),
  contactShadows: ContactShadowSettings(
    enabled: contact,
    // Half a metre rather than the default quarter, because this scene is
    // measured in half-metre boxes — the same "the radius has to suit the
    // scene" the occlusion pass carries.
    length: 0.5,
    steps: 16,
    strength: 1.0,
  ),
);

Future<Uint8List> _draw(
  RenderSettings settings, {
  bool sun = true,
  bool sunCasts = true,
  ({Scene scene, CameraNode camera})? room,
}) async {
  final engine = _engine();
  final at = room ?? _boxOnPlane(sun: sun, sunCasts: sunCasts);
  final frame = engine.renderer.render(
    width: _width,
    height: _height,
    scene: at.scene,
    views: <RenderView>[RenderView(camera: at.camera)],
    settings: settings,
  );
  final pixels = await engine.device.readback(frame.frame);
  expect(pixels, isNotNull);
  return pixels.buffer.asUint8List();
}

/// Total red across [x0]..[x1] on row [y], which on this grey scene is
/// brightness.
int _rowSum(Uint8List rgba, int y, int x0, int x1) {
  var total = 0;
  for (var x = x0; x < x1; x++) {
    total += rgba[(y * _width + x) * 4];
  }
  return total;
}

void main() {
  test('off is exactly off', () async {
    // The claim the goldens rest on, and it is about arithmetic rather than
    // appearance: the multiplier is one, not a number that rounds to one.
    //
    // Two independent things make it so, the arrangement the occlusion pass
    // uses and for the reason it uses it: the composite zeroes the strength
    // when there is nothing to apply, *and* the sampler that must not be left
    // unbound gets the 1×1 white. Either alone would carry this test; both
    // together mean no mismatch between them can darken a frame that asked for
    // nothing.
    final without = await _draw(_settings(contact: false));
    final plain = await _draw(
      const RenderSettings(
        bloom: BloomSettings(enabled: false),
        shadows: ShadowSettings(enabled: false),
      ),
    );
    expect(
      without,
      orderedEquals(plain),
      reason: 'a disabled contact shadow changed the picture',
    );
  });

  test(
    'the floor against the box goes darker than the floor beyond it',
    () async {
      final without = await _draw(_settings(contact: false));
      final with_ = await _draw(_settings(contact: true));

      // **Where the box is, taken from the frame rather than assumed** — and the
      // assumption was wrong, which is why it is taken. The sun points along
      // +x, so it stands at -x; the camera looks along +z, and looking that way
      // puts +x on the *left* of the screen. So the shadowed side of the box is
      // the side a reader of the scene file would call its right and the picture
      // shows on its left. Reading the difference image put the seam at rows
      // 36–37 beside a silhouette spanning columns 32–47, and that is what the
      // numbers below are.
      //
      // The measurement is a difference of differences rather than an absolute:
      // what this claims is that the *join* darkens where the open floor does
      // not, which is what makes it a contact shadow rather than a dimmer.
      final near = _rowSum(without, 37, 26, 42) - _rowSum(with_, 37, 26, 42);
      final far = _rowSum(without, 48, 26, 42) - _rowSum(with_, 48, 26, 42);

      expect(
        near,
        greaterThan(0),
        reason: 'the floor at the join did not darken at all',
      );
      expect(
        near,
        greaterThan(far),
        reason:
            'the darkening was spread over the floor rather than at the join',
      );
    },
  );

  test(
    'a thin edge over the floor is smooth without a temporal resolve',
    () async {
      // The comb this pins: each pixel's march starts at its own cell of the
      // 4 x 4 pattern and keeps the hard answer that offset found, so along the
      // edge of a plate held off the floor the shadow alternated pixel by pixel
      // — measured before the fix at 204 190 208 185 across one row and
      // 177 0 181 163 across the next, a jump of 181 between neighbours. The
      // resolve averages the sixteen phases, and what is left along a row is
      // the one-level wobble of the output's own dither.
      final without = await _draw(
        _settings(contact: false),
        room: _plateOverFloor(),
      );
      final with_ = await _draw(
        _settings(contact: true),
        room: _plateOverFloor(),
      );
      int darkening(int x, int y) =>
          without[(y * _width + x) * 4] - with_[(y * _width + x) * 4];

      // The rows the shadow is on, found rather than assumed; the columns are
      // the plate's interior, clear of its two ends where the shadow does end.
      final rows = <int>[
        for (var y = 0; y < _height; y++)
          if (darkening(_width ~/ 2, y) > 20) y,
      ];
      expect(rows, isNotEmpty, reason: 'the plate cast no contact shadow');

      final jump = rows.fold(
        0,
        (worst, y) => <int>[
          worst,
          for (var x = 18; x < 60; x++)
            (darkening(x + 1, y) - darkening(x, y)).abs(),
        ].reduce((a, b) => a > b ? a : b),
      );
      expect(
        jump,
        lessThan(8),
        reason: 'neighbouring pixels along the edge differ by $jump levels',
      );
    },
  );

  test('a scene with no sun draws no seam', () async {
    // Nothing to march toward. The node declines rather than marching toward a
    // direction it made up, which would put a dark edge under every object in
    // a scene lit by lamps — the failure this case exists to catch.
    final without = await _draw(_settings(contact: false), sun: false);
    final with_ = await _draw(_settings(contact: true), sun: false);
    expect(
      with_,
      orderedEquals(without),
      reason: 'a scene with no directional light drew a contact shadow anyway',
    );
  });

  test('a sun that casts no map still gets its seam', () async {
    // The march reads the surface buffer and no shadow map, so a sun with
    // `castsShadow` cleared — contact shadows without paying for a map — is
    // the setup the pass is cheapest in. It took its direction from the map's
    // caster and switched off with the map.
    final casting = await _draw(_settings(contact: true));
    final without = await _draw(_settings(contact: false), sunCasts: false);
    final with_ = await _draw(_settings(contact: true), sunCasts: false);
    expect(
      with_,
      isNot(orderedEquals(without)),
      reason: 'clearing castsShadow on the sun switched contact shadows off',
    );
    expect(
      with_,
      orderedEquals(casting),
      reason: 'the seam should not depend on whether the sun casts a map',
    );
  });
}
