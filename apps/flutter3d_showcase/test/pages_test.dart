@Tags(['golden', 'skip_very_good_optimization'])
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/page_harness.dart';

void main() {
  for (final Feature feature in allFeatures) {
    test('${feature.id} draws something and keeps its own claim', () async {
      // Mutation: build the scene and add nothing to it. The frame comes back
      // black and `litPixels` is zero, which is the failure this catches.
      final PageFrame page = await renderPage(feature);
      expect(page.litPixels, greaterThan(0), reason: feature.id);
    });
  }
}
