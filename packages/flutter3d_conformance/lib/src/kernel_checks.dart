/// The four kernels every compute placement is held to, in `.f3dmat
/// compute`, each against an answer worked out here — 1.0.
///
/// **The same bytes on every placement**, which is the claim a frame graph
/// that moves a step between the device, the wgpu sidecar and the CPU
/// rests on. The answers below are written out independently of the
/// kernels' Dart translation: each f32 operation rounded where the kernel
/// rounds it, the RGBA8 store rounded half to even. A device whose bytes
/// differ in one place fails with the index.
///
/// The kernels keep to what every placement computes exactly: `+`, `-`,
/// `*`, the integers, guarded indices and the RGBA8 conversions. A
/// prefix sum (every output depends on every input before it), a particle
/// step (a branch per invocation), a skinning pass (a sum of four products,
/// the case a fused multiply-add would change) and a blur (a sampled texture
/// in, a storage texture out).
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/kernel.dart';

import '../flutter3d_conformance.dart';

/// The four kernels, as one `.f3dmat compute` file.
const String conformanceKernels = r'''
// The four kernels conformance holds every compute placement to.

compute PrefixSum {
  workgroup 64;
  buffer input: u32[] read;
  buffer sums: u32[] read_write;
  kernel {
    let i = id.x;
    if i >= len(sums) { return; }
    var total = 0u;
    for j in 0u .. i + 1u {
      total += input[j];
    }
    sums[i] = total;
  }
}

compute ParticleStep {
  workgroup 64;
  // Eight floats a particle: position, unused, velocity, unused.
  buffer particles: f32[] read_write;
  // The step, the gravity along y, the floor's height, the restitution.
  buffer params: f32[] read;
  kernel {
    let i = id.x;
    if i * 8u >= len(particles) { return; }
    let base = i * 8u;
    let dt = params[0];
    var vx = particles[base + 4u];
    var vy = particles[base + 5u] + params[1] * dt;
    var vz = particles[base + 6u];
    var px = particles[base] + vx * dt;
    var py = particles[base + 1u] + vy * dt;
    var pz = particles[base + 2u] + vz * dt;
    if py < params[2] {
      py = params[2];
      vy = -vy * params[3];
    }
    particles[base] = px;
    particles[base + 1u] = py;
    particles[base + 2u] = pz;
    particles[base + 4u] = vx;
    particles[base + 5u] = vy;
    particles[base + 6u] = vz;
  }
}

compute Skin {
  workgroup 64;
  // Four floats a vertex, the fourth unused.
  buffer rest: f32[] read;
  // Two joints a vertex.
  buffer joints: u32[] read;
  // Two weights a vertex.
  buffer weights: f32[] read;
  // Twelve floats a joint: a 3 × 4 matrix, row by row.
  buffer matrices: f32[] read;
  buffer skinned: f32[] read_write;
  kernel {
    let v = id.x;
    if v * 4u >= len(skinned) { return; }
    let p = vec3(rest[v * 4u], rest[v * 4u + 1u], rest[v * 4u + 2u]);
    var out = vec3(0.0);
    for k in 0u .. 2u {
      let m = joints[v * 2u + k] * 12u;
      let w = weights[v * 2u + k];
      let x = matrices[m] * p.x + matrices[m + 1u] * p.y + matrices[m + 2u] * p.z + matrices[m + 3u];
      let y = matrices[m + 4u] * p.x + matrices[m + 5u] * p.y + matrices[m + 6u] * p.z + matrices[m + 7u];
      let z = matrices[m + 8u] * p.x + matrices[m + 9u] * p.y + matrices[m + 10u] * p.z + matrices[m + 11u];
      out = out + vec3(x, y, z) * w;
    }
    skinned[v * 4u] = out.x;
    skinned[v * 4u + 1u] = out.y;
    skinned[v * 4u + 2u] = out.z;
    skinned[v * 4u + 3u] = 1.0;
  }
}

compute Blur {
  workgroup 8, 8;
  texture source: rgba8;
  image target: rgba8;
  kernel {
    let x = i32(id.x);
    let y = i32(id.y);
    let w = i32(width(source));
    let h = i32(height(source));
    if x >= w || y >= h { return; }
    var sum = vec4(0.0);
    for dy in -1 .. 2 {
      for dx in -1 .. 2 {
        let sx = clamp(x + dx, 0, w - 1);
        let sy = clamp(y + dy, 0, h - 1);
        let weight = f32((2 - abs(dx)) * (2 - abs(dy))) * 0.0625;
        sum = sum + load(source, sx, sy) * weight;
      }
    }
    store(target, x, y, sum);
  }
}
''';

