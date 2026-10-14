// The kernel language on the CPU placement: a bundle's kernel section loads
// as compute stages, reloads under the handles already handed out, and a
// frame's placement rule lands on this device where nothing else computes.
import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_shaders/kernel.dart';
import 'package:test/test.dart';

const String _double = '''
compute Twice {
  workgroup 4;
  buffer values: u32[] read_write;
  kernel {
    let i = id.x;
    if i >= len(values) { return; }
    values[i] = values[i] * 2u;
  }
}
''';

CpuDevice _device() => cpuComputeDevice();

ByteData _bundle(String source) =>
    kernelBundle('kernels', ComputeKernel.parseAll(source)).encode();

Future<List<int>> _run(CpuDevice device, ShaderHandle stage, int n) async {
  final contents = ByteData(n * 4);
  for (var i = 0; i < n; i++) {
    contents.setUint32(i * 4, i + 1, Endian.little);
  }
  final buffer = device.createBuffer(
    BufferDescriptor(
      lengthInBytes: n * 4,
      usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
    ),
    contents: contents,
  );
  device.beginComputePass()
    ..bindPipeline(device.createComputePipeline(stage))
    ..bindStorageBuffer(stage, 'values', buffer)
    ..dispatch(2)
    ..submit();
  final out = await device.readBuffer(buffer);
  return <int>[for (var i = 0; i < n; i++) out.getUint32(i * 4, Endian.little)];
}

void main() {
  test('a kernel in a bundle runs as a compute stage', () async {
    // Mutation: leave kernels out of the loaded library, and the bundle is
    // refused for a stage the rasteriser has no Dart for.
    final device = _device();
    final library = await device.loadShaders(_bundle(_double));
    final stage = library['Twice']!;
    expect(await _run(device, stage, 8), <int>[2, 4, 6, 8, 10, 12, 14, 16]);
  });

  test('a binding the kernel does not declare answers false', () async {
    // Mutation: bind anything by name, and a typo binds nothing silently.
    final device = _device();
    final stage = (await device.loadShaders(_bundle(_double)))['Twice']!;
    final pass = device.beginComputePass()
      ..bindPipeline(device.createComputePipeline(stage));
    final buffer = device.createBuffer(
      const BufferDescriptor(
        lengthInBytes: 16,
        usage: BufferUsage.standardStorage,
      ),
    );
    expect(pass.bindStorageBuffer(stage, 'value', buffer), isFalse);
    expect(pass.bindStorageBuffer(stage, 'values', buffer), isTrue);
  });

  test('a reload runs the new kernel under the handle handed out', () async {
    // Mutation: replace the stage instead of what it runs, and a pipeline
    // made before the reload runs the old kernel.
    final device = _device();
    final library = await device.loadShaders(_bundle(_double));
    final stage = library['Twice']!;
    library.refresh(_bundle(_double.replaceAll('* 2u', '* 3u')));
    expect(library['Twice'], same(stage));
    expect(await _run(device, stage, 4), <int>[3, 6, 9, 12]);
  });

  test('a kernel that does not read refuses the bundle by name', () async {
    // Mutation: swallow the parse error, and the bundle loads with a stage
    // that answers nothing.
    final device = _device();
    final broken = ShaderBundle(
      name: 'broken',
      sdk: '',
      stages: const <ShaderBundleStage>[
        ShaderBundleStage('Twice', fragment: false),
      ],
      sections: <String, ByteData>{
        ShaderBundle.kernelSection: encodeKernelSection(<String, String>{
          'Twice': _double.replaceAll('u32[] read_write', 'u32[] read'),
        }),
      },
    ).encode();
    await expectLater(
      device.loadShaders(broken),
      throwsA(
        isA<ShaderBundleException>()
            .having((e) => e.name, 'name', 'broken')
            .having((e) => e.reason, 'reason', contains('"Twice"'))
            .having((e) => e.reason, 'reason', contains('read only')),
      ),
    );
  });

  group('placement', () {
    test('a device without compute places a step on the CPU', () {
      // Mutation: try the drawing device whatever it says, and a step is
      // encoded on a device that refuses its first call.
      final cpu = _device();
      final executor = ComputeExecutors(
        device: FakeBackend(),
        cpu: cpu,
      ).place(step: 'particles');
      expect(executor.placement, ComputePlacement.cpu);
      expect(executor.device, same(cpu));
    });

    test('a device that computes runs the step itself', () {
      // Mutation: prefer the CPU, and a frame on WebGPU copies every
      // buffer through host memory for nothing.
      final drawing = _device();
      final executor = ComputeExecutors(
        device: drawing,
        cpu: _device(),
      ).place(step: 'particles');
      expect(executor.placement, ComputePlacement.device);
      expect(executor.device, same(drawing));
    });

    test('a kernel refused on one executor moves to the next', () {
      // Mutation: stop at the first executor with compute, and a kernel the
      // device cannot load leaves the step with nowhere to run.
      final drawing = _device();
      final cpu = _device();
      final executors = ComputeExecutors(device: drawing, cpu: cpu);
      expect(
        executors
            .place(
              step: 'blur',
              accepts: (ComputeExecutor e) => !identical(e.device, drawing),
            )
            .device,
        same(cpu),
      );
      expect(
        () => executors.place(step: 'blur', accepts: (_) => false),
        throwsA(
          isA<ComputePlacementException>().having(
            (e) => e.reason,
            'reason',
            ComputeRefusalReason.kernelRefused,
          ),
        ),
      );
    });

    test('the CPU backend registers its compute device', () async {
      final registry = DeviceRegistry<Object>();
      final registration = registerCpuBackend(registry);
      final executors = await registry.computeExecutors(FakeBackend());
      expect(executors.cpu, isA<CpuDevice>());
      registration.cancel();
      expect((await registry.computeExecutors(FakeBackend())).cpu, isNull);
    });
  });
}
