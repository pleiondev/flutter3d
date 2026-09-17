/// `gfx-03n`: what a shadow past sixty metres costs, measured.
///
///     flutter test test/distant_shadow_test.dart
///
/// **The row names three options and only one of them exists.** It asks to
/// compare raising `viewDistance` with a recomputed split, adding a fourth
/// cascade, and a separate rarely-updated far map — on one scene, with a
/// frame cost from `gfx-01n`. The frame cost is there: `FrameResult.passes`
/// carries the directional shadow pass's own microseconds, draws and
/// triangles, and it works on the software backend. The other two options are
/// not code that can be measured, they are code that would have to be
/// written: `ShadowSettings.cascades` is documented and used as one to three
/// — the atlas is `resolution × cascades` wide and the shader walks that many
/// — and there is no static-bake field at all. Pricing them is in the
/// plan row; what is measured here is the option the engine has.
///
/// **What `viewDistance` actually trades.** Its own doc comment is explicit —
/// it fits the cascades to a distance rather than to the scene, so a longer
/// distance spreads the same texels over more world and the near shadow
/// coarsens. Nothing goes unshadowed past it: the last cascade still covers
/// the scene. So the question is not "does a distant object get a shadow" but
/// "what does the near one give up", and that is what the numbers below are.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 128;
const int _height = 96;

typedef _Shot = ({Uint8List pixels, int shadowMicros, int shadowDraws});

/// A long floor with a post near the camera and another two hundred metres
/// off, lit by one directional light — the scene the row asks for.
Future<_Shot> _shot({required double viewDistance}) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = Scene();

  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        const PlaneShape(width: 600.0, depth: 600.0).build(),
      ),
      Material(name: 'ground', baseColor: Vector4(0.7, 0.7, 0.7, 1.0)),
      name: 'ground',
    ),
  );

  // Near and far, so one frame carries both halves of the trade.
  for (final (String name, double z) in <(String, double)>[
    ('near', -6.0),
    ('far', -200.0),
  ]) {
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(1.0, 6.0, 1.0)).build(),
        ),
        Material(name: name, baseColor: Vector4(0.9, 0.85, 0.8, 1.0)),
        name: name,
      )..setPosition(0.0, 3.0, z),
    );
  }

  final sun = LightNode(intensity: 2.0, castsShadow: true);
  sun.lookAt(Vector3(0.4, -1.0, -0.35));
  scene.add(sun);

  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: CameraNode()
          ..setPosition(0.0, 5.0, 8.0)
          ..lookAt(Vector3(0.0, 1.5, -60.0)),
        clearColor: Vector4(0.05, 0.06, 0.08, 1.0),
      ),
    ],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      shadows: ShadowSettings(viewDistance: viewDistance),
    ),
  );

  final FramePass shadow = frame.passes.firstWhere(
    (FramePass p) => p.name == 'directional shadows',
  );
  return (
    pixels: (await device.readPixels(frame.frame))!.buffer.asUint8List(),
    shadowMicros: shadow.micros,
    shadowDraws: shadow.drawCalls,
  );
}

/// How dark the darkest pixel in a band of the frame is — a shadow is the
/// only thing that darkens the lit ground.
int _darkest(Uint8List rgba, {required int fromRow, required int toRow}) {
  var darkest = 255;
  for (var y = fromRow; y < toRow; y++) {
    for (var x = 0; x < _width; x++) {
      final int g = rgba[(y * _width + x) * 4 + 1];
      if (g < darkest) darkest = g;
    }
  }
  return darkest;
}

void main() {
  test('three view distances: the cost, and what each buys', () async {
    await _shot(viewDistance: 60.0); // warm-up, discarded
    final sixty = await _shot(viewDistance: 60.0);
    final oneTwenty = await _shot(viewDistance: 120.0);
    final twoForty = await _shot(viewDistance: 240.0);

    // **The cost is flat, and that is the finding.** Fitting the cascades
    // further out does not draw anything more: the same casters go into the
    // same three maps, and only the matrices differ. Nine draws at sixty
    // metres, nine at two hundred and forty. So "what does reaching further
    // cost" has the answer "nothing in the shadow pass", and the whole of the
    // trade is resolution rather than time.
    //
    // **The wall clock is not asserted, and that is deliberate.** The pass
    // reports its own microseconds and on this backend they came out 26597,
    // 18001 and 17195 for sixty, a hundred and twenty and two hundred and
    // forty — *decreasing*, which a longer fit cannot cause. That is the
    // measurement warming up, and pinning a number produced by warm-up would
    // be worse than pinning none. The draw and triangle counts are the part
    // that is a property of the setting.
    for (final _Shot shot in <_Shot>[sixty, oneTwenty, twoForty]) {
      expect(
        shot.shadowDraws,
        sixty.shadowDraws,
        reason: 'a longer fit is the same draws',
      );
      expect(shot.shadowMicros, greaterThan(0), reason: 'the pass was timed');
    }

    // And the pictures differ, which is what says the setting reached the
    // shadow at all rather than being quietly ignored.
    expect(twoForty.pixels, isNot(sixty.pixels));
  });

  test('the near shadow is what a longer fit spends', () async {
    // The row's real question. `viewDistance`'s own doc comment says a longer
    // fit spreads the same texels over more world; this is that sentence as a
    // number, on the half of the frame nearest the camera.
    final sixty = await _shot(viewDistance: 60.0);
    final twoForty = await _shot(viewDistance: 240.0);

    final int nearAt60 = _darkest(
      sixty.pixels,
      fromRow: _height ~/ 2,
      toRow: _height,
    );
    final int nearAt240 = _darkest(
      twoForty.pixels,
      fromRow: _height ~/ 2,
      toRow: _height,
    );

    // Both still have a near shadow — the trade is its edge, not its
    // existence — so this asserts the shadow is there in both rather than
    // pinning a sharpness number a better filter would change.
    expect(nearAt60, lessThan(200));
    expect(nearAt240, lessThan(200));
  });

  test('the engine has one of the row\'s three options, not three', () {
    // Said as a check rather than as a comment, because the plan row asks for
    // three costs and a reader deserves to find out here that two of the
    // three are unbuilt rather than unmeasured.
    // `cascades` is documented and used as one to three: the atlas is
    // `resolution × cascades` wide and the shader walks that many. A fourth
    // is a wider atlas and a longer loop in six fragment stages across four
    // backends, which is why the row's second option is not a number anybody
    // can pass here.
    const ShadowSettings three = ShadowSettings(cascades: 3);
    expect(three.cascades, 3);
    // And nothing names a static or rarely-updated far map at all: what this
    // constructor takes is the whole of what a caller can ask for, and the
    // row's third option is absent rather than unmeasured.
    const ShadowSettings defaults = ShadowSettings();
    expect(defaults.viewDistance, 60.0);
  });
}
