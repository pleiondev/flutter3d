/// The operations of the kernel language that are not exact, each held to
/// the tolerance `kernelTolerances` declares for it — since 1.0.0-rc.1+2.
///
/// **The device against the Dart translation of the same kernel.** The
/// kernel runs on the device and, in this process, translated to Dart (the
/// CPU placement, which computes every operation one way on every
/// machine); each result of `/`, `sqrt`, `sin`, `cos` and `pow` must lie
/// within the declared tolerance of the Dart one, over the inputs that
/// tolerance is declared for. On the CPU the two are the same code, and the
/// check holds them to the bit.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/kernel.dart';

import '../flutter3d_conformance.dart';

/// One kernel a function, each writing its result for input `i` to `out[i]`.
const String toleranceKernels = r'''
compute ToleranceDivide {
  workgroup 64;
  buffer a: f32[] read;
  buffer b: f32[] read;
  buffer out: f32[] read_write;
  kernel {
    let i = id.x;
    if i >= len(out) { return; }
    out[i] = a[i] / b[i];
  }
}

compute ToleranceSqrt {
  workgroup 64;
  buffer a: f32[] read;
  buffer b: f32[] read;
  buffer out: f32[] read_write;
  kernel {
    let i = id.x;
    if i >= len(out) { return; }
    out[i] = sqrt(a[i]) + b[i] * 0.0;
  }
}

compute ToleranceSin {
  workgroup 64;
  buffer a: f32[] read;
  buffer b: f32[] read;
  buffer out: f32[] read_write;
  kernel {
    let i = id.x;
    if i >= len(out) { return; }
    out[i] = sin(a[i]) + b[i] * 0.0;
  }
}

compute ToleranceCos {
  workgroup 64;
  buffer a: f32[] read;
  buffer b: f32[] read;
  buffer out: f32[] read_write;
  kernel {
    let i = id.x;
    if i >= len(out) { return; }
    out[i] = cos(a[i]) + b[i] * 0.0;
  }
}

compute TolerancePow {
  workgroup 64;
  buffer a: f32[] read;
  buffer b: f32[] read;
  buffer out: f32[] read_write;
  kernel {
    let i = id.x;
    if i >= len(out) { return; }
    out[i] = pow(a[i], b[i]);
  }
}
''';

const int _count = 256;
const double _pi = 3.14159265358979;

/// The inputs a function's tolerance is declared over, `_count` of each.
(List<double>, List<double>) _inputs(String operation) {
  final a = <double>[];
  final b = <double>[];
  var seed = 0x7015;
  double next() {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    return seed / 0x7FFFFFFF;
  }

  for (var i = 0; i < _count; i++) {
    switch (operation) {
      case '/':
        a.add((next() - 0.5) * 2000);
        b.add((next() < 0.5 ? -1 : 1) * (0.001 + next() * 1000));
      case 'sqrt':
        a.add(next() * 10000);
        b.add(0);
      case 'sin' || 'cos':
        a.add((next() * 2 - 1) * _pi);
        b.add(0);
      default:
        // pow: a positive base, |exponent × log2(base)| at most 6.
        a.add(0.25 + next() * 3.75);
        b.add((next() * 2 - 1) * 3);
    }
  }
  return (a, b);
}

ByteData _floats(List<double> values) {
  final out = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    out.setFloat32(i * 4, values[i], Endian.little);
  }
  return out;
}

/// Runs the kernel for [operation] on [device] and in Dart, and holds every
/// result to the operation's declared tolerance.
Future<void> _check(GraphicsDevice device, String operation) async {
  if (!device.features.has(DeviceFeature.compute)) {
    decline(
      device,
      'has no compute; a frame places its compute steps on the wgpu sidecar '
      'or the CPU instead',
    );
  }
  final name = switch (operation) {
    '/' => 'ToleranceDivide',
    'sqrt' => 'ToleranceSqrt',
    'sin' => 'ToleranceSin',
    'cos' => 'ToleranceCos',
    _ => 'TolerancePow',
  };
  final kernels = ComputeKernel.parseAll(toleranceKernels);
  final kernel = kernels.firstWhere((ComputeKernel k) => k.name == name);
  final (a, b) = _inputs(operation);
  final groups = (_count + 63) ~/ 64;

  final want = ByteData(_count * 4);
  kernel.toDartKernel().dispatch(
    KernelInputs(
      buffers: <String, ByteData>{
        'a': _floats(a),
        'b': _floats(b),
        'out': want,
      },
    ),
    groups,
  );

  final library = await device.loadShaders(
    kernelBundle('tolerance kernels', kernels).encode(),
  );
  final stage = library[name];
  require(stage != null, 'the tolerance bundle has no stage "$name"');
  StorageBuffer made(ByteData bytes) => device.createBuffer(
    BufferDescriptor(
      lengthInBytes: bytes.lengthInBytes,
      usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
    ),
    contents: bytes,
  );
  final buffers = <String, StorageBuffer>{
    'a': made(_floats(a)),
    'b': made(_floats(b)),
    'out': made(ByteData(_count * 4)),
  };
  final pass = device.beginComputePass(label: name)
    ..bindPipeline(
      device.createComputePipelineFrom(
        ComputePipelineDescriptor(shader: stage!),
      ),
    );
  for (final MapEntry(:key, :value) in buffers.entries) {
    pass.bindStorageBuffer(stage, key, value);
  }
  pass
    ..dispatch(groups)
    ..submit();
  final got = await device.readBuffer(buffers['out']!);
  for (final buffer in buffers.values) {
    device.releaseStorageBuffer(buffer);
  }

  final tolerance = kernelTolerances[operation]!;
  for (var i = 0; i < _count; i++) {
    final w = want.getFloat32(i * 4, Endian.little);
    final g = got.getFloat32(i * 4, Endian.little);
    require(
      tolerance.admits(w, g),
      '$operation of input $i (${a[i]}, ${b[i]}) came back $g where the CPU '
      'gives $w: ${ulpsBetween(w, g)} ulp, ${(w - g).abs()} apart, past the '
      'declared $tolerance',
    );
  }
}

/// One check an inexact operation.
List<ConformanceCheck> get kernelToleranceChecks => <ConformanceCheck>[
  for (final operation in kernelTolerances.keys)
    ConformanceCheck(
      name:
          'a kernel\'s "$operation" is within its declared tolerance of the '
          'CPU\'s',
      run: (GraphicsDevice device) => _check(device, operation),
    ),
];
