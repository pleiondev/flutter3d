/// The bytes a backend fills a uniform block in before handing them to its
/// API, kept rather than made per draw. Exported by
/// `package:flutter3d_hardware/backend.dart`.
library;

import 'dart:typed_data';

/// One reusable, zeroed buffer per block size, for a backend's
/// `bindUniformBlock`.
///
/// **Why it exists: a draw allocated every block it bound.** Each backend
/// made a fresh `Float32List` (and Impeller a second, rounded copy) for every
/// uniform block of every draw: six to ten blocks a mesh a view, the shadow
/// passes included, and four kilobytes for a skinned mesh's joints. All of
/// it was garbage the moment the API had copied it, which every API here
/// does at the call — WebGL2's `bufferData`, WebGPU's `queue.writeBuffer`,
/// flutter_gpu's `HostBuffer.emplace`. So one buffer per size serves every
/// block of that size, for the life of the device.
///
/// **What a caller promises.** The list [zeroed] answers is valid until the
/// next call for the same size, so it is filled, handed to an API that
/// copies, and forgotten, in that order; a backend that kept it past the
/// copy would see the next draw's values in it.
final class UniformScratch {
  /// An empty set of buffers; each size is made the first time it is asked
  /// for.
  UniformScratch();

  final Map<int, Float32List> _bySize = <int, Float32List>{};

  /// A list of [sizeInBytes] / 4 floats, all zero: the same list every time
  /// this size is asked for, cleared first, so a member the caller does not
  /// write reads zero as it did in a fresh list.
  ///
  /// [sizeInBytes] is a multiple of four, as a uniform block's size is.
  Float32List zeroed(int sizeInBytes) {
    assert(
      sizeInBytes >= 0 && sizeInBytes % 4 == 0,
      'a uniform block is a whole number of floats, not $sizeInBytes bytes',
    );
    final list = _bySize[sizeInBytes] ??= Float32List(sizeInBytes ~/ 4);
    return list..fillRange(0, list.length, 0);
  }

  /// How many sizes have a buffer: what this holds, for a debugger.
  int get sizes => _bySize.length;
}
