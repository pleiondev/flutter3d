/// The same puff on the VM and compiled for a browser.
///
///     dart test test/six_way_puff_platforms_test.dart -p vm,chrome
///
/// The hash under the noise once relied on 64-bit integers: compiled for the
/// web its products lost their low bits as doubles, a browser baked another
/// puff, and `smoke-six-way` stood 2% apart from the native backends. The
/// source file alone, since the package's library reaches `dart:ffi`.
library;

import 'package:flutter3d_build/src/six_way_bake.dart';
import 'package:test/test.dart';

void main() {
  test('the puff is the same field on every platform', () {
    final field = smokePuff(seed: 3);
    expect(field(0.1, 0.2, -0.3, 0.0), closeTo(0.31749390301320235, 1e-12));
    expect(field(-0.45, 0.05, 0.2, 0.5), closeTo(0.46599636846111026, 1e-12));
    expect(field(0.3, -0.35, 0.1, 0.9), closeTo(0.3780850639076149, 1e-12));
    expect(field(0.0, 0.0, 0.0, 0.25), closeTo(0.85, 1e-12));
  });
}
