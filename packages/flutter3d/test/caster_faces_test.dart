/// `ShadowSettings.casterFaces`, in a picture.
///
///     flutter test test/caster_faces_test.dart
///
/// **A public setting with three values that no frame anywhere chose.** The
/// only thing that named it outside the engine was
/// `flutter3d/test/static_shadow_rebake_test.dart`, which asks whether changing
/// it invalidates the static bake key — a question about bookkeeping, answered
/// without drawing anything. Which side of a caster ends up recorded, and what
/// that does to the shadow, was held by nothing.
///
/// The difference is only visible on geometry that is a *surface* rather than a
/// body. A closed cube has a front face and a back face and casts either way,
/// which is why the setting can sit at `back` — its default, and second-depth
/// shadow mapping — through a whole golden suite of blocks without ever showing
/// itself. A single-sided plane has one face: record the far side of it and
/// there is no far side, so the light goes straight through and the shadow is
/// gone.
///
/// That is the case the enum's own documentation is about — "catches a
/// one-sided wall or an open shell, which the other two see straight through" —
/// and it is the case a level author meets, because a plane is what a floor,
/// a billboard and a fence panel are.
///
/// **Written to pin a setting, and it found the setting unwired.** The cube
/// atlas read `casterFaces`; the directional pass — the one the sun goes
/// through, and the one every outdoor level leans on — wrote `CullMode.frontFace`
/// into three `setState` calls and never looked at the setting. `frontFace` is
/// what the default asks for, so two of the three values did nothing at all and
/// the third was doing it by coincidence. Nothing said so: `StaticBakeKey`
/// dutifully invalidated the bake when the setting changed, so the pass really
/// did run again, and drew the identical picture.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

/// A floor, a single-sided sheet held over it, and the sun straight down.
///
/// The sheet is a [PlaneShape], whose one face points at +Y and therefore at
/// the light. The camera sits below it and looks along the floor, so the sheet
/// itself is out of shot — its back face, which the scene pass culls — and what
/// is in shot is the patch of floor under it.
({Scene scene, CameraNode camera, MeshNode sheet}) _sheetOverFloor() {
  final scene = Scene();
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  Material grey(String name) => Material(
    name: name,
    baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
    lighting: LightingModel.lambert,
  );

  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(60.0, 1.0, 60.0)).build(),
      ),
      grey('floor'),
      name: 'floor',
    )..setPosition(0.0, -0.5, 0.0),
  );
  final sheet = MeshNode(
    DeviceMesh.upload(device, const PlaneShape(width: 9.0, depth: 9.0).build()),
    grey('sheet'),
    name: 'sheet',
  )..setPosition(0.0, 4.0, 2.0);
  scene.add(sheet);
  scene.add(
    LightNode(
      type: LightType.directional,
      // Low enough that the lit floor is not at the top of the tone curve,
      // where a shadow has no room to be darker than what is around it.
      intensity: 0.55,
      castsShadow: true,
      name: 'sun',
    )..setLocalForward(Vector3(-0.15, -1.0, 0.2)),
  );

  final camera = CameraNode()
    ..setPosition(0.0, 1.4, -14.0)
    ..lookAt(Vector3(0.0, 0.0, 2.0));
  return (scene: scene, camera: camera, sheet: sheet);
}

Future<List<int>> _grid(ShadowCasterFaces faces) async {
  final it = cpuTestDevice(width: _width, height: _height);
  final renderer = Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );
  final room = _sheetOverFloor();
  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: room.scene,
    views: <RenderView>[RenderView(camera: room.camera)],
    settings: RenderSettings(
      bloom: const BloomSettings(enabled: false),
      shadows: ShadowSettings(cascades: 1, casterFaces: faces),
    ),
  );
  final pixels = await it.device.readPixels(frame.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return parityGrid(pixels!.buffer.asUint8List(), _width, _height);
}

/// Cells that are floor lying in shadow.
///
/// The window is between the two things a floor cell can be and nothing else:
/// lit floor reads 193 and floor under the sheet reads about 131, so the band
/// is well clear of both. The empty sky above the horizon (4) and the horizon
/// row itself (41) are below it — the first draft of this took the horizon for
/// a shadow and reported one in every frame, including the frames that had
/// none.
Set<int> _shadowed(List<int> grid) => <int>{
  for (var i = 0; i < grid.length; i++)
    if (grid[i] > 100 && grid[i] < 170) i,
};

void main() {
  test('a one-sided caster is recorded by front and both, not by back', () async {
    // Mutation: swap the `front` and `back` arms of the `casterCull` switch in
    // `renderer_shadow_pass.dart` — the enum then names what is culled rather
    // than what is recorded, `front` loses the shadow and `back` gains one, and
    // both expectations below fail at once. Collapsing the switch to
    // `CullMode.none` fails only the `back` one, which is why that is the
    // expectation stated first.
    final back = _shadowed(await _grid(ShadowCasterFaces.back));
    final front = _shadowed(await _grid(ShadowCasterFaces.front));
    final both = _shadowed(await _grid(ShadowCasterFaces.both));

    expect(
      back,
      isEmpty,
      reason:
          'recording the far side of a surface that has no far side must leave '
          'nothing in the map, so the light goes straight through the sheet',
    );
    expect(
      front.length,
      greaterThan(4),
      reason: 'the light-facing side is the one side this sheet has',
    );
    expect(
      both,
      equals(front),
      reason:
          'drawing every face of a one-sided caster records the same one face, '
          'so the two must put the shadow in the same cells',
    );
  });

  test('doubleSided overrides the setting rather than following it', () async {
    // The escape hatch `ShadowCastingMode.doubleSided` documents — "cast from
    // every face, whatever ShadowSettings.casterFaces says" — which is the
    // answer for exactly the geometry the test above shows losing its shadow.
    // Nothing drew it either.
    //
    // Mutation: make `castsFromEveryFace` return false — the sheet follows the
    // setting again, `back` culls its only face, and this fails with an empty
    // set.
    final room = _sheetOverFloor();
    room.sheet.shadowCasting = ShadowCastingMode.doubleSided;

    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    );
    final frame = renderer.render(
      width: _width,
      height: _height,
      scene: room.scene,
      views: <RenderView>[RenderView(camera: room.camera)],
      settings: const RenderSettings(
        bloom: BloomSettings(enabled: false),
        shadows: ShadowSettings(
          cascades: 1,
          casterFaces: ShadowCasterFaces.back,
        ),
      ),
    );
    final pixels = await it.device.readPixels(frame.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');

    expect(
      _shadowed(parityGrid(pixels!.buffer.asUint8List(), _width, _height)),
      isNotEmpty,
      reason:
          'the sheet asked to cast from every face and the setting that would '
          'have culled its only one was allowed to',
    );
  });
}
