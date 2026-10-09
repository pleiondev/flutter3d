/// Depth for large worlds — `A2.8`–`A2.10` — and the level-of-detail
/// cross-fade — `A1.3`.
///
///     flutter test test/depth_precision_test.dart
///
/// **The arithmetic first, then the frame.** What a reversed or an infinite
/// projection does to a depth is a matter of four numbers in one row, and
/// is asked of the matrices directly; whether the renderer then draws the
/// same world with them — the sky still behind it, a mountain past any far
/// plane, a low box's shadow in a near cascade — is asked of the software
/// rasteriser, which keeps a float depth and so takes the reversed path.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/flutter3d.dart' as engine show RenderMaterial;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// [projection] applied to a point [distance] down the view axis, as NDC z
/// — in double precision from the matrix's own entries, so what is asked of
/// a float below is the float's and not the arithmetic's on the way.
double _depthAt(Matrix4 projection, double distance) {
  final s = projection.storage;
  final z = s[10] * -distance + s[14];
  final w = s[11] * -distance + s[15];
  return z / w;
}

/// [value] as a 32-bit float stores it.
double _float32(double value) => (Float32List(1)..[0] = value)[0];

void main() {
  _projections();
  _frames();
  _shadowFloor();
  _crossFade();
}

void _projections() {
  group('an infinite far plane', () {
    test('keeps everything in front of the near plane inside the range', () {
      const lens = PerspectiveProjection(far: double.infinity);
      final m = lens.toMatrix(1.5);
      expect(_depthAt(m, lens.near), closeTo(0.0, 1e-6));
      var previous = -1.0;
      for (final distance in <double>[1.0, 1e2, 1e4, 1e6, 1e8]) {
        final z = _depthAt(m, distance);
        expect(z, inInclusiveRange(0.0, 1.0), reason: 'at $distance m');
        expect(z, greaterThan(previous), reason: 'at $distance m');
        previous = z;
      }
    });

    test('is what the named constructor builds', () {
      const named = PerspectiveProjection.infinite(near: 0.25);
      expect(named.far, double.infinity);
      expect(
        named.toMatrix(1.0).storage,
        const PerspectiveProjection(
          near: 0.25,
          far: double.infinity,
        ).toMatrix(1.0).storage,
      );
    });

    test('is taken by an off-axis frustum too', () {
      final eye = OffAxisProjection.symmetric(far: double.infinity);
      final z = _depthAt(eye.toMatrix(1.0), 1e6);
      expect(z.isFinite, isTrue);
      expect(z, inInclusiveRange(0.0, 1.0));
    });
  });

  group('reversed depth', () {
    const lens = PerspectiveProjection(near: 0.1, far: 100.0);

    test('puts the near plane at one and the far plane at nought', () {
      final m = toReversedDepth(lens.toMatrix(1.0));
      expect(_depthAt(m, 0.1), closeTo(1.0, 1e-5));
      expect(_depthAt(m, 100.0), closeTo(0.0, 1e-5));
      expect(_depthAt(m, 1.0), greaterThan(_depthAt(m, 2.0)));
    });

    test('given twice gives the matrix back', () {
      final m = lens.toMatrix(1.3);
      final twice = toReversedDepth(toReversedDepth(m));
      for (var i = 0; i < 16; i++) {
        expect(twice.storage[i], closeTo(m.storage[i], 1e-6));
      }
    });

    test('worked out from the planes, an infinite one is near over '
        'distance', () {
      final m = withDepthPlanes(
        const PerspectiveProjection.infinite(near: 0.1).toMatrix(1.0),
        near: 0.1,
        far: double.infinity,
        reversed: true,
      )!;
      for (final distance in <double>[0.1, 1.0, 50.0, 1e4]) {
        expect(_depthAt(m, distance), closeTo(0.1 / distance, 1e-9));
      }
    });

    test('worked out from the planes, the ordinary row is the camera\'s to '
        'the bit', () {
      final m = lens.toMatrix(1.7);
      final rebuilt = withDepthPlanes(m, near: 0.1, far: 100.0)!;
      expect(rebuilt.storage, m.storage);
    });

    test('a matrix with no pair of planes to move is left alone', () {
      expect(
        withDepthPlanes(
          const OrthographicProjection().toMatrix(1.0),
          near: 0.1,
          far: 10.0,
        ),
        isNull,
      );
      final oblique = lens.toMatrix(1.0)..setEntry(2, 0, 0.3);
      expect(withDepthPlanes(oblique, near: 0.1, far: 10.0), isNull);
    });

    test('keeps two surfaces a centimetre apart at ten kilometres apart in '
        'a float, where the ordinary way round cannot', () {
      // The reason for all of it, in two lines of arithmetic. A float's
      // precision follows its exponent; the ordinary row crowds distant
      // depth against one, where the steps are 2⁻²⁴ apart, and the reversed
      // row puts it against nought, where they are as fine as the number.
      const near = 0.1;
      const far = double.infinity;
      final ordinary = const PerspectiveProjection(
        near: near,
        far: far,
      ).toMatrix(1.0);
      final reversed = withDepthPlanes(
        ordinary,
        near: near,
        far: far,
        reversed: true,
      )!;
      double stored(Matrix4 m, double d) => _float32(_depthAt(m, d));
      expect(stored(ordinary, 1e4), stored(ordinary, 1e4 + 0.01));
      expect(stored(reversed, 1e4), isNot(stored(reversed, 1e4 + 0.01)));
    });
  });
}

