/// Fifty programs nobody wrote, drawn here and on the software rasteriser —
/// `H4`, the browser half.
///
///     flutter test --platform chrome test/fuzz_test.dart
///
/// The CPU half holds the software rasteriser to itself, byte for byte. This
/// holds a hardware backend to that rasteriser's picture: the same program,
/// the same seed, and at most [_budget] of the pixels differing by more than
/// eight steps in any channel — where the cross-backend golden tests draw
/// the line, for the same reason, since edge coverage and blend rounding are
/// the driver's own.
@TestOn('browser')
library;

import 'package:flutter3d_conformance/flutter3d_conformance.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/engine_shaders.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart';
import 'package:flutter_test/flutter_test.dart';

/// Measured at 0.85% for the worst of the fifty on a Mac's WebGPU, once the
/// software rasteriser clipped to its viewport and stored eight-bit targets as
/// eight bits — before those two fixes, four of the fifty were 16-26% apart.
const double _budget = 0.02;

void main() {
  test('fifty programs draw what the software rasteriser draws', () async {
    final device = await WebGpuDevice.create(
      width: 32,
      height: 32,
      stages: engineShaders,
    );
    if (device == null) {
      markTestSkipped('this browser has no WebGPU');
      return;
    }
    GraphicsDevice cpu({required int width, required int height}) => CpuDevice(
      width: width,
      height: height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final over = <String>[];
    var worst = 0.0;
    for (var seed = 0; seed < 50; seed++) {
      final difference = await fuzzDifference(
        seed,
        device: ({required int width, required int height}) => device,
        reference: cpu,
      );
      if (difference > worst) worst = difference;
      if (difference > _budget) {
        over.add('seed $seed: ${(difference * 100).toStringAsFixed(1)}%');
      }
    }
    // ignore: avoid_print
    print('webgpu fuzz: worst ${(worst * 100).toStringAsFixed(2)}%');
    expect(over, isEmpty, reason: over.join('\n'));
  });
}