/// A deterministic sequence, the same on every platform: a check's inputs.
final class _Inputs {
  int _seed = 0x5EED;

  int next() => _seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF;

  double between(double lo, double hi) =>
      _f(lo + (hi - lo) * (next() / 0x7FFFFFFF));
}

final Float32List _scratch = Float32List(1);

/// [x] as the nearest f32.
double _f(double x) {
  _scratch[0] = x;
  return _scratch[0];
}

ByteData _floats(List<double> values) {
  final out = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    out.setFloat32(i * 4, values[i], Endian.little);
  }
  return out;
}

ByteData _uints(List<int> values) {
  final out = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    out.setUint32(i * 4, values[i], Endian.little);
  }
  return out;
}

/// The kernel called [name], loaded on [device] from a bundle that carries
/// all four; declines on a device without compute.
Future<ShaderHandle> _kernel(GraphicsDevice device, String name) async {
  if (!device.features.has(DeviceFeature.compute)) {
    decline(
      device,
      'has no compute; a frame places its compute steps on the wgpu sidecar '
      'or the CPU instead',
    );
  }
  final bundle = kernelBundle(
    'conformance kernels',
    ComputeKernel.parseAll(conformanceKernels),
  );
  final library = await device.loadShaders(bundle.encode());
  final stage = library[name];
  require(
    stage != null,
    'a bundle carrying the kernel "$name" loaded, and the library has no '
    'stage of that name',
  );
  return stage!;
}

StorageBuffer _buffer(GraphicsDevice device, ByteData contents) =>
    device.createBuffer(
      BufferDescriptor(
        lengthInBytes: contents.lengthInBytes,
        usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
      ),
      contents: contents,
    );

/// Runs [stage] over [groups] workgroups along x with [buffers] bound by
/// name, and reads back the one called [result].
Future<ByteData> _run(
  GraphicsDevice device,
  ShaderHandle stage,
  Map<String, ByteData> buffers,
  String result,
  int groups,
) async {
  final made = <String, StorageBuffer>{
    for (final MapEntry(:key, :value) in buffers.entries)
      key: _buffer(device, value),
  };
  final pass = device.beginComputePass(label: stage.name)
    ..bindPipeline(
      device.createComputePipelineFrom(
        ComputePipelineDescriptor(shader: stage),
      ),
    );
  for (final MapEntry(:key, :value) in made.entries) {
    require(
      pass.bindStorageBuffer(stage, key, value),
      'the kernel "${stage.name}" declares the buffer "$key", and binding it '
      'answered false',
    );
  }
  pass
    ..dispatch(groups)
    ..submit();
  final out = await device.readBuffer(made[result]!);
  for (final buffer in made.values) {
    device.releaseStorageBuffer(buffer);
  }
  return out;
}

/// Holds [got] to [want] byte for byte, naming the first element that
/// differs as [what] reads it.
void _same(
  ByteData got,
  ByteData want,
  String kernel,
  String Function(int) at,
) {
  require(
    got.lengthInBytes >= want.lengthInBytes,
    '$kernel came back ${got.lengthInBytes} bytes long, not '
    '${want.lengthInBytes}',
  );
  for (var i = 0; i + 4 <= want.lengthInBytes; i += 4) {
    if (got.getUint32(i, Endian.little) == want.getUint32(i, Endian.little)) {
      continue;
    }
    require(
      false,
      '$kernel differs at ${at(i ~/ 4)}: '
      '0x${got.getUint32(i, Endian.little).toRadixString(16)} where '
      '0x${want.getUint32(i, Endian.little).toRadixString(16)} belongs. A '
      'difference of one in the last bits of a float is a product the '
      'compiler fused into a multiply-add, or a sum it reordered; the WGSL '
      'translation rounds each one to stop that',
    );
  }
}

