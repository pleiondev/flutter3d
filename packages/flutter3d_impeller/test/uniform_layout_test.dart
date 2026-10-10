/// A uniform block's layout is asked of flutter_gpu once, not per draw.
///
///     flutter test test/uniform_layout_test.dart
library;

import 'package:flutter3d_impeller/src/gpu_uniform_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each member is looked up once, however often it is asked', () {
    // Mutation: `offsetOf` calling the lookup every time, as the encoder
    // did per member per draw — the count reads three.
    final asked = <String>[];
    final layout = GpuUniformLayout(
      slot: Object(),
      sizeInBytes: 192,
      granule: 256,
      offsetLookup: (String member) {
        asked.add(member);
        return member == 'model' ? 64 : null;
      },
    );
    for (var draw = 0; draw < 3; draw++) {
      expect(layout.offsetOf('model'), 64);
      expect(layout.offsetOf('missing'), isNull);
    }
    expect(asked, <String>['model', 'missing']);
  });

  test('a block is written at its size rounded to the granule', () {
    // So `emplace` takes the scratch as it is and makes no rounded copy.
    final layout = GpuUniformLayout(
      slot: Object(),
      sizeInBytes: 192,
      granule: 256,
      offsetLookup: (String member) => null,
    );
    expect(layout.emplacedSize, 256);
    expect(layout.sizeInBytes, 192);
  });
}
