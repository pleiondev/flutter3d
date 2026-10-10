/// `Renderer.listener` — what a renderer tells a `RenderListener` after each
/// frame, on the software device.
///
///     dart test test/render_listener_test.dart
///
/// Each callback is held to the frame it was called for: `drawn` gets the
/// very result `render` returned, `skipped` gets every entry of its
/// `skipped` in order, including a step switched off and a request the
/// device declined, and `overTime` fires exactly when the frame's CPU time
/// went over the budget.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 16;

typedef _Stage = ({Renderer renderer, Scene scene});

_Stage _stage() {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 0.0, 3.0)
    ..lookAt(Vector3.zero());
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.0)).build()),
        RenderMaterial(baseColor: LinearColor.fromSrgb(0.7, 0.5, 0.3, 1.0)),
      ),
    )
    ..add(
      LightNode(intensity: 2.0 * Photometric.legacyUnit)
        ..setPosition(1.0, 2.0, 2.0),
    )
    ..add(camera);
  return (renderer: Renderer.create(device: device), scene: scene);
}

FrameResult _render(
  _Stage it, [
  RenderSettings settings = const RenderSettings(),
]) => it.renderer.render(
  width: _size,
  height: _size,
  scene: it.scene,
  views: <RenderView>[RenderView(camera: it.scene.cameras.single)],
  settings: settings,
);

void main() {
  test('drawn gets every frame, the result render returned', () {
    // Mutation: removing the `listener?.notify(result)` call from
    // `Renderer.render` leaves `seen` empty.
    final it = _stage();
    final seen = <FrameResult>[];
    it.renderer.listener = RenderListener(drawn: seen.add);
    final first = _render(it);
    final second = _render(it);
    expect(seen, hasLength(2));
    expect(seen[0], same(first));
    expect(seen[1], same(second));
  });

  test('skipped gets each skip with its reason, switched off and declined', () {
    // Wireframe on the software device is declined — it has no line
    // primitive for a polygon mode — and the tone curve is a step with no
    // pass, switched off. Both arrive here, told apart by their reasons.
    // Mutation: leaving `FrameResult.declinedSkips` out of the renderer's
    // `skipped` drops the wireframe entry; leaving `RenderStep.reportSkips`
    // out drops the tone curve.
    final it = _stage();
    final told = <SkippedPass>[];
    it.renderer.listener = RenderListener(skipped: told.add);
    final result = _render(
      it,
      const RenderSettings(
        wireframe: true,
      ).without(<RenderStep>{RenderStep.tonemap}),
    );
    expect(told, result.skipped);
    expect(result.wireframeDeclined, isTrue);
    expect(told, contains((name: 'wireframe', reason: PassSkip.declined)));
    expect(told, contains((name: 'tonemap', reason: PassSkip.switchedOff)));
    // And a pass off by its own default setting, reported as such.
    expect(told, contains((name: 'object ids', reason: PassSkip.settings)));
  });

  test('the declined entries are exactly what the fields say', () {
    // The software device has no multisampled target, so every frame here
    // declines multisampling and says so in both places; a frame that did
    // not ask for wireframe lists no wireframe.
    // Mutation: appending the declined entries unconditionally lists
    // 'wireframe' on the first frame; dropping the `multisampling` line from
    // `FrameResult.declinedSkips` loses it from both.
    final it = _stage();
    for (final settings in <RenderSettings>[
      const RenderSettings(),
      const RenderSettings(wireframe: true),
    ]) {
      final result = _render(it, settings);
      expect(
        result.skipped
            .where((s) => s.reason == PassSkip.declined)
            .map((s) => s.name)
            .toSet(),
        <String>{
          if (result.wireframeDeclined) 'wireframe',
          if (result.alphaToCoverageDeclined) 'alpha to coverage',
          if (result.antiAliasing.msaaDeclined != null) 'multisampling',
          if (result.shadowsDenied > 0) 'point shadow rows',
        },
      );
      expect(result.antiAliasing.msaaDeclined, isNotNull);
    }
  });

  test('overTime fires past the budget, and never without one', () {
    // A budget of nought is passed by any frame; a day is passed by none;
    // no budget never fires.
    // Mutation: comparing with `<` instead of `>` in `RenderListener.notify`
    // fires for the day and not for nought.
    final it = _stage();
    final over = <(FrameResult, Duration)>[];
    void record(FrameResult r, Duration budget) => over.add((r, budget));

    it.renderer.listener = RenderListener(
      overTime: record,
      frameBudget: Duration.zero,
    );
    final late = _render(it);
    expect(over, hasLength(1));
    expect(over.single.$1, same(late));
    expect(over.single.$2, Duration.zero);

    it.renderer.listener = RenderListener(
      overTime: record,
      frameBudget: const Duration(days: 1),
    );
    _render(it);
    it.renderer.listener = RenderListener(overTime: record);
    _render(it);
    expect(over, hasLength(1));
  });
}
