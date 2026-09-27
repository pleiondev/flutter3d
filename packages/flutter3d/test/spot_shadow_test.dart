/// Spot lights cast shadows, drawn without a GPU.
///
///     flutter test test/spot_shadow_test.dart
///
/// A spot is a cube light with five of its six faces switched off: one atlas
/// column, aimed where the light aims, opened to the cone rather than to ninety
/// degrees. Nothing about the atlas, the filter, the slot allocator or the
/// shading is new — which is the argument for doing it this way, and also the
/// reason it can go wrong in ways a picture does not announce.
///
/// The failures this file exists to catch, each of which leaves a frame that
/// looks entirely plausible:
///
///   * a spot never reaches the candidate list, so it lights through walls;
///   * the shader picks its column by dominant axis, the way a cube does, and
///     sends most of a downlight's cone to a column that is deliberately blank;
///   * the frustum is fitted to the cone exactly, so the shader's
///     out-of-tile bail trims a ring of shadow off the rim;
///   * the static bake is keyed on position and range, so a spot that only
///     *turns* keeps the walls as they looked through its old aim, for as long
///     as the level runs.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

/// Where the light hangs, and how wide it opens.
///
/// Aimed **straight down** on purpose, and that is what kills the dominant-axis
/// mutation outright rather than by a margin: for any fragment on the floor
/// below, the largest component of the vector from the light is −Y, so a cube's
/// face rule picks column 3 — and column 3 of a spot's row is blank by
/// construction. The shadow does not shrink under that mutation, it vanishes.
const double _lightHeight = 8.0;
const double _coneAngle = 0.45;

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

/// A floor, a downlight, and two blockers held in the beam.
///
/// Two rather than one, and where they sit is the whole point: the near one
/// throws its shadow into the middle of the lit disc, the far one throws its
/// shadow out towards the rim. A frustum fitted a few per cent too tight loses
/// the second and keeps the first, so one blocker would have called that
/// correct.
({Scene scene, CameraNode camera, LightNode light}) _room({
  bool castsShadow = true,
  bool staticBlockers = false,
  double coneAngle = _coneAngle,
}) {
  final scene = Scene();
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  MeshNode block(Vector3 size, Vector3 at, {String name = 'block'}) => MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: size).build()),
    Material(
      name: name,
      baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
      lighting: LightingModel.pbr,
    ),
    name: name,
  )..setPosition(at.x, at.y, at.z);

  scene.add(
    block(Vector3(40.0, 1.0, 40.0), Vector3(0.0, -0.5, 0.0), name: 'floor'),
  );

  // Held in the beam rather than standing on the floor: a caster touching its
  // own shadow gives the filter a contact edge to sharpen and leaves nothing to
  // measure a displacement against.
  final near = block(
    Vector3(1.2, 0.4, 1.2),
    Vector3(0.0, 3.0, 0.0),
    name: 'blocker-near',
  )..shadowIsStatic = staticBlockers;
  final rim = block(
    Vector3(1.2, 0.4, 1.2),
    Vector3(1.9, 3.0, 0.0),
    name: 'blocker-rim',
  )..shadowIsStatic = staticBlockers;
  scene.add(near);
  scene.add(rim);

  final light =
      LightNode(
          type: LightType.spot,
          intensity: 60.0,
          range: 20.0,
          outerConeAngle: coneAngle,
          innerConeAngle: coneAngle * 0.5,
          castsShadow: castsShadow,
          name: 'downlight',
        )
        ..setPosition(0.0, _lightHeight, 0.0)
        ..setLocalForward(Vector3(0.0, -1.0, 0.0));
  scene.add(light);

  // Steep and from the front, so the floor fills the lower half of the frame
  // and the blockers sit in the upper: every cell this file measures is floor.
  final camera = CameraNode()
    ..setPosition(0.0, 9.0, -11.0)
    ..lookAt(Vector3(0.0, 0.0, 0.5));
  return (scene: scene, camera: camera, light: light);
}

