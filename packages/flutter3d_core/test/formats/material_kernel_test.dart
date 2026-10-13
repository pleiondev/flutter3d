// The material language's `compute` form, lowered to the kernel language:
// one kernel, so it computes what a hand-written kernel computes, and is
// refused by name where a device has no compute.
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_shaders/kernel.dart';
import 'package:test/test.dart';

const String _ripples = '''
f3dmat 2
compute Ripples {
  uniform float time = 0.0;
  uniform vec3 tint = vec3(1.0, 0.5, 0.25);
  param float rings = 40.0;
  workgroup 8 4;
  kernel {
    let d = length(uv - vec2(0.5));
    let wave = 0.5 + 0.5 * sin(rings * d - time);
    return vec4(tint * wave, 1.0);
  }
}
''';

/// [_ripples], written by hand in the kernel language.
const String _handWritten = '''
compute Ripples {
  workgroup 8, 4;
  image target: rgba8;
  buffer params: f32[];
  kernel {
    let x = id.x;
    let y = id.y;
    if x >= width(target) || y >= height(target) { return; }
    let size = vec2(f32(width(target)), f32(height(target)));
    let uv = (vec2(f32(x), f32(y)) + vec2(0.5, 0.5)) / size;
    let p = uv - vec2(0.5, 0.5);
    let d = sqrt(p.x * p.x + p.y * p.y);
    let wave = 0.5 + 0.5 * sin(40.0 * d - params[0]);
    let tint = vec3(params[1], params[2], params[3]);
    store(target, x, y, vec4(tint * wave, 1.0));
  }
}
''';

MaterialComputeKernel _lower(String source) =>
    lowerMaterialCompute(parseMaterial(source));

