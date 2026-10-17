/// `GpuRenderBackend.open` in the shape every backend opens in: asynchronous,
/// and given the size of the surface.
///
///     flutter test test/open_test.dart
///
/// The device itself needs Impeller, which `flutter test` does not run, so
/// this holds what `open` decides before it reaches flutter_gpu.
library;

import 'package:flutter3d_impeller/flutter3d_impeller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a size that is not a surface is refused before the bundle loads', () {
    // Mutation: the size check taken out of `open` — the call goes on to
    // load the bundle, and fails there, on flutter_gpu's terms, naming no
    // size at all.
    expect(
      () => GpuRenderBackend.open(width: 0, height: 720),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => '${e.message}',
          'message',
          contains('0x720'),
        ),
      ),
    );
  });
}