Future<List<int>> _grid(
  ({CpuDevice device, Renderer renderer}) engine,
  ({Scene scene, CameraNode camera, LightNode light}) room,
) async {
  final frame = engine.renderer.render(
    width: _width,
    height: _height,
    scene: room.scene,
    views: <RenderView>[RenderView(camera: room.camera)],
    settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
  );
  final pixels = await engine.device.readPixels(frame.frame);
  expect(pixels, isNotNull);
  return parityGrid(pixels!.buffer.asUint8List(), _width, _height);
}

/// Cells the shadow took light away from, comparing lit against shadowed.
///
/// A difference rather than a brightness threshold, and that is what makes the
/// blockers themselves harmless: they are drawn identically in both frames, so
/// they subtract to zero. A threshold would have had to be told where they are.
///
/// Restricted to the lower two thirds, where the floor is. Shadow acne on a
/// caster's own top face is a real thing this scene can produce, and it is not
/// what any of these tests are about.
Set<int> _darkened(List<int> lit, List<int> shadowed) => <int>{
  for (var i = kParityGrid * kParityGrid ~/ 3; i < lit.length; i++)
    if (lit[i] - shadowed[i] > 12) i,
};

int _minColumn(Set<int> cells) =>
    cells.map((int i) => i % kParityGrid).reduce((a, b) => a < b ? a : b);
int _maxColumn(Set<int> cells) =>
    cells.map((int i) => i % kParityGrid).reduce((a, b) => a > b ? a : b);

