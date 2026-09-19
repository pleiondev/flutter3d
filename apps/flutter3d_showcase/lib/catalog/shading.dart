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
  Feature(
    id: 'lighting-models',
    title: 'The six lighting models',
    category: Category.shading,
    summary:
        'Unlit, Lambert, Blinn-Phong, PBR, toon and normals: six ways for a '
        'surface to answer the same light.',
    since: '0.1.0',
    evidence: 'Six lighting models, each a pre-built shader',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/lighting_model.dart',
    ],
  ),
  Feature(
    id: 'normal-mapping',
    title: 'Normal maps',
    category: Category.shading,
    summary:
        'Fine relief stored in a texture, so a smooth surface catches light '
        'like a bumpy one.',
    since: '0.5.2',
    evidence: 'a normal map\'s mip chain is real',
    evidenceFile: 'packages/flutter3d_shaders/CHANGELOG.md',
    approximate: true,
    keywords: <String>['normal map'],
    packages: <String>['flutter3d', 'flutter3d_shaders'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/geometry/mesh_tangents.dart',
    ],
  ),
  Feature(
    id: 'alpha-modes',
    title: 'Alpha modes',
    category: Category.shading,
    summary:
        'Opaque, cut-out, blended or hashed: four answers to what a '
        'see-through material should do.',
    since: '0.7.0',
    evidence: '`MaterialAlphaMode.hashed`, a material source language behind',
    keywords: <String>['hashed'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/material.dart',
    ],
  ),
  Feature(
    id: 'draw-state',
    title: 'Draw order and depth state',
    category: Category.shading,
    summary:
        'Draw a surface first, keep it out of the depth buffer, or skip the '
        'backs of triangles.',
    since: '0.4.3',
    evidence: 'where it fails the depth test',
    approximate: true,
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/material.dart',
    ],
  ),
  Feature(
    id: 'texture-filtering',
    title: 'Anisotropic texture filtering',
    category: Category.shading,
    summary:
        'A floor stretching to the horizon keeps its checks sharp instead of '
        'turning into a grey band.',
    since: '0.4.3',
    evidence: '`RenderSettings.anisotropy`',
    keywords: <String>['anisotropy'],
    needs: <Need>{Need.mipmaps},
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/render_settings.dart',
    ],
  ),
];
