// How a frame of compute paces on the sidecar: the frame a simulation's
// workload records (a parameter write, two dispatches, its state read back
// for the host), run back to back, and how long each frame holds the
// calling isolate.
//
//     dart run benchmark/sidecar_pacing.dart
//
// Prints one line per case. "held" is the time the frame's calls keep the
// isolate, which is the UI isolate in an application: what a frame of the
// sidecar costs the frame that draws. "frame" is the whole frame, the read
// back included, which is what the simulation waits on.
// A benchmark prints its numbers.
// ignore_for_file: avoid_print
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/kernel.dart';
import 'package:flutter3d_wgpu/flutter3d_wgpu.dart';

const String _kernels = r'''
compute Step {
  workgroup 64;
  buffer particles: f32[] read_write;
  buffer params: f32[] read;
  kernel {
    let i = id.x;
    if i * 8u >= len(particles) { return; }
    let base = i * 8u;
    let dt = params[0];
    var vy = particles[base + 5u] + params[1] * dt;
    var py = particles[base + 1u] + vy * dt;
    if py < params[2] {
      py = params[2];
      vy = -vy * params[3];
    }
    particles[base + 1u] = py;
    particles[base + 5u] = vy;
  }
}

compute Damp {
  workgroup 64;
  buffer particles: f32[] read_write;
  kernel {
    let i = id.x;
    if i * 8u >= len(particles) { return; }
    particles[i * 8u + 4u] = particles[i * 8u + 4u] * 0.5;
  }
}
''';

Future<void> main() async {
  final GraphicsDevice device;
  try {
    device = await WgpuSidecar.open();
  } on DeviceUnavailableException catch (refused) {
    print('no sidecar here: ${refused.message}');
    return;
  }
  final kernels = ComputeKernel.parseAll(_kernels);
  final library = await device.loadShaders(
    kernelBundle('pacing', kernels).encode(),
  );
  final step = library['Step']!;
  final damp = library['Damp']!;
  final stepPipeline = device.createComputePipeline(step);
  final dampPipeline = device.createComputePipeline(damp);
  for (final particles in const <int>[4096, 65536]) {
    final bytes = particles * 32;
    final state = device.createBuffer(
      BufferDescriptor(
        lengthInBytes: bytes,
        usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
      ),
    );
    final params = device.createBuffer(
      const BufferDescriptor(
        lengthInBytes: 16,
        usage: BufferUsage.standardStorage,
      ),
    );
    final groups = (particles + 63) ~/ 64;
    final values = ByteData(16)
      ..setFloat32(0, 1 / 60, Endian.little)
      ..setFloat32(4, -9.8, Endian.little)
      ..setFloat32(12, 0.5, Endian.little);
    Future<({double held, double frame})> frame() async {
      final watch = Stopwatch()..start();
      device.writeBuffer(params, 0, values);
      device.beginComputePass(label: 'pacing')
        ..bindPipeline(stepPipeline)
        ..bindStorageBuffer(step, 'particles', state)
        ..bindStorageBuffer(step, 'params', params)
        ..dispatch(groups)
        ..bindPipeline(dampPipeline)
        ..bindStorageBuffer(damp, 'particles', state)
        ..dispatch(groups)
        ..submit();
      final read = device.readBuffer(state);
      final held = watch.elapsedMicroseconds / 1000;
      await read;
      return (held: held, frame: watch.elapsedMicroseconds / 1000);
    }

    for (var i = 0; i < 30; i++) {
      await frame();
    }
    const frames = 300;
    var held = 0.0;
    var whole = 0.0;
    for (var i = 0; i < frames; i++) {
      final f = await frame();
      held += f.held;
      whole += f.frame;
    }
    print(
      '$particles particles (${bytes ~/ 1024} KiB read back): '
      'held ${(held / frames).toStringAsFixed(3)} ms, '
      'frame ${(whole / frames).toStringAsFixed(3)} ms',
    );
    state.dispose();
    params.dispose();
  }
  device.dispose();
}
