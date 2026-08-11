/// `flutter_gpu` is imported in `lib/src/engine/gpu/` and nowhere else.
///
/// That is the whole boundary this engine draws, and it is one sentence on
/// purpose. Everything else in `lib/` — the renderer, the frame graph, the
/// nodes, the contributors, the scene, the assets — is written against
/// `graphics/`, so a second backend is a second directory beside `gpu/` rather
/// than an edit to any of them.
///
/// `graphics_is_backend_free_test.dart` states the rule from the other end: the
/// vocabulary may not reach a backend. This one is the complement, and it is
/// the harder half, because the renderer is where a backend import creeps back
/// in for one line and never leaves.
///
/// Deliberately a file scan. The set is small, the rule is textual, and a scan
/// says which file broke it.
///
/// The second test here is the same boundary stated as a dependency rather
/// than as a name, and the difference is easy to miss: not *naming*
/// `flutter_gpu` is not the same as not *depending* on `gpu/`. Three core files
/// did — `model_asset.dart`, `texture_upload.dart` and `procedural_texture.dart`
/// — all for the same missing thing, a way to get CPU data onto the device.
/// They reached `gpuContext`, a global, which is the one shape of dependency
/// that cannot be satisfied from another package.
///
/// **That list is empty now**, and the allowlist below is kept at zero
/// deliberately. It is not bookkeeping: it is the difference between a backend
/// that can be lifted into its own package by moving a directory, and one that
/// has to be rewritten because the core reaches into it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one directory allowed to name a graphics API.
const String _backendDir = 'lib/src/engine/gpu/';

/// Core files allowed to reach into `gpu/`, and why each one is.
///
/// **Empty, and worth keeping empty.** Content upload — vertices, indices,
/// pixels — was the last thing here, and it now goes through
/// `GraphicsDevice.uploadGeometry` and `createTextureFromPixels` like
/// everything else. `GpuMesh` became `DeviceMesh` in `geometry/`, because
/// nothing about a mesh was backend-specific once its buffers were handles.
///
/// An entry here is a claim that some core file cannot be written against
/// `graphics/`. Adding one should feel like a decision, which is why it is a
/// map with reasons rather than a list of paths.
const Map<String, String> _mayReachBackend = <String, String>{};

void main() {
  test('only gpu/ imports flutter_gpu', () {
    final lib = Directory('lib');
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'run from the package root, where lib/ is',
    );

    final offenders = <String>[];
    var backendFiles = 0;

    for (final file in lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final reaches = file.readAsLinesSync().any((line) {
        final trimmed = line.trim();
        return (trimmed.startsWith('import ') ||
                trimmed.startsWith('export ')) &&
            trimmed.contains('flutter_gpu');
      });
      if (!reaches) continue;
      if (file.path.startsWith(_backendDir)) {
        backendFiles++;
      } else {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these reach flutter_gpu from outside $_backendDir, which is '
          'where the backend lives. Whatever they need belongs on '
          'GraphicsDevice or CommandEncoder',
    );

    // A scan that finds nothing proves nothing: if the backend directory ever
    // moves, the check above would pass by scanning an empty set.
    expect(
      backendFiles,
      greaterThan(0),
      reason: '$_backendDir names no backend at all, so this test is checking '
          'nothing — the directory moved and the rule has to move with it',
    );
  });

  test('only the named core files depend on gpu/ at all', () {
    final reaching = <String>{};

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // `gpu/` itself, and the umbrella that has to export it, are not the
      // subject: an application constructs the backend, so `flutter3d.dart`
      // naming it is the seam working rather than leaking.
      if (file.path.startsWith(_backendDir) ||
          file.path == 'lib/flutter3d.dart') {
        continue;
      }
      final reaches = file.readAsLinesSync().any((line) {
        final trimmed = line.trim();
        return trimmed.startsWith('import ') && trimmed.contains("gpu/gpu_") ||
            trimmed.startsWith('import ') &&
                trimmed.contains('gpu/texture_upload');
      });
      if (reaches) reaching.add(file.path);
    }

    expect(
      reaching.difference(_mayReachBackend.keys.toSet()),
      isEmpty,
      reason: 'a new core file reaches into $_backendDir. If it wants to put '
          'data on the device, that seam belongs on GraphicsDevice — and if it '
          'genuinely has to be here, add it above with the reason',
    );

    // The other direction, so the list cannot rot into a description of code
    // that has since been fixed. A stale entry reads as a debt that is still
    // owed, and the next person budgets for work already done.
    expect(
      _mayReachBackend.keys.toSet().difference(reaching),
      isEmpty,
      reason: 'these no longer reach $_backendDir, so the allowlist is stale — '
          'delete the entry and take the credit',
    );
  });
}
