// Impeller compiles a bundled shader's entry point from its SOURCE FILE STEM —
// `<stem>_<stage>_main` — and ignores the manifest key. The manifest's optional
// `entry_point` field is honoured for HLSL only; for GLSL it is dead.
//
// At run time every bundle's stages are registered into the one Impeller shader
// library the GPU context owns, keyed by (name, stage), and registering a name
// that is already there is skipped rather than rejected. So two packages that
// each ship a `foo.frag` silently share whichever one loaded first: the second
// one's code is never compiled, and nothing warns.
//
// That is the trap the extension model walks into, since every `flutter3d_*`
// package is meant to ship its own bundle. The rule is that an extension
// prefixes its shader FILE NAMES with the package name — renaming the file is
// the only lever, because the manifest key does nothing.
//
// This is the guard. It is device-free: bundles are read off disk.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Names owned by more than one package.
///
/// Pure, and separated from the scan on purpose: the scan over this repository
/// asserts that nothing collides, which is a test that passes just as happily
/// when it has stopped looking. Proving the detector detects needs input that
/// does collide, and that is what the synthetic cases below supply.
Map<String, List<String>> collisionsAmong(Map<String, Set<String>> byPackage) {
  final owner = <String, String>{};
  final collisions = <String, List<String>>{};
  for (final entry in byPackage.entries) {
    for (final name in entry.value) {
      final first = owner[name];
      if (first == null) {
        owner[name] = entry.key;
      } else {
        collisions.putIfAbsent(name, () => <String>[first]).add(entry.key);
      }
    }
  }
  return collisions;
}

final RegExp _entryPoint = RegExp(r'[a-z0-9_]+_(?:vertex|fragment|compute)_main');

/// Entry-point names in a compiled bundle.
///
/// The bundle is a flatbuffer holding, among other things, the Metal source for
/// each stage. Rather than link a flatbuffers reader for one string field, scan
/// the printable runs — the same thing `tool/build_shaders.sh` does with
/// `strings`, and it needs no schema that a Flutter upgrade could move.
Set<String> entryPointsIn(File bundle) {
  final Uint8List bytes = bundle.readAsBytesSync();
  final buffer = StringBuffer();
  for (final byte in bytes) {
    // Printable ASCII forms the runs; anything else terminates one.
    buffer.writeCharCode(byte >= 0x20 && byte < 0x7f ? byte : 0x0a);
  }
  return _entryPoint.allMatches(buffer.toString()).map((m) => m.group(0)!).toSet();
}

/// Every built bundle in the workspace, package name to path.
///
/// Discovered rather than listed, so a new extension is covered the day it
/// arrives instead of the day somebody remembers to add it here. `flutter test`
/// runs from the package root, so `..` is `packages/`.
Map<String, File> _builtBundles() {
  final found = <String, File>{};
  final packages = Directory('..');
  if (!packages.existsSync()) return found;
  for (final entry in packages.listSync()) {
    if (entry is! Directory) continue;
    final shaders = Directory('${entry.path}/assets/shaders');
    if (!shaders.existsSync()) continue;
    for (final file in shaders.listSync()) {
      if (file is File && file.path.endsWith('.shaderbundle')) {
        found[entry.path.split(Platform.pathSeparator).last] = file;
      }
    }
  }
  return found;
}

void main() {
  group('the collision detector', () {
    test('says nothing when every name has one owner', () {
      expect(
        collisionsAmong({
          'flutter3d': {'pbr_fragment_main', 'mesh_vertex_main'},
          'flutter3d_post': {'post_bloom_fragment_main'},
        }),
        isEmpty,
      );
    });

    test('catches two packages shipping the same shader file name', () {
      // Both would ship an `unlit.frag`. Different shaders, one entry point.
      final collisions = collisionsAmong({
        'flutter3d': {'unlit_fragment_main', 'pbr_fragment_main'},
        'flutter3d_post': {'unlit_fragment_main'},
      });
      expect(collisions.keys, equals({'unlit_fragment_main'}));
      expect(
        collisions['unlit_fragment_main'],
        equals(['flutter3d', 'flutter3d_post']),
      );
    });

    test('names every owner when more than two collide', () {
      final collisions = collisionsAmong({
        'a': {'fog_fragment_main'},
        'b': {'fog_fragment_main'},
        'c': {'fog_fragment_main'},
      });
      expect(collisions['fog_fragment_main'], equals(['a', 'b', 'c']));
    });

    test('a name colliding does not implicate its neighbours', () {
      final collisions = collisionsAmong({
        'a': {'shared_fragment_main', 'a_only_fragment_main'},
        'b': {'shared_fragment_main', 'b_only_fragment_main'},
      });
      expect(collisions.keys, equals({'shared_fragment_main'}));
    });
  });

  group('this repository', () {
    test('has built the engine bundle', () {
      // A failure, not a skip. "CI built only one bundle" is one of the traps
      // being guarded, and a guard that skips itself when the thing is missing
      // guards nothing.
      expect(
        _builtBundles().containsKey('flutter3d_gpu'),
        isTrue,
        reason: 'Run packages/flutter3d/tool/build_shaders.sh. The bundle is '
            'gitignored, so a fresh checkout or worktree does not have one.',
      );
    });

    test('ships no colliding shader entry points', () {
      final bundles = _builtBundles();
      final collisions = collisionsAmong({
        for (final entry in bundles.entries) entry.key: entryPointsIn(entry.value),
      });
      expect(
        collisions,
        isEmpty,
        reason: 'Two packages ship a shader file with the same stem. Rename the '
            'file — prefix it with the package name. The manifest key has no '
            'effect on the entry point.',
      );
    });

    test('reads entry points out of a real bundle', () {
      // Pins that the scan above is looking at something. A regex that matched
      // nothing would make the collision test pass for the wrong reason.
      final engine = _builtBundles()['flutter3d_gpu'];
      expect(engine, isNotNull);
      final names = entryPointsIn(engine!);
      expect(names, contains('pbr_fragment_main'));
      expect(names, contains('unlit_fragment_main'));
      expect(names.length, greaterThan(10));
    });
  });
}
