/// The catalogue a gallery lists — `gal-01`.
///
/// **A licence is not optional and has no default.** "Free models" and
/// "models you may ship without crediting anybody" are different sets, and
/// a gallery that blurs them is a gallery that gets somebody sued. So
/// [GalleryItem] cannot be constructed without one, and a source that
/// cannot say what an item is licensed under does not offer that item at
/// all — there is no `unknown` to fall back to, on purpose.
///
/// **CC0 first, and that is a sort rather than a filter.** Everything the
/// sources offer can be listed; what the order says is which of them cost
/// nothing downstream. `gal-05` is what makes the rest honest: a CC-BY
/// model writes its credit into the export, so choosing one is a decision
/// with a visible consequence rather than a trap.
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

/// What an item's licence lets somebody do, and what it asks in return.
///
/// **A class with const instances rather than an enum**, the same shape
/// `LightingModel` keeps: a licence this build has never heard of is a real
/// thing a source can name, and an enum would make every one of those a
/// case somebody has to add here before the item can be listed at all.
final class GalleryLicence {
  const GalleryLicence({
    required this.id,
    required this.name,
    required this.url,
    required this.requiresAttribution,
    this.allowsCommercial = true,
  });

  /// The SPDX-style identifier, lowercase — `cc0`, `cc-by-4.0`.
  final String id;

  /// What the card shows.
  final String name;

  /// Where the full text is, for somebody who has to read it.
  final String url;

  /// Whether an export that includes this item owes somebody a credit.
  /// `gal-05` is what writes it.
  final bool requiresAttribution;

  /// Whether the item may be used in something sold. False is rare and
  /// worth showing plainly rather than burying.
  final bool allowsCommercial;

  /// Public domain: no credit, no conditions.
  static const GalleryLicence cc0 = GalleryLicence(
    id: 'cc0',
    name: 'CC0 — public domain',
    url: 'https://creativecommons.org/publicdomain/zero/1.0/',
    requiresAttribution: false,
  );

  /// What this repository's own recipes are under. The same terms as
  /// [cc0]; a separate instance so a card can say where a model came from
  /// without a second field.
  static const GalleryLicence ours = GalleryLicence(
    id: 'cc0',
    name: 'CC0 — built by this application',
    url: 'https://creativecommons.org/publicdomain/zero/1.0/',
    requiresAttribution: false,
  );

  /// Credit the author, and that credit travels with every copy.
  static const GalleryLicence ccBy4 = GalleryLicence(
    id: 'cc-by-4.0',
    name: 'CC BY 4.0 — credit the author',
    url: 'https://creativecommons.org/licenses/by/4.0/',
    requiresAttribution: true,
  );

  /// Credit, and nothing sold.
  static const GalleryLicence ccByNc4 = GalleryLicence(
    id: 'cc-by-nc-4.0',
    name: 'CC BY-NC 4.0 — credit, non-commercial',
    url: 'https://creativecommons.org/licenses/by-nc/4.0/',
    requiresAttribution: true,
    allowsCommercial: false,
  );

  /// Whether an item under this costs nothing downstream — what the
  /// default filter keeps.
  bool get isFree => !requiresAttribution && allowsCommercial;
}

/// What an item hands over when somebody inserts it.
sealed class GalleryModel {
  const GalleryModel();
}

/// A model this build makes — `gal-02`'s own recipes.
final class BuiltModel extends GalleryModel {
  const BuiltModel(this.mesh);

  final EditMesh mesh;
}

/// A model that arrived as a file, which the import path decodes the same
/// way it decodes one a person dropped on the window.
final class FetchedModel extends GalleryModel {
  const FetchedModel({required this.bytes, required this.name});

  final Uint8List bytes;

  /// The file's own name, extension included — what tells the decoder
  /// which format it is looking at.
  final String name;
}

/// One thing a gallery can offer.
final class GalleryItem {
  const GalleryItem({
    required this.id,
    required this.name,
    required this.about,
    required this.category,
    required this.licence,
    required this.sourceId,
    required this.open,
    this.author,
  });

  /// Unique across every source — a source prefixes its own ids, so two
  /// catalogues cannot collide over "chair".
  final String id;

  final String name;

  /// One sentence about what it is. The same rule `ux-18` gives a tool: a
  /// card with only a name asks somebody to insert the thing to find out
  /// what it is.
  final String about;

  /// Which section it lists under. `gal-02`'s own four, shared so a
  /// downloaded lamp sits beside a built one.
  final RecipeCategory category;

  /// What it is licensed under. Required, and there is no default.
  final GalleryLicence licence;

  /// Which source offered it — `GallerySource.id`.
  final String sourceId;

  /// Who made it, when the licence asks for a credit. Null is only legal
  /// where [GalleryLicence.requiresAttribution] is false.
  final String? author;

  /// Fetches or builds it. Called when somebody inserts, never while a
  /// grid is being drawn.
  final Future<GalleryModel> Function() open;

  /// Whether this item can be inserted without owing anybody anything.
  bool get isFree => licence.isFree;
}

/// Where items come from: the recipes, a cached download, an API.
abstract interface class GallerySource {
  /// Stable and lowercase — what an item's own id is prefixed with.
  String get id;

  /// What the grid's own group heading says.
  String get name;

  /// Everything this source offers.
  ///
  /// **Answers rather than throws when it cannot reach anything.** A
  /// source that is down is a row saying so, never an empty grid and never
  /// an exception that takes the other sources' items with it — `gal-04`'s
  /// own rule, stated here because this is the interface that has to make
  /// it possible.
  Future<List<GalleryItem>> list();
}

/// [items] with the ones that cost nothing downstream first, and each group
/// alphabetical.
///
/// **A sort, not a filter.** Everything stays listed; what the order says
/// is which of them a person can use without reading anything. A filter
/// belongs to the screen, where somebody can see it and turn it off.
List<GalleryItem> freeFirst(List<GalleryItem> items) {
  final sorted = <GalleryItem>[...items];
  sorted.sort((GalleryItem a, GalleryItem b) {
    if (a.isFree != b.isFree) return a.isFree ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return sorted;
}

/// Whether [item] may be listed at all, and why not when it may not.
///
/// The one rule a catalogue enforces on itself: an item under a licence
/// that asks for a credit has to name somebody to credit, or the credit
/// `gal-05` writes would be a blank line.
String? refuseItem(GalleryItem item) {
  if (item.licence.requiresAttribution &&
      (item.author == null || item.author!.trim().isEmpty)) {
    return '${item.id} is under ${item.licence.name} and names no author';
  }
  if (!item.id.startsWith('${item.sourceId}/')) {
    return '${item.id} does not start with its own source id';
  }
  return null;
}
