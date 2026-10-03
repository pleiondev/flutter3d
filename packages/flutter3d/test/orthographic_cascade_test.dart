/// Directional shadow cascades under an orthographic camera — `P7`.
///
///     flutter test test/orthographic_cascade_test.dart
///
/// The cascades are split by distance from the eye, half way to logarithmic,
/// which is right through a perspective lens: a texel on screen covers more
/// world the further off it is. Through an orthographic lens every metre of
/// depth gets the same texels on screen, and the eye is only where the camera
/// was put along its axis — here forty metres back and forty up. Split from
/// there, the near cascades covered air in front of the lens and everything
/// the camera saw fell to the last cascade, the whole level in one map. What
/// has to hold instead:
///
///   * the near cascade covers part of what the view sees;
///   * a caster at the bottom of the frame and one at the top each land in a
///     near cascade, of about the same size;
///   * the shadows stay where one whole-level map puts them.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

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

/// Where the two canopies stand: one at the bottom of the frame, one at the
/// top.
final Vector3 _nearCanopy = Vector3(0.0, 3.0, 8.0);
final Vector3 _farCanopy = Vector3(0.0, 3.0, 52.0);

/// A floor a hundred and sixty metres long with a canopy held over it near the
/// bottom of the frame and another near the top, a sun across it, and an
/// isometric camera forty metres back and forty up.
({Scene scene, CameraNode camera}) _isometricRoom() {
  final scene = Scene();
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  MeshNode block(Vector3 size, Vector3 at, String name) => MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: size).build()),
    Material(
      name: name,
      baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
      lighting: LightingModel.pbr,
    ),
    name: name,
  )..setPosition(at.x, at.y, at.z);

  scene
    ..add(block(Vector3(40.0, 1.0, 160.0), Vector3(0.0, -0.5, 64.0), 'floor'))
    ..add(block(Vector3(10.0, 0.6, 6.0), _nearCanopy, 'near'))
    ..add(block(Vector3(10.0, 0.6, 6.0), _farCanopy, 'far'))
    ..add(
      LightNode(
        type: LightType.directional,
        intensity: 1.1,
        castsShadow: true,
        name: 'sun',
      )..setLocalForward(Vector3(-0.2, -0.95, 0.25)),
    );

  final camera = CameraNode()
    ..projection = const OrthographicProjection(height: 30.0, far: 400.0)
    ..setPosition(0.0, 40.0, -40.0)
    ..lookAt(Vector3(0.0, 0.0, 30.0));
  return (scene: scene, camera: camera);
}

Future<List<int>> _grid(
  ({CpuDevice device, Renderer renderer}) engine,
  ({Scene scene, CameraNode camera}) room,
  ShadowSettings shadows,
) async {
  final frame = engine.renderer.render(
    width: _width,
    height: _height,
    scene: room.scene,
    views: <RenderView>[RenderView(camera: room.camera)],
    settings: RenderSettings(
      shadows: shadows,
      bloom: const BloomSettings(enabled: false),
    ),
  );
  final pixels = await engine.device.readPixels(frame.frame);
  expect(pixels, isNotNull);
  return parityGrid(pixels!.buffer.asUint8List(), _width, _height);
}

/// The cells that are floor lying in shadow, as `cascade_test.dart` counts
/// them.
Set<int> _shadowed(List<int> grid) => <int>{
  for (var i = 0; i < grid.length; i++)
    if (grid[i] > 20 && grid[i] < 170) i,
};

/// Which cascade the shaders give [point], by the rule `shadow.glsl` follows
/// through an orthographic lens: by depth along the view axis, then on to the
/// next cascade while the chosen one's sphere does not hold the point.
int _cascadeOf(Renderer renderer, CameraNode camera, Vector3 point) {
  final splits = renderer.debugCascadeSplits;
  final centres = renderer.debugCascadeCentres;
  final radii = renderer.debugCascadeRadii;
  final depth = (point - camera.readWorldPosition()).dot(camera.readForward());
  final byDepth = depth > splits[1]
      ? 2
      : depth > splits[0]
      ? 1
      : 0;
  return <int>[
    for (var i = byDepth; i < centres.length; i++)
      if (centres[i].distanceTo(point) <= radii[i]) i,
    centres.length - 1,
  ].first;
}

