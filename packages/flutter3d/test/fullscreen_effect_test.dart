/// `gfx-28n`: a caller's own effect, in the frame on the same terms as ours.
///
///     flutter test test/fullscreen_effect_test.dart
///
/// **The claim is not that an effect can be added — it could be — but that it
/// is a pass like any other once it is.** It reports its time in
/// `FrameResult.passes`, it reports a reason in `skipped` when it does not
/// run, and it can be switched off by name through `disabledPasses` beside
/// `bloom` and `ssao`. An extension point whose members are second-class is an
/// extension point whose author has not used it.
///
/// Drawn on the software rasteriser rather than recorded on a fake, because
/// the half that is easy to get wrong is the hand-off: a pass that draws into
/// a texture nothing reads costs its time and shows nothing, and only pixels
/// can tell that apart from a shader that does nothing.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 32;

/// A stage that paints every pixel the same colour, so "did it run" is a
/// question about bytes rather than about shape.
final class _FlatShader implements CpuFragmentShader {
  const _FlatShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) =>
      Vector4(0.0, 1.0, 0.0, 1.0);
}

/// The builtin stages plus the one above, under a name of its own.
CpuShaderLibrary _shaders() => CpuShaderLibrary(<String, CpuStage>{
  ...builtinCpuShaders(),
  'Flat': const CpuStage.fragment(_FlatShader()),
});

/// Renders with [effects] registered, and returns the frame and its pixels.
Future<({FrameResult result, List<int> pixels})> _frame({
  List<FullscreenEffect> Function(ShaderLibrary shaders)? effects,
  RenderSettings settings = const RenderSettings(),
}) async {
  final device = CpuDevice(width: _size, height: _size, shaders: _shaders());
  final renderer = Renderer.create(device: device);
  for (final effect in effects?.call(device.shaders) ?? <FullscreenEffect>[]) {
    renderer.nodes.add(effect);
  }

  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, SphereShape(radius: 0.5).build()),
        Material(name: 'ball', baseColor: Vector4(0.8, 0.2, 0.2, 1.0)),
      ),
    )
    ..add(
      LightNode(intensity: 5.0)
        ..setPosition(2.0, 3.0, 4.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(CameraNode()..setPosition(0.0, 0.0, 3.0));

  final result = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: settings,
  );
  final bytes = await device.readPixels(result.frame);
  return (
    result: result,
    pixels: <int>[
      for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i),
    ],
  );
}

void main() {
  test('an effect in the present phase reaches the pixels', () async {
    // Flat green over the whole frame, after the composite. If the hand-off
    // is missing the pass still runs, still costs its time, and the frame is
    // the ball — which is the failure this test exists to tell apart from a
    // shader that does nothing.
    final plain = await _frame();
    final painted = await _frame(
      effects: (shaders) => <FullscreenEffect>[
        FullscreenEffect.present(name: 'flat', shader: shaders['Flat']!),
      ],
    );

    expect(painted.pixels, isNot(plain.pixels));
    expect(painted.pixels.take(4).toList(), <int>[
      0,
      255,
      0,
      255,
    ], reason: 'the top-left pixel is the effect, not the scene behind it');
  });

  test('it is a pass in the report, with its own time', () async {
    final painted = await _frame(
      effects: (shaders) => <FullscreenEffect>[
        FullscreenEffect.present(name: 'flat', shader: shaders['Flat']!),
      ],
    );

    expect(painted.result.passes.map((p) => p.name), contains('flat'));
    expect(
      painted.result.passes.firstWhere((p) => p.name == 'flat').drawCalls,
      1,
      reason: 'one full-screen triangle, counted like every other pass',
    );
  });

  test('it can be switched off by name, beside the engine\'s own', () async {
    // **The key space, which is the half of this row that is not a
    // convenience.** A caller types 'flat' into the same set they type
    // 'bloom' into, and the graph accepts it because the name is registered.
    final plain = await _frame();
    final off = await _frame(
      effects: (shaders) => <FullscreenEffect>[
        FullscreenEffect.present(name: 'flat', shader: shaders['Flat']!),
      ],
      settings: const RenderSettings(disabledPasses: <String>{'flat'}),
    );

    expect(off.pixels, plain.pixels);
    expect(off.result.skipReasonOf('flat'), PassSkip.disabled);
  });

  test(
    'switched off by its own flag it reports the settings instead',
    () async {
      // Two ways to be off and two different answers, which is the whole of
      // `gfx-39n` applied to somebody else's pass: 'disabled' means a caller
      // named it and 'settings' means the node said there was nothing to do.
      final plain = await _frame();
      final off = await _frame(
        effects: (shaders) => <FullscreenEffect>[
          FullscreenEffect.present(
            name: 'flat',
            shader: shaders['Flat']!,
            enabled: false,
          ),
        ],
      );

      expect(off.pixels, plain.pixels);
      expect(off.result.skipReasonOf('flat'), PassSkip.settings);
    },
  );

  test('an overlay effect is registered before the composite', () async {
    // The phase decides which version it reads, and the node says which
    // phase it belongs to — so a caller who leaves the argument off gets the
    // one the effect was built for rather than the default.
    final painted = await _frame(
      effects: (shaders) => <FullscreenEffect>[
        FullscreenEffect.overlay(name: 'flat', shader: shaders['Flat']!),
      ],
    );
    final ran = painted.result.passes.map((p) => p.name).toList();

    expect(ran.indexOf('flat'), lessThan(ran.indexOf('composite')));
  });

  test('a present effect is registered after it, without being told', () async {
    final painted = await _frame(
      effects: (shaders) => <FullscreenEffect>[
        FullscreenEffect.present(name: 'flat', shader: shaders['Flat']!),
      ],
    );
    final ran = painted.result.passes.map((p) => p.name).toList();

    expect(ran.indexOf('flat'), greaterThan(ran.indexOf('composite')));
  });

  test('two effects chain, in registration order', () async {
    // The version chain, from outside: the second reads what the first left.
    // Both paint flat, so what this actually holds is that both ran and
    // neither overwrote the other's target with a stale read.
    final painted = await _frame(
      effects: (shaders) => <FullscreenEffect>[
        FullscreenEffect.present(name: 'flat', shader: shaders['Flat']!),
        FullscreenEffect.present(name: 'flat again', shader: shaders['Flat']!),
      ],
    );
    final ran = painted.result.passes.map((p) => p.name).toList();

    expect(ran.indexOf('flat'), lessThan(ran.indexOf('flat again')));
    expect(painted.pixels.take(4).toList(), <int>[0, 255, 0, 255]);
  });
}
