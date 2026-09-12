/// `GraphicsDevice.overwriteGeometry`, on the one backend a plain `flutter
/// test` can check content against without a GPU or a browser — `pro-eng-01`.
///
///     flutter test test/geometry_overwrite_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

CpuDevice _device() =>
    CpuDevice(width: 4, height: 4, shaders: CpuShaderLibrary(builtinCpuShaders()));

Uint8List _bytesHeldBy(GeometryBuffer buffer) {
  final backend = buffer.backend as ({ByteData bytes, GeometryUsage usage});
  return backend.bytes.buffer.asUint8List(
    backend.bytes.offsetInBytes,
    backend.bytes.lengthInBytes,
  );
}

void main() {
  test('a write in the middle changes only the bytes it named', () {
    final device = _device();
    final original = Uint8List.fromList(List<int>.generate(16, (i) => i));
    final buffer = device.uploadGeometry(
      ByteData.sublistView(original),
      GeometryUsage.vertices,
    );

    device.overwriteGeometry(
      buffer,
      4,
      ByteData.sublistView(Uint8List.fromList(<int>[99, 98, 97, 96])),
    );

    expect(_bytesHeldBy(buffer), <int>[
      0, 1, 2, 3, // untouched
      99, 98, 97, 96, // overwritten
      8, 9, 10, 11, 12, 13, 14, 15, // untouched
    ]);
  });

  test('uploadGeometry made its own copy, so the caller\'s array is untouched', () {
    // Mutation: pass `bytes` straight through instead of copying it in
    // `uploadGeometry`. This test would still pass, because it only reads
    // back through the buffer — the point belongs to the next one, which
    // reads `original` itself.
    final device = _device();
    final original = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final buffer = device.uploadGeometry(
      ByteData.sublistView(original),
      GeometryUsage.vertices,
    );
    device.overwriteGeometry(
      buffer,
      0,
      ByteData.sublistView(Uint8List.fromList(<int>[9, 9, 9, 9])),
    );
    expect(original, <int>[1, 2, 3, 4]);
  });

  test('a write past the end is refused rather than silently truncated', () {
    final device = _device();
    final buffer = device.uploadGeometry(
      ByteData.sublistView(Uint8List(8)),
      GeometryUsage.vertices,
    );
    expect(
      () => device.overwriteGeometry(
        buffer,
        4,
        ByteData.sublistView(Uint8List(8)),
      ),
      throwsArgumentError,
    );
  });

  test('a write past the end of a slice is refused even though it would '
      'still fit in the buffer underneath it', () {
    // Mutation: drop the explicit bound check and rely on `asUint8List`'s own
    // range check instead. That check answers a `RangeError` — a subtype of
    // `ArgumentError`, so the test above still passes without it — but only
    // guards the *backing* buffer, not a slice's own declared length, so a
    // write like this one, which stays inside the backing 16 bytes but not
    // inside the 4-byte slice, would go through silently and corrupt the
    // bytes just past the slice instead of being refused.
    final device = _device();
    final whole = device.uploadGeometry(
      ByteData.sublistView(Uint8List(16)),
      GeometryUsage.vertices,
    );
    final slice = whole.slice(offset: 0, length: 4);
    expect(
      () => device.overwriteGeometry(
        slice,
        0,
        ByteData.sublistView(Uint8List(8)),
      ),
      throwsArgumentError,
    );
  });

  test('a negative offset is refused the same way', () {
    final device = _device();
    final buffer = device.uploadGeometry(
      ByteData.sublistView(Uint8List(8)),
      GeometryUsage.vertices,
    );
    expect(
      () => device.overwriteGeometry(
        buffer,
        -1,
        ByteData.sublistView(Uint8List(4)),
      ),
      throwsArgumentError,
    );
  });

  test('a slice carries its own offset into the write, not just its length', () {
    // Mutation: drop `target.offsetInBytes +` from the absolute-offset sum.
    // Nothing above this line ever uploads through a slice, so a mutation
    // there would sail through every other test in this file — this is the
    // one that actually exercises `GeometryBuffer.slice`'s own offset.
    final device = _device();
    final original = Uint8List.fromList(List<int>.generate(16, (i) => i));
    final whole = device.uploadGeometry(
      ByteData.sublistView(original),
      GeometryUsage.vertices,
    );
    final second = whole.slice(offset: 8, length: 8);

    device.overwriteGeometry(
      second,
      4,
      ByteData.sublistView(Uint8List.fromList(<int>[9, 9])),
    );

    expect(_bytesHeldBy(whole), <int>[
      0, 1, 2, 3, 4, 5, 6, 7, // untouched: before the slice
      8, 9, 10, 11, // untouched: inside the slice, before its own offset
      9, 9, // overwritten: slice offset 8 + write offset 4 = byte 12
      14, 15, // untouched: after the write
    ]);
  });
}
