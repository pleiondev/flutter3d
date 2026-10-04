/// The hand-written bindings agree with the header — P9.
///
///     dart test test/bindings_test.dart
///
/// The bindings are written by hand, so nothing but this keeps them and
/// `csrc/include/f3d_physics.h` — and the GPU's, `csrc/gpu/f3d_gpu.h` —
/// saying the same thing.
library;

import 'dart:io';

import 'package:flutter3d_physics_native/src/bindings.dart' as c;
import 'package:flutter3d_physics_native/src/gpu_bindings.dart' as g;
import 'package:test/test.dart';

void main() {
  final header = File('csrc/include/f3d_physics.h').readAsStringSync();

  int define(String name) {
    final match = RegExp('#define $name (\\d+)u').firstMatch(header);
    if (match == null) fail('the header defines no $name');
    return int.parse(match.group(1)!);
  }

  test('the ABI version is the header\'s and the library\'s', () {
    // Mutation: bump F3D_ABI_VERSION in the header and not here.
    expect(c.abiVersion, define('F3D_ABI_VERSION'));
    expect(c.f3d_abi_version(), c.abiVersion);
  });

  test('a transform is as many floats as the header says', () {
    expect(c.transformFloats, define('F3D_TRANSFORM_FLOATS'));
  });

  test('the body types are the header\'s numbers', () {
    expect(header, contains('F3D_BODY_DYNAMIC = ${c.BodyType.dynamic},'));
    expect(header, contains('F3D_BODY_FIXED = ${c.BodyType.fixed},'));
  });

  test('every function the header exports is bound', () {
    // A function added to the header and forgotten here is caught before
    // anybody looks for it.
    final declared = RegExp(
      r'F3D_API [^;(]*?\b(f3d_\w+)\(',
    ).allMatches(header).map((m) => m.group(1)!).toSet();
    final bound = RegExp(r'external \S+ (f3d_\w+)\(')
        .allMatches(File('lib/src/bindings.dart').readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();
    expect(declared, isNotEmpty);
    expect(bound, declared);
  });

  test('particles, debris and cloth are as many floats as the header says', () {
    expect(c.particleFloats, define('F3D_PARTICLE_FLOATS'));
    expect(c.debrisInputFloats, define('F3D_DEBRIS_INPUT_FLOATS'));
    expect(c.debrisFloats, define('F3D_DEBRIS_FLOATS'));
    expect(c.debrisStaticFloats, define('F3D_DEBRIS_STATIC_FLOATS'));
    expect(c.debrisMaxStatics, define('F3D_DEBRIS_MAX_STATICS'));
    expect(c.clothFloats, define('F3D_CLOTH_FLOATS'));
    expect(c.clothMaxBalls, define('F3D_CLOTH_MAX_BALLS'));
  });

  test('the GPU library\'s header and bindings agree', () {
    final gpu = File('csrc/gpu/f3d_gpu.h').readAsStringSync();
    final version = RegExp(r'#define F3D_GPU_ABI_VERSION (\d+)u').firstMatch(gpu);
    expect(int.parse(version!.group(1)!), g.gpuAbiVersion);
    final declared = RegExp(
      r'F3D_GPU_API [^;(]*?\b(f3d_\w+)\(',
    ).allMatches(gpu).map((m) => m.group(1)!).toSet();
    final bound = RegExp(r'external \S+ (f3d_\w+)\(')
        .allMatches(File('lib/src/gpu_bindings.dart').readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();
    expect(declared, isNotEmpty);
    expect(bound, declared);
  });
}