const int _width = 96;
const int _height = 72;

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

engine.RenderMaterial _unlit(String name, Vector4 color) =>
    engine.RenderMaterial(
      name: name,
      baseColor: _fromSrgb(color),
      lighting: LightingModel.unlit,
    );

Future<Uint8List> _frame({
  required Scene scene,
  required CameraNode camera,
  required bool reversed,
}) async {
  final it = _engine();
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColorSrgb: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      reversedDepth: reversed,
      sky: SkySettings(
        enabled: true,
        zenith: LinearColor(0.0, 0.0, 0.6),
        horizon: LinearColor(0.0, 0.0, 0.6),
        nadir: LinearColor(0.0, 0.0, 0.6),
        sunIntensity: 0.0,
      ),
    ),
  );
  final pixels = await it.device.readback(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels.buffer.asUint8List();
}

/// The colour at the middle of the frame.
List<int> _middle(Uint8List pixels) {
  final at = ((_height ~/ 2) * _width + _width ~/ 2) * 4;
  return pixels.sublist(at, at + 3);
}

void _frames() {
  group('the renderer, reversed', () {
    ({Scene scene, CameraNode camera}) world({
      required Projection projection,
      double wallAt = 40.0,
      double wallSize = 30.0,
    }) {
      final scratch = cpuTestDevice(width: 4, height: 4).device;
      final scene = Scene()
        // A red post in front of a green wall, both in front of the sky.
        ..add(
          MeshNode(
            DeviceMesh.upload(
              scratch,
              CuboidShape(size: Vector3(wallSize, wallSize, 1.0)).build(),
            ),
            _unlit('wall', Vector4(0.0, 1.0, 0.0, 1.0)),
            name: 'wall',
          )..setPosition(0.0, 0.0, wallAt),
        )
        ..add(
          MeshNode(
            DeviceMesh.upload(
              scratch,
              CuboidShape(size: Vector3(0.6, 30.0, 0.6)).build(),
            ),
            _unlit('post', Vector4(1.0, 0.0, 0.0, 1.0)),
            name: 'post',
          )..setPosition(0.0, 0.0, 10.0),
        );
      final camera = CameraNode(projection: projection)
        ..lookAt(Vector3(0.0, 0.0, 1.0));
      scene.add(camera);
      return (scene: scene, camera: camera);
    }

    test('draws what the ordinary way round draws', () async {
      // Mutations: the scene pass's `less` not turned (`_ReversedDepthEncoder`
      // passing compares through) leaves the clear everywhere; the sky drawn
      // at 0.999999 reversed paints over the wall and the post.
      final (:scene, :camera) = world(
        projection: const PerspectiveProjection(
          fovY: 1.2,
          near: 0.3,
          far: 500.0,
        ),
      );
      final ordinary = await _frame(
        scene: scene,
        camera: camera,
        reversed: false,
      );
      final reversed = await _frame(
        scene: scene,
        camera: camera,
        reversed: true,
      );
      final post = _middle(reversed);
      expect(post[0], greaterThan(200), reason: 'the post, $post');
      expect(post[1], lessThan(30), reason: 'the post, $post');
      var worst = 0;
      for (var i = 0; i < ordinary.length; i++) {
        worst = math.max(worst, (ordinary[i] - reversed[i]).abs());
      }
      expect(worst, lessThanOrEqualTo(2), reason: 'the two frames differ');
    });

    test('an infinite camera draws a wall twenty kilometres out', () async {
      for (final reversed in <bool>[false, true]) {
        final (:scene, :camera) = world(
          projection: const PerspectiveProjection.infinite(
            fovY: 1.2,
            near: 0.3,
          ),
          wallAt: 20000.0,
          wallSize: 30000.0,
        );
        // Nothing nearer: the post is out of the way.
        scene.meshes.firstWhere((n) => n.name == 'post').isVisible = false;
        final pixels = await _frame(
          scene: scene,
          camera: camera,
          reversed: reversed,
        );
        final wall = _middle(pixels);
        expect(
          wall[1],
          greaterThan(200),
          reason: 'the wall, reversed: $reversed — $wall',
        );
        expect(
          wall[2],
          lessThan(60),
          reason: 'the wall, reversed: $reversed — $wall',
        );
      }
    });
  });
}

