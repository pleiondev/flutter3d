/// What the gallery endpoints answer with — `gal-07`.
///
/// **The shape the modeller already understands.** An item here is the
/// same four facts `GalleryItem` insists on — an id, a name, a category and
/// a licence — plus the author a licence that asks for a credit needs. The
/// server does not invent a second vocabulary for the same thing; what it
/// adds is the one thing a client cannot do, which is hold a key.
///
/// **A licence the server cannot read keeps the item out of the index.**
/// That rule lives in three places now — the catalogue, the grid and here —
/// and it is worth repeating rather than trusting: each of the three is a
/// place an item can arrive from, and the cost of being wrong is an export
/// that ships without a credit it owed.
library;

import 'dart:typed_data';

/// One item of the index.
final class CatalogueItem {
  const CatalogueItem({
    required this.id,
    required this.name,
    required this.about,
    required this.category,
    required this.licenceId,
    required this.licenceName,
    required this.licenceUrl,
    required this.requiresAttribution,
    this.author,
  });

  /// `<source>/<id>`, which is what `/gallery/model/...` takes.
  final String id;

  final String name;
  final String about;

  /// One of the modeller's own four — `lighting`, `furniture`,
  /// `tableware`, `architecture`.
  final String category;

  final String licenceId;
  final String licenceName;
  final String licenceUrl;
  final bool requiresAttribution;

  /// Who to credit. Never null where [requiresAttribution] is true — an
  /// item that cannot say is one this index leaves out.
  final String? author;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'about': about,
    'category': category,
    'licence': <String, Object?>{
      'id': licenceId,
      'name': licenceName,
      'url': licenceUrl,
      'requiresAttribution': requiresAttribution,
    },
    if (author != null) 'author': author,
  };
}

/// The index, and what could not be reached while building it.
typedef CatalogueIndex = ({
  List<CatalogueItem> items,
  List<String> unreachable,
});

/// A model's bytes, ready to hand back.
typedef CatalogueDownload = ({
  Uint8List bytes,
  String contentType,
  String fileName,
});

/// Where the index and the models come from.
///
/// **An interface, so the routes can be tested without a network.** The
/// real one reads the catalogues the server has keys for; a test's own
/// answers whatever it was built with, which is how the routes' own rules —
/// the headers, the not-found sentence, the unreachable list — are checked
/// at all.
abstract interface class GalleryCatalogue {
  /// Everything this server can offer right now.
  Future<CatalogueIndex> index();

  /// The bytes for [id], or null when nothing here offers it.
  Future<CatalogueDownload?> download(String id);
}

/// A catalogue built from a fixed list — what a server with no keys
/// configured answers with, and what a test uses.
///
/// **A server with no keys is not a broken server.** It offers what it can
/// reach without one, says nothing it cannot, and the modeller falls back
/// to its own built-in models regardless — which is why the gallery works
/// on a laptop with no network at all.
final class FixedCatalogue implements GalleryCatalogue {
  const FixedCatalogue({
    this.items = const <CatalogueItem>[],
    this.unreachable = const <String>[],
    this.bytesFor,
  });

  final List<CatalogueItem> items;
  final List<String> unreachable;

  /// What `/gallery/model/...` hands back for an id, or null.
  final Future<CatalogueDownload?> Function(String id)? bytesFor;

  @override
  Future<CatalogueIndex> index() async =>
      (items: items, unreachable: unreachable);

  @override
  Future<CatalogueDownload?> download(String id) async {
    if (bytesFor == null) return null;
    // Only ids this index actually offers: a proxy that fetched whatever
    // it was asked for would be an open relay with our own key on it.
    if (!items.any((CatalogueItem it) => it.id == id)) return null;
    return bytesFor!(id);
  }
}
