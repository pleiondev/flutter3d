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
/// The second test here is the weaker half of the same boundary, and it is
/// written down because the difference is easy to miss. Not naming
/// `flutter_gpu` is not the same as not *depending* on `gpu/`: three files in
/// the core still import that directory, so the backend cannot yet be lifted
/// into a package of its own. Every one of them wants the same missing thing —
/// a way to get CPU data onto the device — which is the next seam, not this
/// one. An allowlist keeps that a known list of three rather than a habit.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one directory allowed to name a graphics API.
const String _backendDir = 'lib/src/engine/gpu/';

/// Core files that still reach into `gpu/`, and what each one wants.
///
/// All three are *content upload* — vertices, indices, pixels — which is a
/// different seam from encoding a pass and was deliberately left for later. The
/// encoder took the drawing side: nothing here is on the path of a draw.
///
/// The list may shrink. It may not grow without somebody deciding to, which is
/// the whole point of writing it here instead of in a commit message.
const Map<String, String> _mayReachBackend = <String, String>{
  'lib/src/engine/assets/model_asset.dart':
      'GpuMesh.upload and the texture upload path — a decoded model has to '
          'reach the device, and GraphicsDevice has no way to put it there yet',
  'lib/src/engine/render/procedural_texture.dart':
      'createGpuTexture plus Texture.overwrite, to upload generated pixels — '
          'the same missing seam, for textures rather than meshes',
};

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
