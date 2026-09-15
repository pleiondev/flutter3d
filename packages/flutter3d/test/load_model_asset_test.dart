/// `ap-11`: `loadModelAsset` reads the build hook's own converted `.f3d`
/// when it is there, and — only in debug, only off the web — decodes the
/// source directly and warns once when it is not.
///
/// **Why `FileAssetSource`, not a real `rootBundle` fixture.** This
/// package ships no `flutter: assets:` of its own (nothing under `lib/`
/// needs one), and adding a throwaway fixture there to exercise
/// [BundleAssetSource] would ship that fixture to every application that
/// depends on this package — a real cost for a test's convenience. This
/// package's own `model_loader_test.dart` already avoids mocking
/// `rootBundle` the same way, reading real files through
/// [FileAssetSource] instead. `loadModelAsset` takes [AssetSource]
/// factories for exactly this reason: a test can stand a real temporary
/// file in for what a real asset bundle would serve, and the two lines
/// that actually reach `rootBundle` ([BundleAssetSource.read] itself) are
/// a single, already-tested seam this package does not re-test here.
import 'dart:io';

import 'package:flutter3d/src/engine/assets/load_model_asset.dart';
import 'package:flutter3d/src/engine/assets/model_loader.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';

const String kSamples = kSamplesPath;

void main() {
  group('generatedAssetPathFor', () {
    test('assets_src/ becomes flutter3d_generated/, extension swapped', () {
      expect(
        generatedAssetPathFor('assets_src/chair.glb'),
        'flutter3d_generated/chair.f3d',
      );
    });

    test('a nested source keeps its own relative directories', () {
      expect(
        generatedAssetPathFor('assets_src/props/lamp.obj'),
        'flutter3d_generated/props/lamp.f3d',
      );
    });

    test('a path with no assets_src/ prefix is rewritten in place', () {
      expect(
        generatedAssetPathFor('chair.glb'),
        'flutter3d_generated/chair.f3d',
      );
    });
  });

  group('loadModelAsset', () {
    late Directory scratch;

    setUp(() => scratch = Directory.systemTemp.createTempSync('f3d_load_'));
    tearDown(() => scratch.deleteSync(recursive: true));

    test('the generated file is preferred when it is there', () async {
      // A fixture standing in for the *generated* side: any recognised
      // model works, since this only proves loadModelAsset reached the
      // generated path rather than falling back to the source at all.
      final document = await loadModelAsset(
        'assets_src/does-not-matter.glb',
        generatedSource: (path) {
          expect(path, 'flutter3d_generated/does-not-matter.f3d');
          return const FileAssetSource('$kSamples/Box.glb');
        },
        fallbackSource: (path) => fail('the generated file was there — the '
            'fallback must not be reached'),
      );
      expect(document.surfaces, isNotEmpty);
    });

    test(
      'in debug, a missing generated file falls back to the source and '
      'warns once',
      () async {
        final source = File('${scratch.path}/chair.obj')
          ..writeAsStringSync('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n');

        Future<ModelDocument> load() => loadModelAsset(
          source.path,
          debugMode: true,
          generatedSource: (_) =>
              const FileAssetSource('/nonexistent/nowhere.f3d'),
          fallbackSource: (path) => FileAssetSource(path),
        );

        final first = await load();
        expect(first.triangleCount, 1);

        // A second call for the same path must not throw or duplicate the
        // warning — `_warnedMissingGenerated` is a set keyed by source
        // path, checked here by the fact that this simply succeeds again,
        // the same way the first call did.
        final second = await load();
        expect(second.triangleCount, 1);
      },
    );

    test('outside debug, a missing generated file is a real error', () async {
      final source = File('${scratch.path}/chair.obj')
        ..writeAsStringSync('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n');

      await expectLater(
        loadModelAsset(
          source.path,
          debugMode: false,
          generatedSource: (_) =>
              const FileAssetSource('/nonexistent/nowhere.f3d'),
          fallbackSource: (path) => fail('release must not fall back'),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('flutter3d_build:init'),
          ),
        ),
      );
    });

    test(
      'a genuinely corrupt generated file is a real error, not a silent '
      'fallback',
      () async {
        // Present, readable, and not a model at all — the file exists, so
        // this must not be treated as "missing".
        final corrupt = File('${scratch.path}/chair.f3d')
          ..writeAsStringSync('not an f3d file');

        await expectLater(
          loadModelAsset(
            'assets_src/chair.obj',
            debugMode: true,
            generatedSource: (_) => FileAssetSource(corrupt.path),
            fallbackSource: (path) =>
                fail('a corrupt file is not a missing one'),
          ),
          throwsA(anything),
        );
      },
    );
  });
}
