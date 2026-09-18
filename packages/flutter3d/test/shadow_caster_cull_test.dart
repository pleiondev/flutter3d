/// `gfx-63n`: a caster outside a cascade is not drawn into it.
///
///     flutter test test/shadow_caster_cull_test.dart
///
/// **What it cost before.** The cascade loop walked `scene.meshes` in full for
/// every cascade and rejected only on the visibility flag, the casting flag and
/// drawability, so a level larger than the nearest cascade covers was recorded
/// three times over — and most of it was thrown away at the clipper, after the
/// vertex work. The cube pass had the same shape, six faces at a time, where a
/// face is a ninety-degree frustum holding a small corner of any real level.
///
/// Two claims, and the second is what makes the first safe to take: the draw
/// count falls, and the picture does not move. It cannot move, because a box
/// bounds every triangle its node has, so a box the cascade's volume never
/// touches holds nothing that could have produced a fragment.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// A floor with one caster over it, plus [distant] more casters strung out far
/// beyond anything the near cascades cover.
///
/// The distant ones are the subject: they are inside the scene, so the last
/// cascade — which is always fitted to the whole scene — still records them,
/// and they are nowhere near the first two.
Scene _scene(
  CpuDevice device, {
  required int distant,
  bool casting = true,
  bool nearCasts = true,
  bool culled = true,
}) {
  final floor = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(8, 0.1, 8)).build(),
  );
  final block = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(1, 1, 1)).build(),
  );

  final scene = Scene()
    ..add(
      MeshNode(
        floor,
        Material(name: 'floor', baseColor: Vector4(0.9, 0.9, 0.9, 1.0)),
      )..setPosition(0.0, -1.0, 0.0),
    )
    ..add(
      MeshNode(block, Material(name: 'near'))
        ..setPosition(0.0, 0.6, 0.0)
        ..shadowCasting = nearCasts
            ? ShadowCastingMode.on
            : ShadowCastingMode.off,
    );

  for (var i = 0; i < distant; i++) {
    scene.add(
      MeshNode(block, Material(name: 'far $i'))
        ..setPosition(60.0 + i * 4.0, 0.6, 60.0 + i * 4.0)
        ..shadowCasting = casting ? ShadowCastingMode.on : ShadowCastingMode.off
        // **The switch this file compares against.** `frustumCulled` is the
        // caller's opt-out and the shadow cull honours it, so a scene with it
        // false is this engine drawing casters the way it did before
        // `gfx-63n` — with the same nodes in the same places, which is what
        // makes the two frames comparable. Turning the casting flag off
        // instead would have been a different scene: the cascades are fitted
        // to the casters, so the last one snaps tighter and the picture moves
        // for a reason that has nothing to do with culling. The first draft
        // did exactly that and the test said so, three levels out of 255 at
        // one pixel.
        ..frustumCulled = culled,
    );
  }

  return scene
    ..add(
      LightNode(intensity: 6.0, castsShadow: true)
        ..setPosition(4.0, 5.0, 0.01)
        ..lookAt(Vector3.zero()),
    )
    ..add(
      CameraNode()
        ..setPosition(0.0, 5.0, 0.01)
        ..lookAt(Vector3.zero()),
    );
}

Future<({List<int> pixels, int shadowDraws})> _frame({
  required int distant,
  bool casting = true,
  bool nearCasts = true,
  bool culled = true,
}) async {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = _scene(
    device,
    distant: distant,
    casting: casting,
    nearCasts: nearCasts,
    culled: culled,
  );

  final frame = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: const RenderSettings(
      shadows: ShadowSettings(enabled: true, cascades: 3),
    ),
  );
  final bytes = await device.readPixels(frame.frame);
  return (
    pixels: <int>[
      for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i),
    ],
    shadowDraws: frame.passes
        .where((p) => p.name == 'directional shadows')
        .fold(0, (a, p) => a + p.drawCalls),
  );
}

/// The same shape lit by a point light, whose six cube faces are the other
/// path this row touches.
///
/// A range wide enough to reach the near block and nothing like wide enough to
/// reach the distant ones, so the faces have something to reject.
Future<({List<int> pixels, int shadowDraws})> _pointFrame({
  bool culled = true,
}) async {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = _scene(device, distant: 6, culled: culled)
    ..add(
      LightNode(
        type: LightType.point,
        intensity: 40.0,
        range: 20.0,
        castsShadow: true,
      )..setPosition(0.0, 3.0, 0.0),
    );

  final frame = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: const RenderSettings(shadows: ShadowSettings(enabled: true)),
  );
  final bytes = await device.readPixels(frame.frame);
  return (
    pixels: <int>[
      for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i),
    ],
    shadowDraws: frame.passes
        .where((p) => p.name.startsWith('point shadows'))
        .fold(0, (a, p) => a + p.drawCalls),
  );
}

void main() {
  test('a caster the near cascades cannot see is not drawn into them', () async {
    // Six distant blocks and two things near the camera, with three cascades.
    // Every cascade used to record all eight, which is twenty-four draws; the
    // distant six now reach only the last cascade, the one fitted to the whole
    // scene, so the count falls to eighteen.
    final culled = await _frame(distant: 6);
    final uncut = await _frame(distant: 6, culled: false);

    expect(uncut.shadowDraws, 8 * 3);
    expect(
      culled.shadowDraws,
      lessThan(uncut.shadowDraws),
      reason: 'every cascade still recorded every caster',
    );
    expect(
      culled.shadowDraws,
      greaterThan(0),
      reason: 'the cascade pass drew nothing at all, which is the other bug',
    );
  });

  test('and the picture does not move', () async {
    // **The claim that makes the cull safe.** A caster outside a cascade
    // contributes no fragment to it either way, because the box bounds every
    // triangle the node has, so the two frames have to agree to the byte. If
    // the cull were rejecting something a cascade's volume actually touches,
    // this is where it would show.
    final culled = await _frame(distant: 6);
    final uncut = await _frame(distant: 6, culled: false);

    expect(culled.pixels, uncut.pixels);
  });

  test('a caster inside the near cascade is still drawn into it', () async {
    // The control, and the one that would catch a cull rejecting everything:
    // with nothing distant at all the two casters are inside every cascade, so
    // the count is the full one and no cascade has lost anybody.
    final near = await _frame(distant: 0);

    expect(near.shadowDraws, 2 * 3);
  });

  test('the shadow under the near block survives the cull', () async {
    // And the picture the whole row is about. A cull that quietly rejected the
    // caster nearest the camera would pass all three tests above — fewer draws,
    // a stable picture between two frames that both lost it — and fail only
    // here, where the floor is compared against a frame with nothing casting.
    final lit = await _frame(distant: 6, nearCasts: false);
    final shadowed = await _frame(distant: 6);

    var darker = 0;
    for (var i = 0; i < lit.pixels.length; i += 4) {
      if (shadowed.pixels[i] < lit.pixels[i] - 2) darker++;
    }
    expect(
      darker,
      greaterThan(20),
      reason: 'the block over the floor casts no shadow at all',
    );
  });

  test(
    'a cube face drops the casters it cannot see, and keeps the tile',
    () async {
      // The other shadow path, and the one where the omission cost most: a cube
      // face is a ninety-degree frustum reaching as far as the light's range, so
      // it holds a small corner of any level, and the loop ran six times a light.
      final culled = await _pointFrame();
      final uncut = await _pointFrame(culled: false);

      expect(
        culled.shadowDraws,
        lessThan(uncut.shadowDraws),
        reason: 'every face still recorded every caster',
      );
      expect(culled.pixels, uncut.pixels);
    },
  );
}
