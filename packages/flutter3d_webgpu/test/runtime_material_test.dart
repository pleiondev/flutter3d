/// A material loaded while the game runs, spliced into this backend's own
/// `Unlit` stage — and the result handed to naga, which is what says it is
/// WGSL a browser takes.
///
///     flutter test test/runtime_material_test.dart
///
/// `flutter3d_plugin_runtime`'s `material_wgsl_test.dart` holds the splice
/// to a stand-in; this holds it to the stage the engine really ships, which
/// a regenerated `engine_shaders.dart` can reshape. On the VM because naga is
/// a program; without naga on `PATH` the validation is skipped and says so.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_shaders/compile.dart' show nagaExecutable;
import 'package:flutter3d_webgpu/engine_shaders.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu.dart';
import 'package:flutter_test/flutter_test.dart';

const String _glow = '''
material Glow {
  param vec3 tint = vec3(1.0, 0.6, 0.2);
  uniform float pulse = 0.5;
  uniform vec3 rim = vec3(0.1, 0.2, 0.3);
  texture base = base_color_texture;
  fragment {
    let t = sample(base, uv);
    let f = pow(1.0 - clamp(nDotV, 0.0, 1.0), 3.0);
    let c = mix(albedo * tint, rim, f) * pulse + t.rgb * 0.5;
    return vec4(clamp(c + vec3(world.x, normal.y, -1.5), 0.0, 4.0), alpha);
  }
}
''';

bool _nagaAnswers() {
  try {
    return Process.runSync(nagaExecutable, const <String>[
          '--version',
        ]).exitCode ==
        0;
  } on ProcessException {
    return false;
  }
}

void main() {
  final host = webGpuMaterialHost();
  final bundle = runtimeMaterialBundle(
    _glow,
    backend: 'webgpu',
    from: 'glow.f3dmat',
    webGpuHost: host,
  );
  final stage = decodeWebGpuSection(
    bundle.sections[ShaderBundle.webgpuSection]!,
  ).fragment['Glow']!;

  test('the section reads back with the host\'s bindings and the block', () {
    // Mutation: lose the host's reflection in the conversion, or give the
    // parameters a binding the host already uses.
    final unlit = webGpuEngineShaders.fragment['Unlit']!;
    expect(stage.blocks.map((b) => b.name), <String>[
      ...unlit.blocks.map((b) => b.name),
      'MaterialParams',
    ]);
    final taken = <int>{
      for (final block in unlit.blocks) block.binding,
      for (final sampler in unlit.samplers) ...<int>[
        sampler.textureBinding,
        sampler.samplerBinding,
      ],
    };
    expect(taken, isNot(contains(stage.blocks.last.binding)));
    expect(
      stage.samplers.map((s) => s.name),
      unlit.samplers.map((s) => s.name),
    );
  });

  test('naga takes the spliced stage', () {
    // Mutation: write a GLSL-only spelling — `vec3(...)` with a float
    // spread WGSL has no overload for, `clamp(vec3, float, float)` — or
    // keep the host's main_1 beside the new one. naga names the line.
    final directory = Directory.systemTemp.createTempSync('f3d_material_');
    try {
      final file = File('${directory.path}/glow.wgsl')
        ..writeAsStringSync(stage.wgsl);
      final result = Process.runSync(nagaExecutable, <String>[file.path]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    } finally {
      directory.deleteSync(recursive: true);
    }
  }, skip: _nagaAnswers() ? false : '$nagaExecutable is not on PATH');
}
