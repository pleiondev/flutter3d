/// The public mesh layout says what the stages read.
///
///     flutter test test/cpu_mesh_layout_test.dart
library;

import 'package:flutter3d_cpu/builtin.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_layout.dart';
import 'package:test/test.dart';

void main() {
  test('CpuMeshLayout is the layout the stages read', () {
    // Mutation: move a varying in `cpu_shaders_layout.dart` and not here. A
    // material compiled onto the stages then reads the wrong slot.
    expect(CpuMeshLayout.texcoord, kTexcoord);
    expect(CpuMeshLayout.color, kColour);
    expect(CpuMeshLayout.varyingWorld, kVWorld);
    expect(CpuMeshLayout.varyingNormal, kVNormal);
    expect(CpuMeshLayout.varyingUv, kVUv);
    expect(CpuMeshLayout.varyingInstance, kVInstance);
    expect(CpuMeshLayout.varyings, kMeshVaryings);
    expect(CpuMeshLayout.maxLights, kMaxLights);
  });
}
