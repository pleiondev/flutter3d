/// The pages of the `environment` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> environmentFeatures = <Feature>[
  Feature(
    id: 'procedural-sky',
    title: 'Procedural sky',
    category: Category.environment,
    summary:
        'A sky with a gradient, a glow and a sun disc, drawn from a few '
        'numbers with no image to load.',
    since: '0.2.0',
    evidence: 'a sky and two-colour ambient light',
    keywords: <String>['sun disc', 'sky settings'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/sky_settings.dart',
      'packages/flutter3d_core/lib/src/engine/scene/sky_gradient.dart',
      'packages/flutter3d_core/lib/src/engine/scene/sky.dart',
    ],
  ),
  Feature(
    id: 'distance-fog',
    title: 'Distance fog',
    category: Category.environment,
    summary:
        'Things farther from the eye fade toward one colour, so a long '
        'view has depth and its far end has no hard edge.',
    since: '0.5.1',
    evidence:
        'a custom lit shader declaring `FogInfo` has to declare the new '
        '`forward` member',
    keywords: <String>['foginfo'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/render_settings.dart',
    ],
  ),
  Feature(
    id: 'image-based-lighting',
    title: 'Image-based lighting',
    category: Category.environment,
    summary:
        'Light from the surroundings instead of a lamp: a cube map blurred '
        'once per roughness, so a mirror and a matte wall read the same '
        'picture at different sharpness.',
    since: '0.3.0',
    evidence: 'Image-based lighting: `EnvironmentMap.prefilter` builds',
    keywords: <String>['environmentmap', 'prefilter'],
    needs: <Need>{Need.cubeTextures},
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/environment_map.dart',
    ],
  ),
];
