/// A field stepped by full-screen passes — `H5`.
///
///     flutter test test/field_pass_test.dart
///
/// `FieldPass` is two targets and a swap, which is little enough code to get
/// wrong in exactly two ways: stepping from the target just written instead of
/// the other one, and forgetting to swap, so every step starts from the same
/// place. A decay whose answer is known after any number of steps catches
/// both.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('n steps of a decay land where the closed form says', () async {
    // Mutation: drop the swap at the end of `step`. Every step then reads the
    // start again, and three steps answer what one does.
    final device = CpuDevice(
      width: 4,
      height: 4,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final field = FieldPass(
      device,
      const RenderTargetSpec(
        width: 4,
        height: 4,
        format: TextureFormat.r32g32b32a32Float,
      ),
    );
    device
        .beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[
              ColorTarget(
                texture: field.current,
                clearValue: Vector4(2.0, 2.0, 2.0, 2.0),
              ),
            ],
          ),
        )
        .submit();

    final kernel = device.shaders['FieldDecay']!;
    for (var i = 0; i < 3; i++) {
      field.step(
        kernel,
        bind: (pass) => pass.bindUniformBlock(
          kernel,
          'FieldDecayInfo',
          <String, Float32List>{
            'params': Float32List.fromList(<double>[0.5, 0.1, 0.0, 0.0]),
          },
        ),
      );
    }
    expect(field.steps, 3);

    final expected =
        2.0 * math.pow(0.5, 3) + 0.1 * (1 - math.pow(0.5, 3)) / 0.5;
    final texel = (field.current.backend as CpuTexture).pixels;
    expect(texel[0], closeTo(expected, 1e-6));
    field.dispose();
  });
}
