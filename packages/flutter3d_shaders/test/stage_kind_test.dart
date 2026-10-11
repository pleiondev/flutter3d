/// A stage says its kind, and a kernel is claimed as a compute stage.
///
/// A stage's kind was `bool fragment`, which has room for two kinds; a
/// kernel went into a bundle as a vertex stage, and a mesh or ray stage
/// could not be said at all. `ShaderStageKind` is open, and the types that
/// carried the bool carry the kind beside it.
///
/// Mutation: claim kernels with `fragment: false` again in `kernelBundle`.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/backend.dart';
import 'package:flutter3d_shaders/kernel.dart';
import 'package:flutter3d_shaders/flutter3d_shaders.dart';
import 'package:test/test.dart';

void main() {
  test('a kernel bundle claims its kernels as compute stages', () {
    final kernel = ComputeKernel.parse('''
compute Scale {
  workgroup 64;
  buffer values: f32[] read_write;
  kernel {
    let i = id.x;
    if i >= len(values) { return; }
    values[i] = values[i] * 2.0;
  }
}
''');
    final bundle = kernelBundle('probe', <ComputeKernel>[kernel]);
    expect(bundle.stages.single.kind, ShaderStageKind.compute);
    expect(bundle.stages.single.fragment, isFalse);

    final back = ShaderBundle.decode(bundle.encode());
    expect(back.stages.single.kind, ShaderStageKind.compute);
  });

  test('the stage types say the kind the bool said, and more', () {
    const vertex = MaterialStageSource(name: 'GlowVertex', glsl: '');
    const fragment = MaterialStageSource(
      name: 'Glow',
      fragment: true,
      glsl: '',
    );
    const compute = MaterialStageSource(
      name: 'Spread',
      kind: ShaderStageKind.compute,
      glsl: '',
    );
    expect(<ShaderStageKind>[
      vertex.kind,
      fragment.kind,
      compute.kind,
    ], ShaderStageKind.values);
    expect(compute.fragment, isFalse);
  });

  test('every required entry point is a vertex or a fragment stage', () {
    for (final shader in requiredShaders) {
      expect(
        shader.kind,
        shader.fragment ? ShaderStageKind.fragment : ShaderStageKind.vertex,
        reason: shader.name,
      );
    }
    expect(
      const RequiredShader(name: 'Pbr', fragment: true),
      requiredShaders.firstWhere((RequiredShader s) => s.name == 'Pbr'),
    );
  });
}
