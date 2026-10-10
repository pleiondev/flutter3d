@Tags(['skip_very_good_optimization'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_showcase/src/catalog/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/showcase_bundle.dart';

void main() {
  test('the site bundle has every page, its guide and its source', () {
    // Mutation: skip a page that fails to expand. The site would then build
    // with a hole where a guide should be, and nobody would be told.
    final Directory out = Directory.systemTemp.createTempSync('bundle_');
    addTearDown(() => out.deleteSync(recursive: true));

    // Called in this process and not through `dart run`, whose first run on a
    // clean checkout builds every package's native hooks before the tool
    // starts: minutes, for a bundle that takes well under a second.
    final ShowcaseBundle bundle = writeShowcaseBundle(out);
    expect(bundle.failures, isEmpty, reason: bundle.failures.join('\n'));
    expect(bundle.pages, kCatalog.length);

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
