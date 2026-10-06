/// The hand-written bindings agree with the header — P9.
///
///     dart test test/bindings_test.dart
///
/// The bindings are written by hand, so nothing but this keeps them and
/// `csrc/include/f3d_physics.h` — and the GPU's, `csrc/gpu/f3d_gpu.h` —
/// saying the same thing.
library;

import 'dart:io';

import 'package:flutter3d_physics_native/src/core/core.dart' as c;
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

  test('the generated calls and layouts are the header\'s', () {
    // A function or a field added to the header and not generated is caught
    // before anybody looks for it.
    final check = Process.runSync('dart', <String>[
      'run',
      'tool/gen_core.dart',
      '--check',
    ]);
    expect(check.exitCode, 0, reason: '${check.stdout}${check.stderr}');
    final declared = RegExp(
      r'F3D_API [^;(]*?\b(f3d_\w+)\(',
    ).allMatches(header).map((m) => m.group(1)!).toSet();
    for (final file in <String>[
      'lib/src/core/calls_native.g.dart',
      'lib/src/core/calls_web.g.dart',
    ]) {
      final bound = RegExp(r'^\S+ (f3d_\w+)\(', multiLine: true)
          .allMatches(File(file).readAsStringSync())
          .map((m) => m.group(1)!)
          .toSet();
      expect(bound, declared, reason: file);
    }
  });

  test('the structs are laid out as the C compiler lays them out', () {
    // The layouts are worked out in Dart for the float build; this asks
    // cc for offsetof and sizeof of every field of every struct.
    final layouts = RegExp(
      r'abstract final class (F3d\w+)Layout \{(.*?)\}',
      dotAll: true,
    ).allMatches(File('lib/src/core/layout.g.dart').readAsStringSync());
    final expected = <String, int>{};
    final source = StringBuffer()
      ..write('#include <stddef.h>\n#include <stdio.h>\n')
      ..write('#include "f3d_physics.h"\nint main(void) {\n');
    for (final l in layouts) {
      final type = l.group(1)!;
      for (final f in RegExp(
        r'static const int (\w+) = (\d+);',
      ).allMatches(l.group(2)!)) {
        final name = f.group(1)!;
        expected['$type.$name'] = int.parse(f.group(2)!);
        final field = name.replaceAllMapped(
          RegExp('[A-Z]'),
          (m) => '_${m[0]!.toLowerCase()}',
        );
        final what = name == 'size'
            ? 'sizeof($type)'
            : 'offsetof($type, $field)';
        source.write('  printf("$type.$name %zu\\n", $what);\n');
      }
    }
    source.write('  return 0;\n}\n');
    final dir = Directory.systemTemp.createTempSync('f3d_layout');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/layout.c').writeAsStringSync(source.toString());
    final built = Process.runSync('cc', <String>[
      '-std=c11',
      '-Icsrc/include',
      '${dir.path}/layout.c',
      '-o',
      '${dir.path}/layout',
    ]);
    expect(built.exitCode, 0, reason: '${built.stderr}');
    final ran = Process.runSync('${dir.path}/layout', const <String>[]);
    final actual = <String, int>{
      for (final line in '${ran.stdout}'.trim().split('\n'))
        line.split(' ')[0]: int.parse(line.split(' ')[1]),
    };
    expect(expected, isNotEmpty);
    expect(actual, expected);
  }, testOn: 'mac-os || linux');

  test(
    'particles, debris, cloth and fluid are as many floats as the header says',
    () {
      expect(c.particleFloats, define('F3D_PARTICLE_FLOATS'));
      expect(c.debrisInputFloats, define('F3D_DEBRIS_INPUT_FLOATS'));
      expect(c.debrisFloats, define('F3D_DEBRIS_FLOATS'));
      expect(c.debrisStaticFloats, define('F3D_DEBRIS_STATIC_FLOATS'));
      expect(c.debrisMaxStatics, define('F3D_DEBRIS_MAX_STATICS'));
      expect(c.clothFloats, define('F3D_CLOTH_FLOATS'));
      expect(c.clothMaxBalls, define('F3D_CLOTH_MAX_BALLS'));
      expect(c.clothStateFloats, define('F3D_CLOTH_STATE_FLOATS'));
      expect(c.ClothObstacleKind.ball, define('F3D_CLOTH_BALL'));
      expect(c.ClothObstacleKind.capsule, define('F3D_CLOTH_CAPSULE'));
      expect(c.ClothObstacleKind.convex, define('F3D_CLOTH_CONVEX'));
      expect(c.ClothObstacleKind.ground, define('F3D_CLOTH_GROUND'));
      expect(c.fluidInputFloats, define('F3D_FLUID_INPUT_FLOATS'));
      expect(c.fluidFloats, define('F3D_FLUID_FLOATS'));
      expect(c.liquidParticleFloats, define('F3D_LIQUID_PARTICLE_FLOATS'));
      expect(c.liquidParcelFloats, define('F3D_LIQUID_PARCEL_FLOATS'));
      expect(c.liquidModeFloats, define('F3D_LIQUID_MODE_FLOATS'));
      expect(c.LiquidWallKind.plane, define('F3D_LIQUID_PLANE'));
      expect(c.LiquidWallKind.inside, define('F3D_LIQUID_INSIDE'));
      expect(c.LiquidWallKind.outside, define('F3D_LIQUID_OUTSIDE'));
      expect(c.liquidPipeFloats, define('F3D_LIQUID_PIPE_FLOATS'));
      expect(c.liquidBodyFloats, define('F3D_LIQUID_BODY_FLOATS'));
      expect(c.liquidPushFloats, define('F3D_LIQUID_PUSH_FLOATS'));
      expect(c.LiquidFloatShape.sphere, define('F3D_LIQUID_SPHERE'));
      expect(c.LiquidFloatShape.box, define('F3D_LIQUID_BOX'));
      expect(c.LiquidFloatShape.capsule, define('F3D_LIQUID_CAPSULE'));
      expect(c.LiquidFloatShape.other, define('F3D_LIQUID_OTHER'));
    },
  );

  test('the GPU library\'s header and bindings agree', () {
    final gpu = File('csrc/gpu/f3d_gpu.h').readAsStringSync();
    final version = RegExp(
      r'#define F3D_GPU_ABI_VERSION (\d+)u',
    ).firstMatch(gpu);
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