void main() {
  test('a spot light casts a shadow at all', () async {
    // Mutation: leave `LightType.spot` out of `_collectShadowCandidates`. The
    // light keeps lighting, the blockers keep being drawn, and the beam goes
    // straight through them.
    //
    // Mutation: pick the atlas column by dominant axis. Same result, for the
    // reason given on `_lightHeight`.
    final lit = await _grid(_engine(), _room(castsShadow: false));
    final shadowed = await _grid(_engine(), _room());

    final dark = _darkened(lit, shadowed);
    expect(dark, isNotEmpty, reason: 'the blockers cast no shadow');
  });

  test('the shadow reaches the rim of the cone, not just its middle', () async {
    // Mutation: build the projection from `innerConeAngle` instead of
    // `outerConeAngle`. The near blocker's shadow survives and the rim
    // blocker's does not, because the shader bails with "lit" for anything that
    // projects outside the tile — and the tile is then half the cone.
    //
    // Not caught here, and said rather than left implied: dropping
    // `_kSpotFrustumMargin` changes nothing this scene can see. The rim
    // blocker's shadow lands at about four fifths of the way to the tile edge,
    // which is inside it with or without the margin. See the constant's own
    // docstring for why it is kept anyway.
    final lit = await _grid(_engine(), _room(castsShadow: false));
    final shadowed = await _grid(_engine(), _room());
    final dark = _darkened(lit, shadowed);

    expect(dark, isNotEmpty, reason: 'the blockers cast no shadow');
    // The two blockers are 1.9 m apart at three metres up, which the light
    // projects to about three metres apart on the floor. Losing the outer one
    // roughly halves this.
    expect(
      _maxColumn(dark) - _minColumn(dark),
      greaterThanOrEqualTo(4),
      reason:
          'the shadow covers one blocker but not both: the frustum is '
          'fitted too tight and the rim is being trimmed',
    );
  });

  test('turning a spot draws what pointing it there would have', () async {
    // The trap `_bakeKeyFor` had, and the one that stays invisible until
    // somebody animates a searchlight: a static bake is reused for as long as
    // its key holds, and a key of position and range alone cannot tell that the
    // light turned. The bake then holds the walls as they looked through the
    // old aim, for the rest of the level, and nothing reports it.
    //
    // The comparison is against a renderer that was *always* pointed the second
    // way, not against the first frame. Asking merely that the frame changed
    // would have proved nothing: turning a spot moves the lit cone whatever the
    // shadows do, so that assertion passes with the bake fully stale — it was
    // written that way first, and the mutation below walked straight through
    // it.
    //
    // Mutation: drop `aim` and `coneAngle` from `_bakeKeyFor`.
    final turned = Vector3(0.25, -1.0, 0.0)..normalize();

    final moving = _room(staticBlockers: true);
    final engine = _engine();
    await _grid(engine, moving);
    moving.light.setLocalForward(turned);
    final afterTurning = await _grid(engine, moving);

    final fixed = _room(staticBlockers: true);
    fixed.light.setLocalForward(turned);
    final alwaysThere = await _grid(_engine(), fixed);

    final disagree = <int>[
      for (var i = 0; i < alwaysThere.length; i++)
        if ((afterTurning[i] - alwaysThere[i]).abs() > 12) i,
    ];
    expect(
      disagree,
      isEmpty,
      reason:
          'a spot that turned onto this aim draws a different frame from '
          'one that was always on it: the static bake is keyed on something '
          'a turn does not alter, so it was never re-baked',
    );
  });

  test('a point light in the same scene is unaffected', () async {
    // The whole design rests on a spot borrowing the point path, so the point
    // path has to be shown still working beside it — a shared slot pool, a
    // shared atlas and a shared filter are three ways for one to eat the other.
    final room = _room();
    room.light.type = LightType.point;
    room.light.castsShadow = true;
    final shadowed = await _grid(_engine(), room);

    final unlitRoom = _room(castsShadow: false);
    unlitRoom.light.type = LightType.point;
    final lit = await _grid(_engine(), unlitRoom);

    expect(
      _darkened(lit, shadowed),
      isNotEmpty,
      reason: 'a point light in this scene stopped casting a shadow',
    );
  });

  test('a cone wider than a cube face shadows as the cube does', () async {
    // A floodlight at 1.5 rad drawn through one tile opens that tile to
    // fourteen times the width of a cube face, and every texel, the normal
    // offset measured in them and the filter's radius grow with it. A beam of
    // fifteen centimetres held under it throws a strip of shadow a few pixels
    // wide, and through the one tile that strip lands displaced and ragged.
    // Drawn as the cube, the floodlight's shadow is the point light's, to the
    // bit, since the cone only attenuates the light and both read the same
    // six faces.
    //
    // Mutation: drop the forty-five degree test on `spot` where `render`
    // describes the atlas rows, so every spot is one tile again.
    Future<List<int>> darkMap(LightType type) async {
      Future<Uint8List> frame({required bool shadows}) async {
        final room = _room(castsShadow: shadows, coneAngle: 1.5);
        room.light.type = type;
        for (final node in room.scene.meshes.toList()) {
          if (node.name?.startsWith('blocker') ?? false) {
            room.scene.remove(node);
          }
        }
        final beam = MeshNode(
          DeviceMesh.upload(
            CpuDevice(
              width: 4,
              height: 4,
              shaders: CpuShaderLibrary(builtinCpuShaders()),
            ),
            CuboidShape(size: Vector3(0.15, 0.15, 6.0)).build(),
          ),
          Material(
            name: 'beam',
            baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
            lighting: LightingModel.pbr,
          ),
          name: 'beam',
        )..setPosition(1.0, 3.0, 0.0);
        room.scene.add(beam);
        final engine = _engine();
        final result = engine.renderer.render(
          width: _width,
          height: _height,
          scene: room.scene,
          views: <RenderView>[RenderView(camera: room.camera)],
          settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
        );
        final pixels = await engine.device.readPixels(result.frame);
        return pixels!.buffer.asUint8List();
      }

      final lit = await frame(shadows: false);
      final shadowed = await frame(shadows: true);
      return <int>[
        for (var i = 0; i < lit.length; i += 4) lit[i + 1] - shadowed[i + 1],
      ];
    }

    final point = await darkMap(LightType.point);
    final spot = await darkMap(LightType.spot);
    expect(
      point.where((int d) => d > 40).length,
      greaterThan(20),
      reason: 'the beam casts no shadow at all',
    );
    // Through the single tile the strip is as large but not where the point
    // light puts it: about a hundred pixels disagree, by up to 86 levels.
    final disagree = <int>[
      for (var i = 0; i < point.length; i++)
        if ((point[i] - spot[i]).abs() > 8) i,
    ];
    expect(
      disagree,
      isEmpty,
      reason:
          'a floodlight shadows a thin beam differently from a point light at '
          'the same place: it is still drawn through one tile opened past a '
          'cube face',
    );
  });
}
