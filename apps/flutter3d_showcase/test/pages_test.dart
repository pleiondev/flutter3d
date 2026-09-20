@Tags(['golden', 'skip_very_good_optimization'])
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/page_harness.dart';

void main() {
  // Most pages build their scene from nothing but code, but a page that
  // loads a real asset (character-controller's model, loaded through
  // `rootBundle`) needs a binding to load it through, and a plain `test()`
  // never creates one on its own.
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final Feature feature in allFeatures) {
    test('${feature.id} draws something and keeps its own claim', () async {
      // Mutation: build the scene and add nothing to it. The frame comes back
      // black and `litPixels` is zero, which is the failure this catches.
      final PageFrame page = await renderPage(feature);
      expect(page.litPixels, greaterThan(0), reason: feature.id);
    });
  }
}