const int _shadowWidth = 160;
const int _shadowHeight = 120;

/// Which way the sunlight travels: low, so a hand-high box throws a shadow a
/// few pixels wide beside itself.
final Vector3 _sunTravels = Vector3(-1.0, -0.35, 0.1);

/// The low box: 4 m across, 6 m long, [_lowHeight] tall, in the near
/// cascade a few metres in front of the camera.
const double _lowHeight = 0.1;
const double _lowZ = -2.0;

CameraNode _shadowCamera() =>
    CameraNode(
        projection: const PerspectiveProjection(
          fovY: 0.85,
          near: 0.2,
          far: 400.0,
        ),
      )
      ..setPosition(0.0, 3.0, 6.0)
      ..lookAt(Vector3(0.0, 0.0, -10.0));

Future<Uint8List> _shadowShot({
  required bool shadows,
  required bool reversed,
  bool halfFloat = false,
}) async {
  // `halfFloat` withholds 32-bit float targets, as Impeller reports none, so
  // the atlas stays in half floats and is turned round: mode one, the floor
  // taken at each fragment's own depth.
  final device = CpuDevice(
    width: _shadowWidth,
    height: _shadowHeight,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
    withhold: halfFloat
        ? const <DeviceFeature>[DeviceFeature.float32Renderable]
        : const <DeviceFeature>[],
  );
  final renderer = Renderer.create(
    device: device,
    fallbackAlbedo: texelOn(device, <int>[255, 255, 255, 255]),
    fallbackNormal: texelOn(device, <int>[128, 128, 255, 255]),
  );
  engine.RenderMaterial grey(String name) => engine.RenderMaterial(
    name: name,
    baseColor: LinearColor.fromSrgb(0.7, 0.7, 0.7, 1.0),
    lighting: LightingModel.lambert,
  );
  final scene = Scene()
    // A valley wide enough that the near cascade reaches back to its far
    // side towards the sun: hundreds of metres along the light, which is
    // what took the ordinary floor to a fifth of a metre.
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          const PlaneShape(width: 880.0, depth: 880.0).build(),
        ),
        grey('valley'),
        name: 'valley',
      ),
    )
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(4.0, _lowHeight, 6.0)).build(),
        ),
        grey('low box'),
        name: 'low box',
      )..setPosition(0.0, _lowHeight / 2, _lowZ),
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
    width: _shadowWidth,
    height: _shadowHeight,
    scene: scene,
    views: <RenderView>[RenderView(camera: _shadowCamera())],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      reversedDepth: reversed,
      shadows: ShadowSettings(enabled: shadows),
    ),
  );
  final pixels = await device.readback(frame.frame);
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

