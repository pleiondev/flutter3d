/// General buffers on the software rasteriser: created, written, mapped,
/// read back in the calling turn, copied in transfer passes, bound by range,
/// and read as a dispatch's grid.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

/// Adds one to the first word of `Count` per workgroup.
final class _CountGroups extends CpuComputeShader {
  const _CountGroups();

  @override
  (int, int, int) get workgroupSize => (1, 1, 1);

  @override
  void runWorkgroup((int, int, int) group, CpuComputeBindings bindings) {
    final count = bindings.storage['Count']!;
    count.setUint32(0, count.getUint32(0, Endian.little) + 1, Endian.little);
  }
}

CpuDevice _device() => CpuDevice(
  width: 1,
  height: 1,
  shaders: CpuShaderLibrary(<String, CpuStage>{
    'CountGroups': const CpuStage.compute(_CountGroups()),
  }),
);

ByteData _words(List<int> values) =>
    ByteData.sublistView(Uint32List.fromList(values));

void main() {
  test('a created buffer holds its contents, and a write lands at its '
      'offset', () async {
    // Mutation: `writeBuffer` ignoring the offset, or `readBufferSync`
    // ignoring the range.
    final d = _device();
    final buffer = d.createBuffer(
      BufferDescriptor(
        lengthInBytes: 12,
        usage: BufferUsage.copyDestination | BufferUsage.hostReadable,
      ),
      contents: _words(<int>[1, 2, 3]),
    );
    d.writeBuffer(buffer, 4, _words(<int>[9]));
    final whole = await d.readBuffer(buffer);
    expect(Uint32List.sublistView(whole), <int>[1, 9, 3]);
    final tail = d.readBufferSync(buffer, offsetInBytes: 8);
    expect(Uint32List.sublistView(tail), <int>[3]);
  });

  test(
    'a mapping is the buffer, and no pass may use it until unmapped',
    () async {
      // Mutation: `mapBuffer` handing out a copy that never reaches the
      // buffer, or `checkUnmapped` not consulted by a readback.
      final d = _device();
      final buffer = d.createBuffer(
        BufferDescriptor(
          lengthInBytes: 8,
          usage: BufferUsage.hostWritable | BufferUsage.hostReadable,
        ),
      );
      final mapped = await d.mapBuffer(buffer, MapMode.write);
      mapped.bytes.setUint32(4, 7, Endian.little);
      expect(() => d.readBufferSync(buffer), throwsStateError);
      mapped.unmap();
      expect(d.readBufferSync(buffer).getUint32(4, Endian.little), 7);
      expect(mapped.unmap, throwsStateError);
    },
  );

  test('copies run when the transfer pass is submitted, in order', () {
    // Mutation: copies run when recorded, so the destination changes
    // before submit.
    final d = _device();
    final source = d.createBuffer(
      const BufferDescriptor(lengthInBytes: 8, usage: BufferUsage.copySource),
      contents: _words(<int>[5, 6]),
    );
    final destination = d.createBuffer(
      BufferDescriptor(
        lengthInBytes: 8,
        usage: BufferUsage.copyDestination | BufferUsage.hostReadable,
      ),
      contents: _words(<int>[1, 1]),
    );
    final pass = d.beginTransferPass()
      ..clearBuffer(destination)
      ..copyBufferToBuffer(source, 4, destination, 0, 4);
    expect(Uint32List.sublistView(d.readBufferSync(destination)), <int>[1, 1]);
    pass.submit();
    expect(Uint32List.sublistView(d.readBufferSync(destination)), <int>[6, 0]);
    expect(
      () => pass.clearBuffer(destination),
      throwsStateError,
      reason: 'a copy recorded after submit',
    );
  });

  test('an indirect dispatch runs the grid its buffer holds, and a range '
      'binding hands the stage those bytes', () async {
    // Mutation: `dispatchIndirect` reading the words in the wrong order or
    // only the first; or `bindStorageBuffer` binding the whole buffer and
    // ignoring the offset.
    final d = _device();
    final stage = d.shaders['CountGroups']!;
    final count = d.createBuffer(
      BufferDescriptor(
        lengthInBytes: 8,
        usage: BufferUsage.storage | BufferUsage.hostReadable,
      ),
    );
    final grid = d.createBuffer(
      const BufferDescriptor(lengthInBytes: 12, usage: BufferUsage.indirect),
      contents: dispatchIndirectArguments(2, 3),
    );
    final stats = d.createQuerySet(QueryType.pipelineStatistics, 1);
    d.beginComputePass()
      ..bindPipeline(d.createComputePipeline(stage))
      ..bindStorageBuffer(stage, 'Count', count, offsetInBytes: 4)
      ..beginPipelineStatisticsQuery(stats, 0)
      ..dispatchIndirect(grid)
      ..endPipelineStatisticsQuery()
      ..submit();
    expect(Uint32List.sublistView(await d.readBuffer(count)), <int>[0, 6]);
    expect((await d.readQueryResults(stats)).last, 6);
    expect(
      () => d.beginComputePass().bindStorageBuffer(
        stage,
        'Count',
        count,
        offsetInBytes: 4,
        sizeInBytes: 8,
      ),
      throwsRangeError,
    );
  });

  test('an indirect buffer must have been made for it', () {
    // Mutation: `dispatchIndirect` reading any buffer it is handed.
    final d = _device();
    final plain = d.createBuffer(
      const BufferDescriptor(lengthInBytes: 12, usage: BufferUsage.storage),
    );
    expect(
      () => d.beginComputePass().dispatchIndirect(plain),
      throwsArgumentError,
    );
  });
}
