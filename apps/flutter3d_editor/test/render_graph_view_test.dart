/// The render-graph view: the last frame's passes in the order they ran, a
/// bar for each one's share of the slowest, the passes that did not run and
/// why — and a real frame reaching it the way the editor's viewport hands
/// one over.
///
///     flutter test test/render_graph_view_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_editor/src/editor_theme.dart';
import 'package:flutter3d_editor/src/render_graph_view.dart';
import 'package:flutter_test/flutter_test.dart';

({Renderer renderer, Scene scene, RenderView view}) _stage() {
  final device = CpuDevice(
    width: 16,
    height: 9,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  return (
    renderer: Renderer.create(device: device),
    scene: Scene(),
    view: RenderView(camera: CameraNode()),
  );
}

/// A frame with the passes and skips a test wants, on a real frame's
/// texture (a frame needs one, and nothing here reads it).
FrameResult _frame(
  TextureHandle texture, {
  required List<FramePass> passes,
  List<SkippedPass> skipped = const <SkippedPass>[],
}) => FrameResult(
  frame: texture,
  cpuMicros: 4000,
  submitMicros: 100,
  drawCalls: 12,
  triangles: 3400,
  instances: 0,
  culled: 5,
  pipelineSwitches: 3,
  debugLines: 0,
  lights: 2,
  lightsDropped: 0,
  pipelines: 4,
  shadowCasters: 0,
  skinnedDraws: 0,
  passes: passes,
  skipped: skipped,
);

FramePass _pass(String name, int micros, {int draws = 1}) => (
  name: name,
  active: true,
  micros: micros,
  gpuMicros: null,
  drawCalls: draws,
  triangles: draws * 100,
  pipelineSwitches: 1,
);

Widget _view(FrameResult? frame) => MaterialApp(
  theme: editorTheme(),
  home: Scaffold(body: RenderGraphView(frame: frame)),
);

TextureHandle _texture() {
  final it = _stage();
  return it.renderer
      .render(
        width: 16,
        height: 9,
        scene: it.scene,
        views: <RenderView>[it.view],
        settings: const RenderSettings(),
      )
      .frame;
}

void main() {
  testWidgets('says so before there is a frame', (WidgetTester tester) async {
    await tester.pumpWidget(_view(null));
    expect(find.text('No frame drawn yet'), findsOneWidget);
  });

  testWidgets('lists the passes in the order they ran, with the totals', (
    WidgetTester tester,
  ) async {
    // Mutation: sort `frame.passes` by name before listing them. "shadows"
    // then comes after "scene", which is not the order the frame ran in.
    await tester.pumpWidget(
      _view(
        _frame(
          _texture(),
          passes: <FramePass>[
            _pass('shadows', 500),
            _pass('scene', 2000, draws: 9),
            _pass('composite', 250),
          ],
        ),
      ),
    );

    // Top to bottom, as they ran.
    final heights = <double>[
      for (final name in <String>['shadows', 'scene', 'composite'])
        tester.getTopLeft(find.byKey(ValueKey<String>('graph.pass.$name'))).dy,
    ];
    expect(heights[0], lessThan(heights[1]));
    expect(heights[1], lessThan(heights[2]));
    expect(
      find.text(
        '3 passes · 12 draws · 3400 triangles · 5 culled · 2 lights · '
        '4.00 ms on the CPU',
      ),
      findsOneWidget,
    );
    expect(find.text('9 draws · 900 tris · 1 switches'), findsOneWidget);
  });

  testWidgets("each bar is the pass's share of the slowest", (
    WidgetTester tester,
  ) async {
    // Mutation: divide by the total of all passes rather than the slowest.
    // The slowest pass's bar is then short of full.
    await tester.pumpWidget(
      _view(
        _frame(
          _texture(),
          passes: <FramePass>[_pass('shadows', 500), _pass('scene', 2000)],
        ),
      ),
    );

    double share(String pass) => tester
        .widget<FractionallySizedBox>(
          find.descendant(
            of: find.byKey(ValueKey<String>('graph.pass.$pass')),
            matching: find.byType(FractionallySizedBox),
          ),
        )
        .widthFactor!;
    expect(share('scene'), 1.0);
    expect(share('shadows'), 0.25);
  });

  testWidgets('and says which passes did not run, and why', (
    WidgetTester tester,
  ) async {
    // Mutation: drop the "not run" section. A bloom switched off and a
    // bloom that ran in no time look the same.
    await tester.pumpWidget(
      _view(
        _frame(
          _texture(),
          passes: <FramePass>[_pass('scene', 2000)],
          skipped: const <SkippedPass>[
            (name: 'bloom', reason: PassSkip.settings),
          ],
        ),
      ),
    );

    expect(find.text('bloom — settings'), findsOneWidget);
  });

  testWidgets('a frame the viewport drew reaches it', (
    WidgetTester tester,
  ) async {
    // The editor's path, with a software renderer in place of the GPU: the
    // surface hands each frame to `onFrame`, the editor keeps it, the view
    // lists its passes. Every one of the frame's own passes is on screen.
    final it = _stage();
    FrameResult? kept;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 16,
          height: 9,
          child: SceneSurface(
            renderer: it.renderer,
            scene: it.scene,
            view: it.view,
            onBeforeFrame: () {},
            settings: () => const RenderSettings(),
            onFrame: (FrameInfo frame) => kept = frame.result,
            presentFrame:
                (
                  GraphicsDevice device,
                  TextureHandle frame, {
                  BoxFit fit = BoxFit.fill,
                  FilterQuality quality = FilterQuality.none,
                }) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    final frame = kept!;
    expect(frame.passes, isNotEmpty);

    await tester.pumpWidget(_view(frame));

    for (final pass in frame.passes) {
      expect(
        find.byKey(ValueKey<String>('graph.pass.${pass.name}')),
        findsOneWidget,
      );
    }
  });
}