/// Per pixel: true where the floor is in the low box's shadow, false where
/// it is lit floor, null where the pixel shows no floor.
List<bool?> _shadowTruth() {
  final inverse = Matrix4.inverted(
    _shadowCamera().viewProjection(_shadowWidth / _shadowHeight),
  );
  final toSun = _sunTravels.normalized()..negate();
  final lo = Vector3(-2.0, 0.0, _lowZ - 3.0);
  final hi = Vector3(2.0, _lowHeight, _lowZ + 3.0);
  bool? at(int x, int y) {
    final nx = (x + 0.5) / _shadowWidth * 2.0 - 1.0;
    final ny = 1.0 - (y + 0.5) / _shadowHeight * 2.0;
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
    for (var y = 0; y < _shadowHeight; y++)
      for (var x = 0; x < _shadowWidth; x++) at(x, y),
  ];
}

/// How much of the low box's true shadow [shaded] drew dark against [lit],
/// and how many lit floor pixels it darkened.
({int inShadow, int drawn, int spoilt}) _score(
  Uint8List lit,
  Uint8List shaded,
  List<bool?> truth,
) {
  var inShadow = 0, drawn = 0, spoilt = 0;
  for (var i = 0; i < truth.length; i++) {
    final dark = shaded[i * 4 + 1] < lit[i * 4 + 1] - 8;
    if (truth[i] == true) {
      inShadow++;
      if (dark) drawn++;
    } else if (truth[i] == false && dark) {
      spoilt++;
    }
  }
  return (inShadow: inShadow, drawn: drawn, spoilt: spoilt);
}

void _shadowFloor() {
  group('a hand-high box in a near cascade', () {
    // `0.9-no-crutches.md`'s open line: the near cascades' bias could not go
    // below one stored half-float step of a cascade hundreds of metres deep
    // along the light — a fifth of a metre here — so a box a hand tall cast
    // a sliver where its shadow should be. Turned round, that step is taken
    // at the ground's own depth, where the half floats are finest; in 32-bit
    // floats there is no step to take.
    //
    // Mutations: `_shadowStorage` left at nought (the readers do not turn
    // the depth back) shadows the whole valley, which the acne guard
    // catches; the floor kept in `publishShadowParams` under reversal loses
    // the shadow again, which the first expectation catches.
    late final List<bool?> truth = _shadowTruth();

    for (final halfFloat in <bool>[false, true]) {
      test('keeps its shadow, reversed '
          '(${halfFloat ? 'half floats' : '32-bit floats'})', () async {
        final lit = await _shadowShot(
          shadows: false,
          reversed: true,
          halfFloat: halfFloat,
        );
        final on = _score(
          lit,
          await _shadowShot(
            shadows: true,
            reversed: true,
            halfFloat: halfFloat,
          ),
          truth,
        );
        expect(on.inShadow, greaterThan(40), reason: 'the frame shows it');
        expect(
          on.drawn / on.inShadow,
          greaterThan(0.55),
          reason:
              '${on.drawn} of the ${on.inShadow} floor pixels in the box\'s '
              'shadow were drawn dark',
        );
        expect(
          on.spoilt,
          lessThan(on.inShadow),
          reason: '${on.spoilt} lit floor pixels were drawn in shadow',
        );
      });
    }

    test('lost most of it the ordinary way round', () async {
      final lit = await _shadowShot(shadows: false, reversed: false);
      final off = _score(
        lit,
        await _shadowShot(shadows: true, reversed: false),
        truth,
      );
      expect(
        off.drawn / off.inShadow,
        lessThan(0.5),
        reason:
            'the ordinary floor is meant to swallow the shadow here — '
            '${off.drawn} of ${off.inShadow} drawn — or this test no longer '
            'shows what reversing fixed',
      );
    });
  });
}