void main() {
  test('the compute form is lowered to version 1 of the kernel language', () {
    final lowered = _lower(_ripples);
    expect(lowered.source, startsWith('kernel $kernelLanguageVersion\n'));
    expect(lowered.kernel.languageVersion, kernelLanguageVersion);
    expect(lowered.workgroupSize, const WorkgroupSize(8, 4, 1));
    expect(
      lowered.kernel.bindings.map((b) => (b.name, b.kind, b.index)),
      <(String, KernelBindingKind, int)>[
        (materialComputeTarget, KernelBindingKind.image, 0),
        (materialComputeParameters, KernelBindingKind.buffer, 1),
      ],
    );
    expect(lowered.uniforms.map((u) => u.name), <String>['time', 'tint']);
    expect(lowered.groupsX(17), 3);
    expect(lowered.groupsY(17), 5);
  });

  test('a material workgroup has three numbers, one z without a third', () {
    // Mutation: keep reading two, and a kernel over a volume cannot say
    // its depth.
    expect(parseMaterial(_ripples).workgroupSize, const WorkgroupSize(8, 4, 1));
    expect(
      parseMaterial(
        _ripples.replaceAll('workgroup 8 4;', 'workgroup 4 4 4;'),
      ).workgroupSize,
      const WorkgroupSize(4, 4, 4),
    );
    expect(
      () => parseMaterial(
        _ripples.replaceAll('workgroup 8 4;', 'workgroup 16 16 2;'),
      ),
      throwsA(
        isA<MaterialSyntaxException>().having(
          (e) => e.message,
          'message',
          contains('at most 256 invocations'),
        ),
      ),
    );
  });

  test('the lowered form computes the bytes of the hand-written kernel', () {
    // Mutation: compute uv from the cell without the half texel, or read
    // the tint from the wrong place in params, and the bytes differ.
    final lowered = _lower(_ripples);
    const values = <String, List<double>>{
      'time': <double>[0.75],
      'tint': <double>[0.9, 0.6, 0.3],
    };
    const width = 19;
    const height = 13;
    final sugar = lowered.bake(width, height, parameters: values);

    final hand = KernelPixels(width, height);
    final kernel = ComputeKernel.parse(_handWritten);
    kernel.toDartKernel().dispatch(
      KernelInputs(
        buffers: <String, ByteData>{
          'params': ByteData(16)
            ..setFloat32(0, 0.75, Endian.little)
            ..setFloat32(4, 0.9, Endian.little)
            ..setFloat32(8, 0.6, Endian.little)
            ..setFloat32(12, 0.3, Endian.little),
        },
        images: <String, KernelImage>{'target': hand},
      ),
      (width + 7) ~/ 8,
      (height + 3) ~/ 4,
    );
    expect(sugar.rgba, hand.rgba);
    // And it drew something: rings, not one colour.
    expect(sugar.rgba.toSet().length, greaterThan(8));
  });

  test('a uniform at its default when no value is given', () {
    final lowered = _lower(_ripples);
    final bytes = lowered.parameterBytes(
      values: const <String, List<double>>{
        'time': <double>[2.0],
      },
    );
    expect(
      <double>[
        for (var i = 0; i < 4; i++) bytes.getFloat32(i * 4, Endian.little),
      ],
      <double>[2.0, 1.0, 0.5, 0.25],
    );
    expect(
      () => lowered.parameterBytes(
        values: const <String, List<double>>{
          'tint': <double>[1.0],
        },
      ),
      throwsArgumentError,
    );
  });

  test('sample reads the texel itself at its centre, and blends between', () {
    // Mutation: sample without the half-texel offset, and a copy at the
    // same size is a blur.
    final lowered = _lower('''
f3dmat 2
compute Copy {
  texture source = source;
  kernel { return sample(source, uv); }
}
''');
    expect(lowered.textures, <String>['source']);
    final source = KernelPixels(
      4,
      3,
      rgba: Uint8List.fromList(<int>[for (var i = 0; i < 48; i++) i * 5]),
    );
    final copy = lowered.bake(
      4,
      3,
      textures: <String, KernelTexture>{'source': source},
    );
    expect(copy.rgba, source.rgba);

    // Half size: each texel the mean of the four under it.
    final half = lowered.bake(
      2,
      1,
      textures: <String, KernelTexture>{
        'source': KernelPixels(
          4,
          2,
          rgba: Uint8List.fromList(<int>[
            for (var t = 0; t < 8; t++) ...<int>[t.isEven ? 0 : 200, 0, 0, 255],
          ]),
        ),
      },
    );
    expect(half.rgba.sublist(0, 4), <int>[100, 0, 0, 255]);
  });

  test('every builtin of the material language lowers', () {
    final lowered = _lower('''
f3dmat 2
compute All {
  uniform vec2 at = vec2(0.25, 0.75);
  kernel {
    let a = dot(uv, at) + length(uv) + normalize(uv).x;
    let b = mix(0.2, 0.8, uv.x) + smoothstep(0.0, 1.0, uv.y);
    let c = step(0.5, uv.x) + pow(uv.y + 1.0, 2.0) + fract(a * 3.0);
    let d = clamp(uv, 0.1, 0.9) + min(uv, at) + max(abs(-uv), floor(at));
    let e = sqrt(b) + cos(c) + sin(d.x);
    return vec4(fract(e), d.y * 0.5, fract(a + c), 1.0);
  }
}
''');
    final pixels = lowered.bake(8, 8);
    expect(pixels.rgba.toSet().length, greaterThan(8));
  });

  test('a device without compute refuses the stage by naming it', () async {
    // Mutation: hand the bundle to the device, and Impeller refuses a
    // bundle with no section of its own, which says nothing of compute.
    final lowered = _lower(_ripples);
    await expectLater(
      lowered.load(FakeBackend()),
      throwsA(
        isA<UnsupportedCapabilityException>()
            .having((e) => e.feature, 'feature', DeviceFeature.compute)
            .having((e) => e.message, 'message', contains('bake')),
      ),
    );
  });

  test('a stage of another kind is not lowered', () {
    expect(
      () => lowerMaterialCompute(
        parseMaterial('material Flat { fragment { return vec4(1.0); } }'),
      ),
      throwsArgumentError,
    );
  });
}
