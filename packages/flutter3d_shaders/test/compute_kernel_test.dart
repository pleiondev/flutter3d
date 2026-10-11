// `.f3dmat compute`: read once into one checked tree, translated to WGSL and
// to Dart, and the Dart kernel computing what WGSL defines.
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/kernel.dart';
import 'package:test/test.dart';

const String _scale = '''
compute Scale {
  workgroup 64;
  buffer values: f32[] read_write;
  buffer factor: f32[] read;
  kernel {
    let i = id.x;
    if i >= len(values) { return; }
    values[i] = values[i] * factor[0];
  }
}
''';

/// Runs [body] as a one-invocation kernel writing a `u32` or `f32` result
/// into `out[0]`, and answers it.
num _eval(String body, {String type = 'u32'}) {
  final kernel = ComputeKernel.parse('''
compute Probe {
  workgroup 1;
  buffer out: $type[] read_write;
  kernel {
    $body
  }
}
''');
  final out = ByteData(4);
  kernel.toDartKernel().dispatch(KernelInputs(buffers: {'out': out}), 1);
  return switch (type) {
    'f32' => out.getFloat32(0, Endian.little),
    'i32' => out.getInt32(0, Endian.little),
    _ => out.getUint32(0, Endian.little),
  };
}

Matcher _refusedAt(int line, String reason) => throwsA(
  isA<ComputeKernelException>()
      .having((e) => e.line, 'line', line)
      .having((e) => e.reason, 'reason', contains(reason)),
);

