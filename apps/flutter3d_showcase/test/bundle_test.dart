@Tags(['skip_very_good_optimization'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_showcase/src/catalog/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the site bundle has every page, its guide and its source', () async {
    // Mutation: skip a page that fails to expand. The site would then build
    // with a hole where a guide should be, and nobody would be told.
    final Directory out = Directory.systemTemp.createTempSync('bundle_');
    addTearDown(() => out.deleteSync(recursive: true));

    final ProcessResult result = await Process.run('dart', <String>[
      'run',
      'tool/showcase_bundle.dart',
      '--out',
      out.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final Map<String, Object?> manifest =
        jsonDecode(File('${out.path}/manifest.json').readAsStringSync())
            as Map<String, Object?>;
    final List<Object?> features = manifest['features']! as List<Object?>;
    expect(features, hasLength(kCatalog.length));
    for (final feature in kCatalog) {
      expect(File('${out.path}/learn/${feature.id}.md').existsSync(), isTrue);
      expect(File('${out.path}/src/${feature.id}.dart').existsSync(), isTrue);
      final String guide = File(
        '${out.path}/learn/${feature.id}.md',
      ).readAsStringSync();
      // The directives that quote code are all expanded.
      expect(guide, isNot(contains('{{code')));
    }
  });
}
