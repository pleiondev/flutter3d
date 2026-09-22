/// Finding a page by what a person would type.
///
/// Title, id, summary, category, keywords and the version all count, and a
/// query that looks like a version (`0.5`) lists what appeared in it, since
/// "what is new in 0.7" is the question a release brings. No fuzzy matching:
/// ninety pages are few enough that a plain substring is predictable, and a
/// list that reorders itself on a typo would be harder to trust than one that
/// simply shows nothing.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

final RegExp _versionLike = RegExp(r'^\d+(\.\d+){0,2}$');

/// The features of [all] that match [query], best first; [all] in its own order
/// for an empty query.
List<Feature> searchFeatures(String query, List<Feature> all) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return all;

  if (_versionLike.hasMatch(q)) {
    return <Feature>[
      for (final Feature f in all)
        if (f.since == q || f.since.startsWith('$q.')) f,
    ];
  }

  // The catalog position is part of the key because `List.sort` promises no
  // stability, and features with the same score should keep catalog order.
  final List<(int score, int at, Feature feature)> hits =
      <(int, int, Feature)>[
        for (var i = 0; i < all.length; i++)
          if (_score(all[i], q) > 0) (_score(all[i], q), i, all[i]),
      ]..sort(
        ((int, int, Feature) a, (int, int, Feature) b) =>
            a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2),
      );
  return <Feature>[for (final hit in hits) hit.$3];
}

int _score(Feature f, String q) {
  if (f.title.toLowerCase() == q || f.id == q) return 100;
  if (f.title.toLowerCase().startsWith(q)) return 80;
  if (f.title.toLowerCase().contains(q)) return 60;
  if (f.keywords.any((String k) => k.toLowerCase().contains(q))) return 40;
  if (f.category.title.toLowerCase().contains(q)) return 30;
  if (f.summary.toLowerCase().contains(q)) return 20;
  return 0;
}
