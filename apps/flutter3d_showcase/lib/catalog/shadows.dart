/// The pages of the `shadows` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> shadowsFeatures = <Feature>[
  Feature(
    id: 'shadow-settings',
    title: 'Shadow quality',
    category: Category.shadows,
    summary:
        'How big the shadow map is, how much slack it leaves and how dark it '
        'paints, on one page.',
    since: '0.1.0',
    evidence: 'directional shadows',
    keywords: <String>['shadow map'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/shadow_settings.dart',
    ],
  ),
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
  Feature(
    id: 'point-light-shadows',
    title: 'Point and spot shadows',
    category: Category.shadows,
    summary:
        'A lamp or a spotlight throws shadows in every direction it lights, '
        'through a cube map.',
    since: '0.2.0',
    evidence: 'cube shadows for point and spot lights into an atlas',
    keywords: <String>['cube shadow', 'point shadow'],
    needs: <Need>{Need.cubeTextures},
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/shadow_settings.dart',
      'packages/flutter3d_core/lib/src/engine/render/renderer_shadow_pass.dart',
    ],
  ),
  Feature(
    id: 'soft-shadows',
    title: 'Soft shadows',
    category: Category.shadows,
    summary:
        'A shadow that is sharp where it starts and blurs the farther it '
        'travels, like one from a light with a size.',
    since: '0.7.0',
    evidence:
        '`ShadowSettings.directionalLightRadius` for a penumbra that widens '
        'with distance',
    keywords: <String>['penumbra', 'directionalLightRadius'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/shadow_settings.dart',
    ],
  ),
  Feature(
    id: 'contact-shadows',
    title: 'Contact shadows',
    category: Category.shadows,
    summary:
        'A short march toward the sun that darkens the crease where an object '
        'meets the ground.',
    since: '0.7.0',
    evidence: '`ContactShadowSettings`',
    keywords: <String>['ContactShadowSettings', 'contact shadow'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/render_settings.dart',
    ],
  ),
  Feature(
    id: 'static-shadow-cache',
    title: 'The cached shadow map',
    category: Category.shadows,
    summary:
        'Walls that never move are drawn into the lamp\'s shadow map once, so '
        'each frame only redraws what moved.',
    since: '0.3.0',
    evidence:
        'The static cube-shadow bake now redraws when the settings that '
        'decide it change',
    keywords: <String>['static cube-shadow bake'],
    needs: <Need>{Need.cubeTextures},
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/static_bake_key.dart',
    ],
  ),
  Feature(
    id: 'masked-shadow-casters',
    title: 'Shadows of cut-out leaves',
    category: Category.shadows,
    summary:
        'A leaf or a fence with holes in its texture throws a shadow with the '
        'same holes.',
    since: '0.7.0',
    evidence: 'masked shadow casters',
    keywords: <String>['masked shadow'],
    engineFiles: <String>[
      'packages/flutter3d_shaders/shaders/lighting/shadow_depth_masked.frag',
    ],
  ),
];
