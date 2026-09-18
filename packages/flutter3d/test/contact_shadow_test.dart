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
import 'package:vector_math/vector_math.dart';

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
({Scene scene, CameraNode camera}) _boxOnPlane({required bool sun}) {
  final scene = Scene()..ambientIntensity = 0.35;
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  MeshNode slab(Vector3 size, Vector3 at, String name) => MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: size).build()),
    Material(
      name: name,
      baseColor: Vector4(0.75, 0.75, 0.75, 1.0),
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
      LightNode(type: LightType.directional, intensity: 2.0, name: 'sun')
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
        intensity: 8.0,
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

Future<Uint8List> _draw(RenderSettings settings, {bool sun = true}) async {
  final engine = _engine();
  final room = _boxOnPlane(sun: sun);
  final frame = engine.renderer.render(
    width: _width,
    height: _height,
    scene: room.scene,
    views: <RenderView>[RenderView(camera: room.camera)],
    settings: settings,
  );
  final pixels = await engine.device.readPixels(frame.frame);
  expect(pixels, isNotNull);
  return pixels!.buffer.asUint8List();
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
}
