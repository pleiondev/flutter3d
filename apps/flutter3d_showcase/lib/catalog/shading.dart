/// The pages of the `shading` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> shadingFeatures = <Feature>[
  Feature(
    id: 'pbr-lighting',
    title: 'PBR metal and rough',
    category: Category.shading,
    summary:
        'One material, two numbers, how metallic and how rough, and the light '
        'does the rest.',
    since: '0.1.0',
    evidence: 'Six lighting models, each a pre-built shader',
    keywords: <String>['pbr', 'metallic', 'roughness', 'physically based'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/material.dart',
    ],
  ),
];
