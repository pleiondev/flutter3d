/// A low caster's shadow in the last cascade, held against where the shadow
/// actually is.
///
///     flutter test test/far_cascade_shadow_test.dart
///
/// **The last cascade is fitted to the whole level, and its depth bias was a
/// share of the whole level's depth.** `ShadowSettings.bias` is in a
/// cascade's stored depth, and the last cascade's depth ran across the sphere
/// round every caster: in the valley below, 880 m square, that was 1493 m, so
/// 0.0015 of it was 2.24 m along the light. Past the second split, about
/// twenty-three metres out at the default sixty-metre fit, every fragment
/// falls to that cascade, and a boat or a car standing a metre off the
/// ground was nearer the light than its own shadow by less than the bias. Its
/// shadow came in only once the near cascades reached it — what River Sortie
/// showed with its bridges and tankers.
///
/// Two changes, measured here one at a time on the 1.2 m box: 58 of the 211
/// floor pixels its shadow covers were drawn dark before, 143 once no
/// cascade's bias may exceed the nearest cascade's in metres (the floor of
/// one stored half-float step still holds, 0.73 m over that depth), and 175
/// once the cascades' depth is fitted to the casters' own extent along the
/// light (860 m here rather than 1493 m, which brings that floor to 0.42 m).
/// The near cascades' floor, which they owe to reaching back to the furthest
/// caster towards the sun, came from 0.31 m to 0.18 m with it.
///
/// **The truth is computed, not recorded.** A box on a plane under a
/// directional light has a shadow anybody can work out: a floor point is in
/// it when the ray from it towards the sun enters the box. So each pixel's
/// floor point is found by unprojecting through the same camera, and the
/// frame is asked two questions: how much of the true shadow it drew, and
/// how much lit floor it darkened. The second is the guard against acne — a
/// smaller bias that let the floor shadow itself would pass the first and
/// fail this one.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 160;
const int _height = 120;

/// Which way the sunlight travels: low in the side of the frame, so the box's
/// shadow falls beside it rather than behind it, out of the camera's sight.
final Vector3 _sunTravels = Vector3(-1.0, -0.9, 0.1);

/// The box: 8 m across, 30 m long, standing [_boxHeight] off the floor with
/// its middle at [_boxZ] — 31 m from the camera, past the second split, so
/// its shadow is the last cascade's.
const double _boxHeight = 1.2;
const double _boxZ = -20.0;

CameraNode _camera() =>
    CameraNode(
        projection: const PerspectiveProjection(
          fovY: 0.85,
          near: 0.5,
          far: 400.0,
        ),
      )
      ..setPosition(0.0, 11.0, 11.0)
      ..lookAt(Vector3(0.0, 0.0, -60.0));

Future<Uint8List> _shot({required bool shadows}) async {
  final it = cpuTestDevice(width: _width, height: _height);
  final renderer = Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );
  RenderMaterial grey(String name) => RenderMaterial(
    name: name,
    baseColor: LinearColor.fromSrgb(0.7, 0.7, 0.7, 1.0),
    lighting: LightingModel.lambert,
  );
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          it.device,
          const PlaneShape(width: 880.0, depth: 880.0).build(),
        ),
        grey('valley'),
        name: 'valley',
      ),
    )
    ..add(
      MeshNode(
        DeviceMesh.upload(
          it.device,
          CuboidShape(size: Vector3(8.0, _boxHeight, 30.0)).build(),
        ),
        grey('box'),
        name: 'box',
      )..setPosition(0.0, _boxHeight / 2, _boxZ),
    )
    ..add(
      LightNode(
        type: LightType.directional,
        intensity: 0.55 * Photometric.legacyUnit,
        castsShadow: true,
        name: 'sun',
      )..setLocalForward(_sunTravels),
    );
  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[RenderView(camera: _camera())],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      // The defaults otherwise: three cascades of 1024, fitted to 60 m.
      shadows: ShadowSettings(enabled: shadows),
    ),
  );
  final pixels = await it.device.readback(frame.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels.buffer.asUint8List();
}

/// Where along [d] from [o] the ray enters the box [lo]–[hi], or null.
double? _enter(Vector3 o, Vector3 d, Vector3 lo, Vector3 hi) {
  var t0 = 0.0, t1 = double.infinity;
  for (var a = 0; a < 3; a++) {
    if (d[a].abs() < 1e-12) {
      if (o[a] < lo[a] || o[a] > hi[a]) return null;
      continue;
    }
    final ta = (lo[a] - o[a]) / d[a], tb = (hi[a] - o[a]) / d[a];
    t0 = math.max(t0, math.min(ta, tb));
    t1 = math.min(t1, math.max(ta, tb));
    if (t0 > t1) return null;
  }
  return t0;
}

/// Per pixel: true where the floor is in the box's shadow, false where it is
/// lit floor, null where the pixel shows no floor.
List<bool?> _truth() {
  final inverse = Matrix4.inverted(_camera().viewProjection(_width / _height));
  final toSun = _sunTravels.normalized()..negate();
  final lo = Vector3(-4.0, 0.0, _boxZ - 15.0);
  final hi = Vector3(4.0, _boxHeight, _boxZ + 15.0);
  bool? at(int x, int y) {
    final nx = (x + 0.5) / _width * 2.0 - 1.0;
    final ny = 1.0 - (y + 0.5) / _height * 2.0;
    final near = inverse.transformed(Vector4(nx, ny, 0.0, 1.0));
    final far = inverse.transformed(Vector4(nx, ny, 1.0, 1.0));
    final o = near.xyz / near.w;
    final d = (far.xyz / far.w - o)..normalize();
    if (d.y >= 0.0) return null;
    final t = -o.y / d.y;
    final box = _enter(o, d, lo, hi);
    if (box != null && box < t) return null;
    final floor = o + d * t;
    return _enter(floor + toSun * 1e-3, toSun, lo, hi) != null;
  }

  return <bool?>[
    for (var y = 0; y < _height; y++)
      for (var x = 0; x < _width; x++) at(x, y),
  ];
}

void main() {
  test('a caster a metre high keeps its shadow in the last cascade', () async {
    // Mutations, each run and seen to fail here:
    //  * the cap in `renderer_shadow_pass.dart` lifted (`nearMetres` →
    //    `double.infinity`) with the depth fit kept: the first expectation;
    //  * the depth fitted to the sphere again (`sceneDepth` → `sceneRadius`)
    //    with the cap kept: 143 of 211, the first expectation;
    //  * the stored-step floor dropped: the second expectation.
    final lit = await _shot(shadows: false);
    final shaded = await _shot(shadows: true);
    final truth = _truth();

    var inShadow = 0, drawn = 0, spoilt = 0;
    for (var i = 0; i < truth.length; i++) {
      // A shadow is the only thing that darkens the floor between the two.
      final dark = shaded[i * 4 + 1] < lit[i * 4 + 1] - 8;
      if (truth[i] == true) {
        inShadow++;
        if (dark) drawn++;
      } else if (truth[i] == false && dark) {
        spoilt++;
      }
    }

    expect(inShadow, greaterThan(150), reason: 'the frame shows the shadow');
    expect(
      drawn / inShadow,
      greaterThan(0.75),
      reason:
          '$drawn of the $inShadow floor pixels in the box\'s shadow were '
          'drawn dark',
    );
    // What is drawn dark outside the true shadow is its edge in the last
    // cascade's texels, a metre and a half wide here; the floor shadowing
    // itself would be counted across the whole valley.
    expect(
      spoilt,
      lessThan(inShadow ~/ 4),
      reason: '$spoilt lit floor pixels were drawn in shadow',
    );
  });
}
