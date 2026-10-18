/// Reading a page's files from the app's assets.
///
/// **The page's own source and its guide are assets, not copies.** They are the
/// files in `lib/pages/<category>/`, declared in the pubspec, so the Source tab
/// shows the bytes that were compiled and a guide cannot be shipped without the
/// page it quotes.
library;

import 'package:flutter/services.dart';
import 'package:flutter3d_showcase/src/catalog/catalog.dart';
import 'package:flutter3d_showcase/src/catalog/feature.dart';

/// A page's source and its guide, and the source of any other page the guide
/// quotes from.
final class Guide {
  /// A guide with its page's source and the sources it quotes from other
  /// pages; [loadGuide] is how the app makes one.
  const Guide({
    required this.markdown,
    required this.pageSource,
    required this.others,
  });

  /// The guide's Markdown as written, its `{{code …}}` lines not yet expanded.
  final String markdown;

  /// The source of the page the guide belongs to, region markers and all.
  final String pageSource;

  /// The source of every other page the guide points into, by id.
  final Map<String, String> others;

  /// The source of page [id], for a `{{code id#region}}` line. Throws a
  /// [StateError] for a page [loadGuide] did not read, which is a guide
  /// quoting a page it never named.
  String sourceOf(String id) =>
      others[id] ?? (throw StateError('the guide never loaded "$id"'));
}

final RegExp _otherPage = RegExp(r'\{\{\s*code\s+([a-z0-9-]+)#');

/// Reads [feature]'s guide and page source from [bundle], and the source of
/// every other page the guide quotes. Throws a [StateError] when the guide
/// names a page the catalog does not have.
Future<Guide> loadGuide(AssetBundle bundle, Feature feature) async {
  final String markdown = await bundle.loadString(feature.tutorialFile);
  final Map<String, String> others = <String, String>{};
  for (final RegExpMatch match in _otherPage.allMatches(markdown)) {
    final String id = match.group(1)!;
    final Feature? other = featureNamed(id);
    if (other == null) throw StateError('the guide points at unknown page $id');
    others[id] = await bundle.loadString(other.pageFile);
  }
  return Guide(
    markdown: markdown,
    pageSource: await bundle.loadString(feature.pageFile),
    others: others,
  );
}