void main() {
  group('reading', () {
    test('a kernel names its workgroup and its bindings in order', () {
      // Mutation: number the bindings from one, and WebGPU binds the
      // factor where the values belong.
      final kernel = ComputeKernel.parse(_scale);
      expect(kernel.name, 'Scale');
      expect(kernel.workgroupSize, (64, 1, 1));
      expect(kernel.bindings.map((b) => (b.name, b.index, b.writable)), [
        ('values', 0, true),
        ('factor', 1, false),
      ]);
      expect(kernel.binding('factor')!.kind, KernelBindingKind.buffer);
      expect(kernel.groupsFor(65), 2);
    });

    test('blocks that are not kernels are skipped', () {
      final kernels = ComputeKernel.parseAll('''
material Glow { fragment { return vec4(1.0); } }
$_scale
''');
      expect(kernels.single.name, 'Scale');
    });

    test('a write to a read buffer is refused where it is written', () {
      // Mutation: accept it, and WebGPU refuses the module at load with a
      // message about an access mode nobody wrote.
      expect(
        () => ComputeKernel.parse(
          _scale.replaceAll('values[i] = values[i]', 'factor[0] = values[i]'),
        ),
        _refusedAt(8, 'read only'),
      );
    });

    test('mixed types are refused, naming both', () {
      expect(
        () => _eval('let a = 1u; let b = 2i; out[0] = a + b;'),
        _refusedAt(5, 'u32 + i32'),
      );
    });

    test(
      'an unknown name, a loose break and a large workgroup are refused',
      () {
        expect(() => _eval('out[0] = nothing;'), _refusedAt(5, '"nothing"'));
        expect(() => _eval('break;'), _refusedAt(5, 'outside a loop'));
        expect(
          () => ComputeKernel.parse(
            _scale.replaceAll('workgroup 64', 'workgroup 512'),
          ),
          _refusedAt(2, 'more than every device runs'),
        );
      },
    );
  });

  group('the Dart kernel computes what WGSL defines', () {
    test('every f32 operation is rounded to an f32', () {
      // Mutation: compute in doubles, and 2^24 + 1 survives where every
      // GPU loses the one.
      expect(_eval('out[0] = 16777216.0 + 1.0;', type: 'f32'), 16777216.0);
      expect(
        _eval('let t = 0.1; out[0] = t * 3.0;', type: 'f32'),
        0.30000001192092896,
      );
    });

    test(
      'integers wrap at 32 bits, and a division by zero is the dividend',
      () {
        expect(_eval('let a = 4294967295u; out[0] = a + 2u;'), 1);
        expect(_eval('let a = 65536u; out[0] = a * a + 7u;'), 7);
        expect(_eval('let a = 9u; let z = 0u; out[0] = a / z;'), 9);
        expect(_eval('let a = 9u; let z = 0u; out[0] = a % z;'), 0);
        expect(_eval('let a = -7; out[0] = a / 2;', type: 'i32'), -3);
        expect(_eval('let s = 33u; out[0] = 1u << s;'), 2);
      },
    );

    test(
      'round breaks ties to even, and a conversion truncates and clamps',
      () {
        expect(_eval('out[0] = round(2.5);', type: 'f32'), 2.0);
        expect(_eval('out[0] = round(3.5);', type: 'f32'), 4.0);
        expect(_eval('let x = -2.7; out[0] = i32(x);', type: 'i32'), -2);
        expect(_eval('let x = -2.7; out[0] = u32(x);'), 0);
        expect(_eval('let x = 1e20; out[0] = u32(x);'), 0xFFFFFFFF);
      },
    );

    test('loops, vectors and select', () {
      expect(
        _eval('''
var total = 0u;
for i in 0u .. 10u {
  if i == 7u { break; }
  if i % 2u == 0u { continue; }
  total += i;
}
out[0] = total;'''),
        1 + 3 + 5,
      );
      expect(
        _eval(
          'let v = vec3(1.0, 2.0, 3.0) * 2.0; out[0] = v.z + v.x;',
          type: 'f32',
        ),
        8.0,
      );
      expect(_eval('out[0] = select(1u > 2u, 5u, 6u);'), 6);
    });

    test(
      'a buffer read past its end is zero, and a write there is dropped',
      () {
        final kernel = ComputeKernel.parse(_scale);
        final values = ByteData(8)
          ..setFloat32(0, 1.5, Endian.little)
          ..setFloat32(4, 2, Endian.little);
        kernel.toDartKernel().dispatch(
          KernelInputs(buffers: {'values': values, 'factor': ByteData(0)}),
          1,
        );
        expect(values.getFloat32(0, Endian.little), 0);
        expect(values.getFloat32(4, Endian.little), 0);
      },
    );

    test('textures load and images store as RGBA8 levels, ties to even', () {
      final kernel = ComputeKernel.parse('''
compute Copy {
  workgroup 2, 2;
  texture source: rgba8;
  image target: rgba8;
  kernel {
    let x = i32(id.x);
    let y = i32(id.y);
    store(target, x, y, load(source, x, y) * 0.5);
  }
}
''');
      final source = KernelPixels(
        2,
        2,
        rgba: Uint8List.fromList(<int>[for (var i = 0; i < 16; i++) i * 17]),
      );
      final target = KernelPixels(2, 2);
      kernel.toDartKernel().dispatch(
        KernelInputs(textures: {'source': source}, images: {'target': target}),
        1,
      );
      expect(target.rgba, <int>[
        for (var i = 0; i < 16; i++) unormLevel(unormValue(i * 17) * 0.5),
      ]);
    });
  });

  group('WGSL', () {
    test('one module, bindings in group zero, the entry point main', () {
      // Mutation: drop the prefixes, and a kernel with a local called
      // `ptr` is a WGSL syntax error on the device.
      final wgsl = ComputeKernel.parse(_scale).toWgsl();
      expect(wgsl.entryPoint, 'main');
      expect(
        wgsl.code,
        contains(
          '@group(0) @binding(0) var<storage, read_write> b_values: array<f32>;',
        ),
      );
      expect(
        wgsl.code,
        contains(
          '@group(0) @binding(1) var<storage, read> b_factor: array<f32>;',
        ),
      );
      expect(wgsl.code, contains('@compute @workgroup_size(64, 1, 1)'));
    });

    test('every f32 product and sum goes through f3d_exact', () {
      // Mutation: emit the product bare, and Metal fuses it into the sum
      // beside it: the conformance kernels then differ by an ulp.
      final wgsl = ComputeKernel.parse(_scale).toWgsl().code;
      expect(wgsl, contains('f3d_exact(b_values[l_i] * b_factor[0i])'));
      expect(wgsl, contains('f3d_zero = f3d_id.z >> 31u;'));
    });

    test('the barrier survives being applied twice', () {
      // Dawn compiles under Metal's relaxed math, which folds `0.0 + x` to
      // `x`; a sum that starts at zero then wraps one barrier straight in
      // another, and an exclusive or twice with one value is no or at all.
      // The product beneath came out bare and fused into the next sum: the
      // skinning kernel an ulp off in 26 values of 512 on Chrome. An
      // inclusive or with zero survives a second one. Mutation: go back to
      // `^`, and this fails here and on Chrome's conformance run.
      final wgsl = ComputeKernel.parse(_scale).toWgsl().code;
      expect(wgsl, contains('bitcast<u32>(x) | f3d_zero'));
      expect(wgsl, isNot(contains('^')));
    });

    test('an image store is rounded to its level, ties to even', () {
      // A level halfway between two was stored half up on Chrome, where the
      // Dart kernel and wgpu round it to even: the blur kernel one level off
      // in 12 texels of 256. The store is handed the level's own value, which
      // every conversion reads back as that level. Mutation: store the sum
      // as it is.
      final wgsl = ComputeKernel.parse('''
compute Copy {
  workgroup 2, 2;
  texture source: rgba8;
  image target: rgba8;
  kernel {
    store(target, i32(id.x), i32(id.y), load(source, i32(id.x), i32(id.y)));
  }
}
''').toWgsl().code;
      expect(wgsl, contains('textureStore(b_target, '));
      expect(wgsl, contains(', f3d_unorm8(textureLoad('));
      expect(
        wgsl,
        contains(
          'return round(clamp(v, vec4<f32>(0.0f), vec4<f32>(1.0f)) * '
          '255.0f) / 255.0f;',
        ),
      );
    });
  });

  group('bundles', () {
    test('a kernel bundle carries each kernel by name, and reads back', () {
      final bundle = ShaderBundle.decode(
        kernelBundle('k', ComputeKernel.parseAll(_scale)).encode(),
      );
      expect(bundle.names, <String>['Scale']);
      expect(kernelsOf(bundle)['Scale']!.bindings, hasLength(2));
    });

    test('a kernel that does not read refuses its bundle, by name', () {
      final bundle = ShaderBundle(
        name: 'bad',
        sdk: '',
        stages: const <ShaderBundleStage>[
          ShaderBundleStage('Scale', fragment: false),
        ],
        sections: <String, ByteData>{
          ShaderBundle.kernelSection: encodeKernelSection(<String, String>{
            'Scale': 'compute Scale { kernel { oops } }',
          }),
        },
      );
      expect(
        () => kernelsOf(bundle),
        throwsA(
          isA<ShaderBundleException>()
              .having((e) => e.name, 'name', 'bad')
              .having((e) => e.reason, 'reason', contains('"Scale"')),
        ),
      );
    });
  });
}