void _crossFade() {
  group('a level-of-detail cross-fade', () {
    MeshNode level(String name) => MeshNode(
      CpuMesh(CuboidShape().build()),
      engine.RenderMaterial(),
      name: name,
    );

    ({LodGroup group, CameraNode camera}) build(double crossFade) {
      final scene = Scene();
      final group = LodGroup(
        crossFade: crossFade,
        levels: <LodLevel>[
          LodLevel(node: level('high'), maxScreenFraction: 1.0),
          LodLevel(node: level('low'), maxScreenFraction: 0.2),
        ],
      );
      scene.add(group);
      final camera = scene.add(CameraNode())
        ..projection = const PerspectiveProjection(fovY: math.pi / 2);
      camera.lookAt(Vector3(0.0, 0.0, -1.0));
      return (group: group, camera: camera);
    }

    /// The camera distance at which the group's sphere covers [fraction] of
    /// the frame, under the quarter-turn field of view [build] gives.
    double distanceFor(LodGroup group, double fraction) =>
        group.levels.first.node.worldBoundsRadius / fraction;

    test('splits the pixels between neighbours, one end each', () {
      final (:group, :camera) = build(0.5);
      // Halfway through the band: the coarse level's threshold is 0.2, the
      // band runs to 0.3, and 0.25 is its middle.
      camera.setPosition(0.0, 0.0, distanceFor(group, 0.25));
      group.select(camera);
      final high = group.levels[0].node;
      final low = group.levels[1].node;
      expect(high.isVisible && low.isVisible, isTrue);
      expect(high.lodFade, greaterThan(0.0), reason: 'the finer, low end');
      expect(low.lodFade, lessThan(0.0), reason: 'the coarser, high end');
      expect(high.lodFade + -low.lodFade, closeTo(1.0, 1e-9));
      expect(high.lodFade, closeTo(0.5, 0.05));
    });

    test('is whole at either end of the band', () {
      final (:group, :camera) = build(0.5);
      camera.setPosition(0.0, 0.0, distanceFor(group, 0.5));
      group.select(camera);
      expect(group.levels[1].node.isVisible, isFalse);
      expect(group.levels[0].node.lodFade, 1.0);

      camera.setPosition(0.0, 0.0, distanceFor(group, 0.15));
      group.select(camera);
      expect(group.levels[0].node.isVisible, isFalse);
      expect(group.levels[1].node.lodFade, 1.0);
    });

    test('moves the share continuously, with nothing popping', () {
      final (:group, :camera) = build(0.5);
      var previous = 1.0;
      for (var f = 0.4; f > 0.15; f -= 0.005) {
        camera.setPosition(0.0, 0.0, distanceFor(group, f));
        group.select(camera);
        final high = group.levels[0].node;
        final share = high.isVisible ? high.lodFade : 0.0;
        expect(previous - share, lessThan(0.06), reason: 'at a fraction $f');
        previous = share;
      }
    });

    test('is the hard switch at nought', () {
      final (:group, :camera) = build(0.0);
      camera.setPosition(0.0, 0.0, distanceFor(group, 0.25));
      group.select(camera);
      expect(
        group.levels.where((l) => l.node.isVisible).length,
        1,
        reason: 'two levels at once with no band',
      );
      for (final l in group.levels) {
        expect(l.node.lodFade, 1.0);
      }
    });
  });
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
