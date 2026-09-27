/// The engine's compute stages, in Dart — `H6`.
library;

import 'dart:typed_data';

import 'cpu_shader_stage.dart';

/// `prefix_sum.comp`: an inclusive prefix sum over 1024 unsigned integers in
/// one workgroup of 256 invocations, phase by phase between its barriers.
final class PrefixSumShader implements CpuComputeShader {
  const PrefixSumShader();

  static const int _invocations = 256;

  @override
  (int, int, int) get workgroupSize => (_invocations, 1, 1);

  @override
  void runWorkgroup((int, int, int) group, CpuComputeBindings bindings) {
    final values = bindings.storage['Values'];
    if (values == null) return;
    int read(int i) => values.getUint32(i * 4, Endian.little);
    void write(int i, int v) =>
        values.setUint32(i * 4, v & 0xFFFFFFFF, Endian.little);

    // Before the first barrier: each invocation's four running sums.
    final sums = List<List<int>>.generate(_invocations, (i) {
      final base = i * 4;
      final s0 = read(base);
      final s1 = (s0 + read(base + 1)) & 0xFFFFFFFF;
      final s2 = (s1 + read(base + 2)) & 0xFFFFFFFF;
      final s3 = (s2 + read(base + 3)) & 0xFFFFFFFF;
      return <int>[s0, s1, s2, s3];
    });
    final partial = Uint32List.fromList(<int>[for (final s in sums) s[3]]);

    // The doubling scan: every invocation reads, all of them wait, every
    // invocation writes, all of them wait.
    for (var offset = 1; offset < _invocations; offset <<= 1) {
      final add = Uint32List.fromList(<int>[
        for (var i = 0; i < _invocations; i++)
          i >= offset ? partial[i - offset] : 0,
      ]);
      for (var i = 0; i < _invocations; i++) {
        partial[i] = partial[i] + add[i];
      }
    }

    for (var i = 0; i < _invocations; i++) {
      final before = i == 0 ? 0 : partial[i - 1];
      for (var k = 0; k < 4; k++) {
        write(i * 4 + k, before + sums[i][k]);
      }
    }
  }
}