/// `PrefixSum` over 256 numbers below 65536.
Future<void> checkKernelPrefixSum(GraphicsDevice device) async {
  final stage = await _kernel(device, 'PrefixSum');
  const n = 256;
  final inputs = _Inputs();
  final input = <int>[for (var i = 0; i < n; i++) inputs.next() & 0xFFFF];
  var total = 0;
  final want = _uints(<int>[
    for (final value in input) total = (total + value).toUnsigned(32),
  ]);
  final got = await _run(
    device,
    stage,
    <String, ByteData>{'input': _uints(input), 'sums': ByteData(n * 4)},
    'sums',
    n ~/ 64,
  );
  _same(got, want, 'PrefixSum', (int i) => 'element $i');
}

/// `ParticleStep` over 200 particles, some of them below the floor.
Future<void> checkKernelParticleStep(GraphicsDevice device) async {
  final stage = await _kernel(device, 'ParticleStep');
  const n = 200;
  final inputs = _Inputs();
  final particles = <double>[
    for (var i = 0; i < n; i++) ...<double>[
      inputs.between(-5, 5),
      inputs.between(-0.1, 3),
      inputs.between(-5, 5),
      0,
      inputs.between(-2, 2),
      inputs.between(-3, 3),
      inputs.between(-2, 2),
      0,
    ],
  ];
  // A step, a pull along y, a floor and a bounce: numbers for the kernel to
  // add and multiply, not a world's gravity.
  final params = <double>[_f(1 / 60), _f(-12.5), 0, 0.5];
  final want = List<double>.of(particles);
  final dt = params[0];
  for (var i = 0; i < n; i++) {
    final b = i * 8;
    final vx = want[b + 4];
    var vy = _f(want[b + 5] + _f(params[1] * dt));
    final vz = want[b + 6];
    final px = _f(want[b] + _f(vx * dt));
    var py = _f(want[b + 1] + _f(vy * dt));
    final pz = _f(want[b + 2] + _f(vz * dt));
    if (py < params[2]) {
      py = params[2];
      vy = _f(-vy * params[3]);
    }
    want
      ..[b] = px
      ..[b + 1] = py
      ..[b + 2] = pz
      ..[b + 4] = vx
      ..[b + 5] = vy
      ..[b + 6] = vz;
  }
  final got = await _run(
    device,
    stage,
    <String, ByteData>{
      'particles': _floats(particles),
      'params': _floats(params),
    },
    'particles',
    (n + 63) ~/ 64,
  );
  _same(
    got,
    _floats(want),
    'ParticleStep',
    (int i) => 'particle ${i ~/ 8}, float ${i % 8}',
  );
}

/// `Skin` over 128 vertices and four joints, two a vertex.
Future<void> checkKernelSkin(GraphicsDevice device) async {
  final stage = await _kernel(device, 'Skin');
  const vertices = 128;
  const joints = 4;
  final inputs = _Inputs();
  final rest = <double>[
    for (var i = 0; i < vertices; i++) ...<double>[
      inputs.between(-1, 1),
      inputs.between(-1, 1),
      inputs.between(-1, 1),
      1,
    ],
  ];
  final which = <int>[
    for (var i = 0; i < vertices * 2; i++) inputs.next() % joints,
  ];
  final weights = <double>[
    for (var i = 0; i < vertices; i++)
      ...(() {
        final w = inputs.between(0, 1);
        return <double>[w, _f(1 - w)];
      })(),
  ];
  final matrices = <double>[
    for (var i = 0; i < joints * 12; i++) inputs.between(-1.5, 1.5),
  ];
  final want = <double>[];
  for (var v = 0; v < vertices; v++) {
    final (px, py, pz) = (rest[v * 4], rest[v * 4 + 1], rest[v * 4 + 2]);
    var out = <double>[0, 0, 0];
    for (var k = 0; k < 2; k++) {
      final m = which[v * 2 + k] * 12;
      final w = weights[v * 2 + k];
      double row(int r) => _f(
        _f(
              _f(_f(matrices[m + r] * px) + _f(matrices[m + r + 1] * py)) +
                  _f(matrices[m + r + 2] * pz),
            ) +
            matrices[m + r + 3],
      );
      final xyz = <double>[row(0), row(4), row(8)];
      out = <double>[for (var c = 0; c < 3; c++) _f(out[c] + _f(xyz[c] * w))];
    }
    want.addAll(<double>[...out, 1]);
  }
  final got = await _run(
    device,
    stage,
    <String, ByteData>{
      'rest': _floats(rest),
      'joints': _uints(which),
      'weights': _floats(weights),
      'matrices': _floats(matrices),
      'skinned': ByteData(vertices * 16),
    },
    'skinned',
    vertices ~/ 64,
  );
  _same(
    got,
    _floats(want),
    'Skin',
    (int i) => 'vertex ${i ~/ 4}, component ${i % 4}',
  );
}

