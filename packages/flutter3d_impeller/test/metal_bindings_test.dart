/// Every resource a compiled stage reports has a Metal slot.
///
///     flutter test test/metal_bindings_test.dart
///
/// **Reflection reports what the GLSL declared, not what the Metal function
/// kept.** A uniform block or a sampler a stage never reads is dropped from
/// the MSL and still listed in the reflection, with its Metal index left at
/// 0xFFFFFFFF. Binding one is a crash inside `setFragmentBuffer:offset:atIndex:`
/// with no Dart stack under it. Vulkan takes the same bind without complaint,
/// so a scene can draw on Android and die on the first frame on a Mac and an
/// iPhone. 0.7.0 shipped that way: `unlit.frag` declared the light list, the
/// renderer bound it to every draw, and nothing that ran here ran Metal.
///
/// This compiles every stage the bundle manifest names with the real
/// `impellerc`, for Metal, and holds the reflection to it. It needs no GPU
/// and no Xcode, only the compiler the Flutter SDK already carries.
///
/// Mutation: take `#define F3D_NO_LIGHT_LIST` out of `unlit.frag`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_impeller/src/shader_bundle_build.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a Metal index reads when the compiler assigned none.
const int _unassigned = 0xFFFFFFFF;

/// Dropped on purpose, and never bound: `LightingModel.lambert` says
/// `usesMetallicRoughnessMap: false`, so the renderer does not ask for it.
const Set<String> _knownUnbound = <String>{
  'Lambert/metallic_roughness_texture',
};

String? _impellerc() {
  final root = flutterSdkRootFrom(Platform.resolvedExecutable);
  for (final platform in const <String>[
    'darwin-x64',
    'darwin-arm64',
    'linux-x64',
    'linux-arm64',
    'windows-x64',
    'windows-arm64',
  ]) {
    final path = '$root/bin/cache/artifacts/engine/$platform/$impellercName';
    if (File(path).existsSync()) return path;
  }
  return null;
}

void main() {
  test('no stage reports a resource Metal has no slot for', () {
    final compiler = _impellerc();
    expect(compiler, isNotNull, reason: 'no impellerc in the Flutter SDK');
    final shaders = Directory('../flutter3d_shaders/shaders').absolute.path;
    final shaderLib = File(compiler!).parent.uri.resolve('shader_lib').path;
    final manifest =
        jsonDecode(
              File('$shaders/flutter3d.shaderbundle.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final scratch = Directory.systemTemp.createTempSync('f3d_metal_');
    addTearDown(() => scratch.deleteSync(recursive: true));

    final unbound = <String>[];
    for (final MapEntry(key: name, value: entry) in manifest.entries) {
      final stage = entry! as Map<String, Object?>;
      final file = (stage['file']! as String).replaceFirst('shaders/', '');
      final reflection = '${scratch.path}/$name.json';
      final result = Process.runSync(compiler, <String>[
        '--metal-desktop',
        '--input=$shaders/$file',
        '--sl=${scratch.path}/$name.metal',
        '--spirv=${scratch.path}/$name.spv',
        '--reflection-json=$reflection',
        '--include=$shaderLib',
        '--include=$shaders',
        '--include=$shaders/lib',
        '--input-type=${stage['type'] == 'vertex' ? 'vert' : 'frag'}',
      ]);
      expect(result.exitCode, 0, reason: '$name: ${result.stderr}');

      final reflected =
          jsonDecode(File(reflection).readAsStringSync())
              as Map<String, Object?>;
      for (final kind in const <String>['buffers', 'sampled_images']) {
        for (final resource in (reflected[kind] as List<Object?>? ?? [])) {
          final r = resource! as Map<String, Object?>;
          final key = '$name/${r['name']}';
          if (r['ext_res_0'] == _unassigned && !_knownUnbound.contains(key)) {
            unbound.add(key);
          }
        }
      }
    }

    expect(
      unbound,
      isEmpty,
      reason:
          'declared, dropped from the Metal function, and still reflected. '
          'Binding any of these crashes Metal inside the driver. Guard the '
          'declaration with the stage\'s F3D_NO_* define, or read it.',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
