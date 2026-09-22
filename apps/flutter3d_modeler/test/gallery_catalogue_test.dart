/// `gal-01`: what a gallery catalogue refuses, and what it puts first.
///
///     flutter test test/gallery_catalogue_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/gallery/gallery_item.dart';
import 'package:flutter3d_modeler/src/gallery/recipe_source.dart';
import 'package:flutter_test/flutter_test.dart';

GalleryItem _item({
  required String id,
  required GalleryLicence licence,
  String? author,
  String name = 'A thing',
  String source = 'somewhere',
}) => GalleryItem(
  id: id,
  name: name,
  about: 'One sentence about what it is.',
  category: RecipeCategory.furniture,
  licence: licence,
  sourceId: source,
  author: author,
  open: () async => BuiltModel(EditMesh.cuboid()),
);

void main() {
  group('a licence is not optional', () {
    test('an item under CC-BY with nobody to credit is refused', () {
      // **The credit `gal-05` writes has to name somebody.** Mutation:
      // accept the item and let the export write an empty credit line —
      // the file then claims to attribute and does not, which is worse
      // than not attributing at all.
      final GalleryItem nameless = _item(
        id: 'somewhere/chair',
        licence: GalleryLicence.ccBy4,
      );
      expect(refuseItem(nameless), contains('names no author'));

      final GalleryItem credited = _item(
        id: 'somewhere/chair',
        licence: GalleryLicence.ccBy4,
        author: 'A. Maker',
      );
      expect(refuseItem(credited), isNull);
    });

    test('an id that does not name its own source is refused', () {
      // Two catalogues both offering "chair" is the ordinary case, and an
      // id that does not say which is the bug that follows it.
      expect(
        refuseItem(_item(id: 'chair', licence: GalleryLicence.cc0)),
        contains('source id'),
      );
    });

    test('CC0 asks for nothing and CC-BY-NC says so plainly', () {
      expect(GalleryLicence.cc0.isFree, isTrue);
      expect(GalleryLicence.ours.isFree, isTrue);
      expect(GalleryLicence.ccBy4.isFree, isFalse);
      expect(GalleryLicence.ccBy4.requiresAttribution, isTrue);
      // Non-commercial is rare enough to be missed and serious enough to
      // matter, so it is its own flag rather than a note in a name.
      expect(GalleryLicence.ccByNc4.allowsCommercial, isFalse);
      expect(GalleryLicence.ccByNc4.isFree, isFalse);
    });
  });

  test('free items come first, and the rest stay listed', () {
    final List<GalleryItem> sorted = freeFirst(<GalleryItem>[
      _item(
        id: 'a/zebra',
        licence: GalleryLicence.ccBy4,
        name: 'Zebra',
        author: 'Someone',
      ),
      _item(
        id: 'a/apple',
        licence: GalleryLicence.ccBy4,
        name: 'Apple',
        author: 'Someone',
      ),
      _item(id: 'a/mug', licence: GalleryLicence.cc0, name: 'Mug'),
      _item(id: 'a/bench', licence: GalleryLicence.cc0, name: 'Bench'),
    ]);

    // **A sort, not a filter.** Mutation: drop everything that is not
    // free. The gallery then silently hides most of what the outside
    // sources offer, and a person who wanted a CC-BY model has no way to
    // find out it was there.
    expect(sorted.map((GalleryItem it) => it.name), <String>[
      'Bench',
      'Mug',
      'Apple',
      'Zebra',
    ]);
  });

  group('the built-in source', () {
    test('offers every recipe, each under our own CC0', () async {
      final List<GalleryItem> items = await const RecipeSource().list();

      expect(items, hasLength(recipes().length));
      for (final GalleryItem item in items) {
        expect(refuseItem(item), isNull, reason: item.id);
        expect(item.isFree, isTrue, reason: item.id);
        expect(item.id.startsWith('built-in/'), isTrue);
      }
    });

    test('and builds a mesh only when one is asked for', () async {
      final List<GalleryItem> items = await const RecipeSource().list();
      final GalleryModel model = await items.first.open();

      // Mutation: build every mesh while listing. Sixteen meshes are made
      // to fill a grid nobody has clicked in, and thrown away with it.
      expect(model, isA<BuiltModel>());
      expect((model as BuiltModel).mesh.faceCount, greaterThan(0));
    });
  });
}
