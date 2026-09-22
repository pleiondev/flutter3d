/// Catalogues that live somewhere else — `gal-04`.
///
/// **The network is a detail, and it is handed in.** Every source here
/// takes a [Fetch] rather than reaching for an HTTP client of its own, so a
/// test drives the whole path — listing, caching, refusing — without a
/// socket, and the web build uses the same code as the desktop one.
///
/// **A source that cannot answer costs its own items and nothing else.**
/// `GallerySource.list` is allowed to fail precisely so that one catalogue
/// being down is a row saying so rather than an empty grid; `RemoteSource`
/// makes that easy to get right by turning every failure into one
/// exception the screen already handles.
///
/// **Cached on disk, because a catalogue is not the model.** The list is
/// small, changes rarely and is needed every time the gallery opens; the
/// models themselves are fetched when somebody inserts one and are not
/// cached at all yet — a gigabyte of somebody else's props in an
/// application's own directory is a decision, not a side effect, and
/// nothing has asked for it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart' show RecipeCategory;

import 'gallery_item.dart';

/// One HTTP GET: the bytes at [url], or a throw.
///
/// A function rather than a client, so this file depends on nothing that
/// has a platform. `mcp_bootstrap_io.dart` is the precedent — the code that
/// knows about sockets lives at the edge, and everything inland takes it as
/// an argument.
typedef Fetch = Future<Uint8List> Function(String url);

/// Where a catalogue is kept between runs.
///
/// **An interface rather than a path**, because the web has no directory
/// and a test wants neither. The application passes its own storage; a test
/// passes a map.
abstract interface class GalleryCache {
  /// What was stored under [key], or null.
  Future<String?> read(String key);

  /// Stores [value] under [key].
  Future<void> write(String key, String value);
}

/// A cache that remembers nothing — what a build with no storage gets, and
/// what keeps the rest of this file honest about a cold start.
final class NoCache implements GalleryCache {
  const NoCache();

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}

/// How long a cached catalogue is used before it is fetched again.
///
/// **A day, because a catalogue is not news.** Somebody who opens the
/// gallery six times in an afternoon should not wait for six round trips to
/// see the same list; somebody who comes back tomorrow should see what was
/// added.
const Duration kCatalogueStale = Duration(days: 1);

/// A catalogue read from somewhere else, cached, and turned into items.
final class RemoteSource implements GallerySource {
  const RemoteSource({
    required this.id,
    required this.name,
    required this.url,
    required this.parse,
    required this.fetch,
    this.cache = const NoCache(),
    this.now,
  });

  @override
  final String id;

  @override
  final String name;

  /// Where the catalogue itself is.
  final String url;

  /// What this source's own JSON means. Given the decoded body and the
  /// source's id, it answers the items — and throws for a body it does not
  /// recognise, which `list` turns into "this source could not be read"
  /// rather than a half-parsed catalogue.
  final List<GalleryItem> Function(Object? body, RemoteSource source) parse;

  final Fetch fetch;

  final GalleryCache cache;

  /// The clock, for a test that has to age a cache entry without waiting a
  /// day. Null reads the real one.
  final DateTime Function()? now;

  @override
  Future<List<GalleryItem>> list() async {
    final DateTime at = (now ?? DateTime.now)();
    final String? cached = await cache.read(id);
    if (cached != null) {
      final ({DateTime? at, Object? body})? stored = _stored(cached);
      if (stored != null &&
          stored.at != null &&
          at.difference(stored.at!) < kCatalogueStale) {
        return _itemsFrom(stored.body);
      }
    }

    final Uint8List bytes = await fetch(url);
    final Object? body = jsonDecode(utf8.decode(bytes));
    final List<GalleryItem> items = _itemsFrom(body);
    // Written only after it parsed: a cache entry nothing can read is a
    // day of the gallery refusing this source for no reason a person can
    // act on.
    await cache.write(
      id,
      jsonEncode(<String, Object?>{'at': at.toIso8601String(), 'body': body}),
    );
    return items;
  }

  List<GalleryItem> _itemsFrom(Object? body) => <GalleryItem>[
    for (final GalleryItem item in parse(body, this))
      // `gal-01`'s own rule, applied where items arrive rather than where
      // they are drawn: a catalogue that offers a CC-BY model naming
      // nobody is a catalogue with a bug, and listing it would carry that
      // bug into an export.
      if (refuseItem(item) == null) item,
  ];

  static ({DateTime? at, Object? body})? _stored(String cached) {
    try {
      final Object? decoded = jsonDecode(cached);
      if (decoded is! Map<String, Object?>) return null;
      return (
        at: DateTime.tryParse(decoded['at'] as String? ?? ''),
        body: decoded['body'],
      );
    } on FormatException {
      // A cache file somebody edited, or one a half-written run left
      // behind: fetch instead of failing.
      return null;
    }
  }
}

/// Builds an item from the four things every catalogue has to supply.
///
/// **Its own function so that a source's `parse` is only the shape of that
/// source's JSON.** Every adapter below is then a mapping and nothing else,
/// which is what makes adding one an afternoon rather than a review.
GalleryItem remoteItem({
  required RemoteSource source,
  required String id,
  required String name,
  required String about,
  required RecipeCategory category,
  required GalleryLicence licence,
  required String downloadUrl,
  String? author,
}) => GalleryItem(
  id: '${source.id}/$id',
  name: name,
  about: about,
  category: category,
  licence: licence,
  sourceId: source.id,
  author: author,
  open: () async => FetchedModel(
    bytes: await source.fetch(downloadUrl),
    // The name is what tells the decoder which format it is looking at,
    // so it carries the suffix the catalogue gave rather than a guess.
    name: downloadUrl.split('/').last,
  ),
);

/// What a catalogue's own words map to, for a source whose categories are
/// not this application's four.
///
/// **A default rather than a refusal.** A chair filed under "seating" is
/// still a chair; dropping it because the word is not in a table would make
/// the gallery smaller for no reason a person cares about.
RecipeCategory categoryFor(String said) {
  final String word = said.toLowerCase();
  if (word.contains('lamp') ||
      word.contains('light') ||
      word.contains('sconce')) {
    return RecipeCategory.lighting;
  }
  if (word.contains('cup') ||
      word.contains('mug') ||
      word.contains('plate') ||
      word.contains('vase') ||
      word.contains('bottle')) {
    return RecipeCategory.tableware;
  }
  if (word.contains('door') ||
      word.contains('window') ||
      word.contains('wall') ||
      word.contains('stair')) {
    return RecipeCategory.architecture;
  }
  return RecipeCategory.furniture;
}
