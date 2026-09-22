/// The gallery's own first source: the models this build makes — `gal-01`.
///
/// **Always there, and never a network call.** Every other source can be
/// unreachable; this one cannot, which is what keeps the gallery useful on
/// a laptop with no connection and in a test with no HTTP client. It is
/// also the only source whose licence needs no checking: the models are
/// built here, so they are ours to put in the public domain.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

import 'gallery_item.dart';

/// `gal-02`'s own recipes, as gallery items.
final class RecipeSource implements GallerySource {
  const RecipeSource();

  @override
  String get id => 'built-in';

  @override
  String get name => 'Built in';

  @override
  Future<List<GalleryItem>> list() async => <GalleryItem>[
    for (final Recipe recipe in recipes())
      GalleryItem(
        id: '$id/${recipe.id}',
        name: recipe.name,
        about: recipe.about,
        category: recipe.category,
        licence: GalleryLicence.ours,
        sourceId: id,
        // Built when somebody inserts, not while the grid draws: sixteen
        // meshes made to fill a list nobody has clicked in is sixteen
        // meshes thrown away.
        open: () async => BuiltModel(recipe.build()),
      ),
  ];
}