/// `Blur` of a 16 × 16 RGBA8 texture into a storage texture.
Future<void> checkKernelBlur(GraphicsDevice device) async {
  final stage = await _kernel(device, 'Blur');
  if (!device.features.has(DeviceFeature.storageTextures) ||
      !device.textureFormatSupport(TextureFormat.r8g8b8a8UNormInt).storage) {
    decline(device, 'computes but writes no RGBA8 storage texture');
  }
  const size = 16;
  final inputs = _Inputs();
  final texels = Uint8List.fromList(<int>[
    for (var i = 0; i < size * size * 4; i++) inputs.next() & 0xFF,
  ]);
  final source = device.createTextureFromPixels(
    width: size,
    height: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData.sublistView(texels),
  );
  final target = device.createTexture(
    TextureDescriptor(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
      usage: TextureUsage.storage | TextureUsage.copySource,
    ),
  );
  final pass = device.beginComputePass(label: 'Blur')
    ..bindPipeline(
      device.createComputePipelineFrom(
        ComputePipelineDescriptor(shader: stage),
      ),
    );
  require(
    pass.bindTexture(stage, 'source', source),
    'the kernel "Blur" declares the texture "source", and binding it '
    'answered false',
  );
  require(
    pass.bindStorageTexture(stage, 'target', target),
    'the kernel "Blur" declares the image "target", and binding it answered '
    'false',
  );
  pass
    ..dispatch(size ~/ 8, size ~/ 8)
    ..submit();
  final got = await device.readback(target);

  final want = Uint8List(size * size * 4);
  double texel(int x, int y, int c) => _f(
    texels[((y.clamp(0, size - 1)) * size + x.clamp(0, size - 1)) * 4 + c] /
        255.0,
  );
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      for (var c = 0; c < 4; c++) {
        var sum = 0.0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final weight = _f((2 - dx.abs()) * (2 - dy.abs()) * 0.0625);
            sum = _f(sum + _f(texel(x + dx, y + dy, c) * weight));
          }
        }
        want[(y * size + x) * 4 + c] = roundHalfEven(
          _f(sum.clamp(0.0, 1.0) * 255.0),
        ).toInt();
      }
    }
  }
  for (var i = 0; i < want.length; i++) {
    final byte = got.getUint8(i);
    require(
      byte == want[i],
      'Blur differs at texel (${(i ~/ 4) % size}, ${(i ~/ 4) ~/ size}), '
      'channel ${i % 4}: $byte where ${want[i]} belongs',
    );
  }
  device
    ..releaseTexture(source)
    ..releaseTexture(target);
}

/// The four, as checks.
List<ConformanceCheck> get kernelChecks => <ConformanceCheck>[
  ConformanceCheck(
    name: 'a prefix sum kernel gives the same bytes',
    run: checkKernelPrefixSum,
  ),
  ConformanceCheck(
    name: 'a particle step kernel gives the same bytes',
    run: checkKernelParticleStep,
  ),
  ConformanceCheck(
    name: 'a skinning kernel gives the same bytes',
    run: checkKernelSkin,
  ),
  ConformanceCheck(
    name: 'a blur kernel gives the same bytes',
    run: checkKernelBlur,
  ),
];
