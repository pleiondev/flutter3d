/// Compute, where a device says it has it — `H6`.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '../flutter3d_conformance.dart';

const int _count = 1024;

/// `PrefixSum` over `0, 1, …, 1023`, dispatched once and read back.
///
/// Every output is `i·(i+1)/2`, which the check knows without running a
/// scan of its own, and every output depends on every input before it: an
/// invocation run out of order, a barrier that did not hold, a buffer read
/// before it was written or written back somewhere else each leave a wrong
/// number, and the message names the first one.
Future<void> checkPrefixSum(GraphicsDevice device) async {
  if (!device.supportsCompute) {
    throw const ConformanceDeclined(
      'this device answers false to supportsCompute, which is a legitimate '
      'answer: compute is optional, and FieldPass is the path every backend '
      'has',
    );
  }
  final stage = device.shaders['PrefixSum'];
  require(stage != null, 'the PrefixSum compute stage is missing');

  final input = ByteData(_count * 4);
  for (var i = 0; i < _count; i++) {
    input.setUint32(i * 4, i, Endian.little);
  }
  final buffer = device.createStorageBuffer(input, hostReadable: true);
  device.beginComputePass(label: 'prefix sum')
    ..bindPipeline(device.createComputePipeline(stage!))
    ..bindStorageBuffer(stage, 'Values', buffer)
    ..dispatch(1)
    ..submit();

  final out = await device.readBuffer(buffer);
  device.releaseStorageBuffer(buffer);
  require(
    out.lengthInBytes == _count * 4,
    'the buffer came back ${out.lengthInBytes} bytes long, not ${_count * 4}',
  );
  for (var i = 0; i < _count; i++) {
    final got = out.getUint32(i * 4, Endian.little);
    final want = i * (i + 1) ~/ 2;
    require(
      got == want,
      'element $i of the prefix sum is $got where $want belongs. The first '
      'wrong element says where it broke: inside one invocation\'s four '
      '(i % 4 != 0), across invocations (a barrier or the shared scan), or '
      'everywhere (the buffer was not written back, or not bound).',
    );
  }
}

/// Run these where a device says it computes. Each declines otherwise.
List<ConformanceCheck> get computeChecks => <ConformanceCheck>[
  (name: 'a compute pass scans a buffer in place', run: checkPrefixSum),
];
