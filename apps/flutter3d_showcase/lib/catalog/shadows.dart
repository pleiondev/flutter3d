/// The pages of the `shadows` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> shadowsFeatures = <Feature>[
  Feature(
    id: 'cascaded-shadows',
    title: 'Cascaded shadows',
    category: Category.shadows,
    summary:
        'The sun\'s shadow in slices, so it is sharp near you and still reaches '
        'the horizon.',
    since: '0.2.0',
    evidence: 'Cascaded directional shadows, cube shadows for point and spot',
    keywords: <String>['cascade', 'shadow map', 'sun shadow'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/shadow_settings.dart',
    ],
  ),
];