void main() {
  test('the near cascade covers what the view sees, not the air in front of '
      'the lens', () async {
    // Mutation: drop the orthographic branch in `_renderShadowMap`. The near
    // cascade goes back to a sphere a few metres in front of the eye, thirty
    // metres above the floor, holding no caster at all.
    final room = _isometricRoom();
    final engine = _engine();
    await _grid(engine, room, const ShadowSettings(cascades: 3));

    final centre = engine.renderer.debugCascadeCentres.first;
    final radius = engine.renderer.debugCascadeRadii.first;
    final bounds = room.scene.computeBounds(castersOnly: true);
    final nearest = Vector3.copy(centre)..clamp(bounds.min, bounds.max);
    expect(
      nearest.distanceTo(centre),
      lessThanOrEqualTo(radius),
      reason: 'the near cascade, $radius m round $centre, holds no caster',
    );
    expect(
      radius,
      lessThan(engine.renderer.debugCascadeRadii.last / 2.0),
      reason: 'the near cascade is as large as the whole level',
    );
  });

  test(
    'casters at the bottom and the top of the frame get the same texels',
    () async {
      // Every metre of an orthographic view gets the same pixels, so a caster at
      // the top of the frame deserves the texels one at the bottom gets. Both
      // land in a near cascade, and the two are within a factor of two of each
      // other.
      //
      // Mutation: drop the orthographic branch in `_renderShadowMap`. Both
      // canopies are fifty metres and more from the eye, past both splits, and
      // fall to the whole-level map.
      final room = _isometricRoom();
      final engine = _engine();
      await _grid(engine, room, const ShadowSettings(cascades: 3));

      final radii = engine.renderer.debugCascadeRadii;
      final near = _cascadeOf(engine.renderer, room.camera, _nearCanopy);
      final far = _cascadeOf(engine.renderer, room.camera, _farCanopy);
      expect(
        near,
        lessThan(2),
        reason: 'the near canopy is in the last cascade',
      );
      expect(far, lessThan(2), reason: 'the far canopy is in the last cascade');
      expect(
        radii[near] / radii[far],
        inInclusiveRange(0.5, 2.0),
        reason: 'cascades of ${radii[near]} m and ${radii[far]} m',
      );
    },
  );

  group('the near cascades hold still', () {
    // The fit follows where the view box meets the casters' bounds, which
    // slides with every pan and every caster that moves. The shadow pass
    // snaps each map to whole texels of its radius and scrolls a still tile
    // only while its scale holds, so a radius or a slab end that follows the
    // fit continuously is a texel grid that rescales every frame.
    //
    // Mutation: drop the rounding in `orthographicCascades`. A centimetre's
    // pan moves the near radii by a couple of millimetres and a canopy rising
    // five centimetres moves them and the slab ends by centimetres.
    Future<({List<double> radii, List<double> splits})> cascades(
      ({Scene scene, CameraNode camera}) room,
    ) async {
      final engine = _engine();
      await _grid(engine, room, const ShadowSettings(cascades: 3));
      final radii = engine.renderer.debugCascadeRadii;
      final splits = engine.renderer.debugCascadeSplits;
      return (
        radii: <double>[radii[0], radii[1]],
        splits: <double>[splits[0], splits[1]],
      );
    }

    test('under a pan of a centimetre', () async {
      final room = _isometricRoom();
      final before = await cascades(room);
      room.camera.setPosition(0.01, 40.0, -40.0);
      final after = await cascades(room);
      expect(after.radii, before.radii, reason: 'a near radius moved');
      expect(after.splits, before.splits, reason: 'a slab end moved');
    });

    test('under a caster rising five centimetres', () async {
      final room = _isometricRoom();
      final before = await cascades(room);
      room.scene.root
          .findByName('near')!
          .setPosition(_nearCanopy.x, _nearCanopy.y + 0.05, _nearCanopy.z);
      final after = await cascades(room);
      expect(after.radii, before.radii, reason: 'a near radius moved');
      expect(after.splits, before.splits, reason: 'a slab end moved');
    });
  });

  test('three cascades shadow the same things as one', () async {
    // A fitted cascade must move nothing, only sharpen it.
    //
    // **No mutation of the fit makes this fail, and it says so** rather than
    // naming one that does not fire. Spheres fitted round each slab's middle
    // on the axis, half its depth across, were tried: wherever a near tile
    // misses a fragment the shader falls through to the whole-level map, so
    // the picture holds. What this guards is the opposite failure — a near
    // tile that *does* hold a fragment and records the wrong thing there.
    final room = _isometricRoom();
    final single = await _grid(
      _engine(),
      room,
      const ShadowSettings(cascades: 1),
    );
    final many = await _grid(
      _engine(),
      room,
      const ShadowSettings(cascades: 3),
    );

    final wasDark = _shadowed(single);
    final isDark = _shadowed(many);
    expect(wasDark, isNotEmpty, reason: 'there was no shadow to compare');
    expect(
      wasDark.difference(isDark).length,
      lessThanOrEqualTo(2),
      reason: 'the shadow left cells it used to cover: it moved',
    );
    expect(
      isDark.difference(wasDark).length,
      lessThanOrEqualTo(2),
      reason: 'the shadow reaches cells it did not before: it moved',
    );
  });
}
