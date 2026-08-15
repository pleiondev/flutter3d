/// Cascaded directional shadows, drawn without a GPU.
///
///     flutter test test/cascade_test.dart
///
/// One directional map fitted to the whole scene spends its resolution on
/// ground nobody can see. On a level a hundred and twenty metres across that is
/// about fourteen centimetres of world per texel, and a character's own shadow
/// comes out as a blurred slab beside them — it was reported, in those words, as
/// the character being drawn twice.
///
/// Cascades put the nearest map around the camera instead. What has to stay
/// true while they do:
///
///   * one cascade is exactly the old behaviour, so every golden holds;
///   * three cascades shadow the *same things* — a nearer map must not move a
///     shadow, only sharpen it;
///   * the near cascade really is denser, which is the whole point;
///   * nothing is left unshadowed by a gap between volumes.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

({CpuDevice device, Renderer renderer}) _engine() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  TextureHandle texel(List<int> rgba) => device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
      )!;
  return (
    device: device,
    renderer: Renderer.create(
      device: device,
      fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
      fallbackNormal: texel(<int>[128, 128, 255, 255]),
    ),
  );
}

/// A long floor with a post standing on it, and the sun across it.
///
/// Long on purpose: the whole argument for cascades is that fitting one map to
/// a large scene wastes it, and a scene that fits in one map cannot show that.
({Scene scene, CameraNode camera}) _longRoom({double length = 160.0}) {
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

  scene.add(block(Vector3(40.0, 1.0, length), Vector3(0.0, -0.5, length * 0.4),
      name: 'floor'));
  // A slab held over the floor, not a post standing on it: a thin caster at
  // this distance throws a shadow a few cells wide, and a few cells is not
  // enough to tell "moved" from "sharpened". The first draft used a post and
  // the frame it produced had no dark cells in it at all.
  scene.add(block(Vector3(10.0, 0.6, 6.0), Vector3(0.0, 5.0, 10.0),
      name: 'canopy'));

  scene.add(
    LightNode(
      type: LightType.directional,
      // Low enough that the lit floor is not saturated: a floor at the top of
      // the tone curve is a floor whose shadow cannot be seen, which is what
      // made the first version of these tests pass with no shadow in shot.
      intensity: 1.1,
      castsShadow: true,
      name: 'sun',
    )..setLocalForward(Vector3(-0.2, -0.95, 0.25)),
  );

  final camera = CameraNode()
    ..setPosition(0.0, 3.0, -8.0)
    ..lookAt(Vector3(0.0, 1.0, 8.0));
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

/// The cells that are floor lying in shadow: darker than lit floor, and
/// brighter than the background behind it.
Set<int> _shadowed(List<int> grid) => <int>{
      for (var i = 0; i < grid.length; i++)
        if (grid[i] > 20 && grid[i] < 170) i,
    };

void main() {
  test('one cascade is the shadow this renderer has always drawn', () {
    // The compatibility guard, and the reason `cascades` defaults to one: every
    // golden image and every parity number in the repository was recorded
    // against this path, and a change of default would have re-baselined them
    // all in a commit about something else.
    //
    // Mutation: default `cascades` to 3.
    expect(const ShadowSettings().cascades, 1);
  });

  test('three cascades shadow the same things as one', () async {
    // A nearer map must *move* nothing. Cascades that are fitted wrongly put
    // the shadow somewhere else entirely, and the frame still looks plausible
    // until you compare it with the one that was right.
    //
    // Mutation: drop the texel snapping, or fit a cascade around the camera
    // rather than along its line of sight — the post's shadow slides.
    final room = _longRoom();
    final single = await _grid(_engine(), room, const ShadowSettings());
    final many =
        await _grid(_engine(), room, const ShadowSettings(cascades: 3));

    // Loose, because a denser map genuinely draws a crisper edge and the point
    // of the change is that the two are not identical. What is asserted is that
    // no cell is *lit differently* — a moved shadow shows up as a cell that was
    // dark and is now bright, which is a difference of a hundred and more.
    // Which cells are floor-in-shadow: darker than lit floor, brighter than the
    // background. Comparing *sets of shadowed cells* rather than a worst-delta,
    // because a worst-delta over a mostly-empty frame is satisfied by almost
    // anything — the first version of this passed with the cascade fitted
    // around the camera instead of ahead of it, and with the texel snapping
    // deleted.
    final wasDark = _shadowed(single);
    final isDark = _shadowed(many);

    expect(wasDark, isNotEmpty, reason: 'there was no shadow to compare');
    expect(isDark.difference(wasDark).length, lessThanOrEqualTo(2),
        reason: 'the shadow reaches cells it did not before: it moved');
    expect(wasDark.difference(isDark).length, lessThanOrEqualTo(2),
        reason: 'the shadow left cells it used to cover: it moved');
  });

  test('the near cascade covers metres where one map covers tens', () async {
    // The measurement the whole change exists for, made where it can be made
    // honestly: the renderer reports what it fitted.
    //
    // Mutation: give every cascade the scene's radius — the near one stops
    // being near and the numbers converge.
    final room = _longRoom(length: 400.0);
    final engine = _engine();
    await _grid(engine, room, const ShadowSettings(cascades: 3));

    final near = engine.renderer.debugCascadeRadii.first;
    final far = engine.renderer.debugCascadeRadii.last;

    expect(near, lessThan(far / 3.0),
        reason: 'the near cascade covers $near m and the far one $far m');
  });

  test('a camera that creeps does not make the shadows crawl', () async {
    // **What the texel snapping is for**, tested where it can be seen. A single
    // frame cannot show shimmer: the artefact is that a shadow *edge* redraws
    // itself somewhere slightly different on every frame, and what a still
    // picture shows is one of those frames. Two earlier versions of this test
    // compared pictures — one on the luminance grid and one on pixels — and
    // neither could fail.
    //
    // So it asserts the mechanism directly: as the camera creeps, the fitted
    // centre of the near cascade must take a *small number of distinct values*
    // rather than a new one every frame. That is what snapping does, and it is
    // the property the artefact is the absence of.
    //
    // Mutation: delete the snapping. Every step gets its own centre and the
    // count goes from a handful to one per frame. (An earlier mutation run
    // reported this same test passing against a snapping that was a no-op —
    // the light frame was built *from* the centre being snapped, so its
    // coordinates were always zero. The defect was real and this is what found
    // it.)
    final room = _longRoom();
    final engine = _engine();
    const shadows = ShadowSettings(cascades: 3, resolution: 256);

    final centres = <String>{};
    for (var step = 0; step < 24; step++) {
      room.camera.setPosition(step * 0.02, 3.0, -8.0);
      await _grid(engine, room, shadows);
      final near = engine.renderer.debugCascadeCentres.first;
      centres.add('${near.x.toStringAsFixed(4)},${near.z.toStringAsFixed(4)}');
    }

    // Half a metre of travel against a texel a third of a metre wide: two or
    // three whole-texel steps, not twenty-four slides.
    expect(centres.length, lessThan(6),
        reason: 'the cascade centre took ${centres.length} distinct places in '
            'twenty-four frames, so it is sliding rather than stepping');
  });

  test('nothing falls between the volumes', () async {
    // A frame with a shadow in it, which the first version of this file did not
    // have: the light was bright enough to saturate the floor, so every cell was
    // either background or white and the assertion below passed on the
    // difference between those two.
    //
    // **The fall-through between cascades is deliberately not covered here**,
    // and saying so is better than a comment claiming a mutation that does not
    // fire. Turning it off — `return 1.0` instead of trying the next cascade —
    // changes nothing in this scene or any other that was tried: the spheres
    // are fitted generously enough that the cascade chosen by distance really
    // does contain the fragment. It is a belt-and-braces path against a fit
    // that is wrong, and a test for it would have to contrive a wrong fit.
    final room = _longRoom();
    final engine = _engine();
    final grid = await _grid(engine, room, const ShadowSettings(cascades: 3));

    // The floor is lit and the post's shadow is on it: somewhere in the frame
    // must be dark, and somewhere must be bright. A frame with no dark cells is
    // a frame with no shadow at all.
    final low = grid.reduce((int a, int b) => a < b ? a : b);
    final high = grid.reduce((int a, int b) => a > b ? a : b);
    expect(high - low, greaterThan(25), reason: 'there is no shadow in it');
  });
}
