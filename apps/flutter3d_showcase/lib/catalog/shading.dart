/// The pages of the `shading` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> shadingFeatures = <Feature>[
  Feature(
    id: 'lighting-models',
    title: 'The six lighting models',
    category: Category.shading,
    summary:
        'Unlit, Lambert, Blinn-Phong, PBR, Toon and Normals: one material '
        'field picks how a surface answers light.',
    since: '0.1.0',
    evidence: 'Six lighting models, each a pre-built shader',
    keywords: <String>['lighting model'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/lighting_model.dart',
    ],
  ),
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
    id: 'normal-mapping',
    title: 'Normal maps',
    category: Category.shading,
    summary:
        'Fine relief stored in a texture, so a smooth surface catches light '
        'like a bumpy one.',
    since: '0.1.0',
    approximate: true,
    evidence:
        'no explicit origin: no CHANGELOG names `Material.normal` or '
        '`normalScale`. The nearest the record comes is the six lighting '
        'models a normal map shades against, which is the shading system '
        'this belongs to and the earliest version it could have arrived in.',
    keywords: <String>['lighting model'],
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
    since: '0.1.0',
    approximate: true,
    evidence:
        'no explicit origin: no CHANGELOG names `drawBucket`, `depthWrite`, '
        '`depthCompare` or `backfaceCulling`. The nearest the record comes is '
        'the six lighting models the same `Material` and render pipeline '
        'carry, the earliest version this draw state could have arrived in.',
    keywords: <String>['lighting model'],
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
  Feature(
    id: 'specular-scale',
    title: 'Specular strength',
    category: Category.shading,
    summary:
        'One scalar turns the whole frame\'s specular response up or down '
        'without touching a single material.',
    since: '0.1.0',
    approximate: true,
    evidence:
        'no explicit origin: no CHANGELOG names `RenderSettings.specular`. '
        'The nearest the record comes is the HDR pipeline with tone mapping '
        'that `RenderSettings` has carried since the beginning, which is the '
        'earliest version this scene-wide knob could have arrived in.',
    keywords: <String>['tone mapping'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/render_settings.dart',
    ],
  ),
  Feature(
    id: 'exposure',
    title: 'Manual exposure',
    category: Category.shading,
    summary:
        'The linear multiplier the composite applies before the tone curve, '
        'set by hand instead of metered.',
    since: '0.1.0',
    approximate: true,
    evidence:
        'no explicit origin: no CHANGELOG names `RenderSettings.exposure`. '
        'Every mention of exposure is the later auto-exposure meter, which '
        'reads this field rather than introducing it. The nearest the record '
        'comes is the HDR pipeline with tone mapping this scalar feeds, '
        'which is the earliest version it could have arrived in.',
    keywords: <String>['tone mapping'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/render_settings.dart',
    ],
  ),
  Feature(
    id: 'wireframe',
    title: 'Wireframe',
    category: Category.shading,
    summary:
        'Draws the scene\'s triangles as lines, on the one backend that has a '
        'polygon mode for it.',
    since: '0.1.0',
    approximate: true,
    evidence:
        'no explicit origin: no CHANGELOG names `RenderSettings.wireframe` '
        'or `FrameResult.wireframeDeclined`. The nearest the record comes is '
        'the HDR pipeline with tone mapping that `RenderSettings` has '
        'carried since the beginning, which is the earliest version this '
        'setting could have arrived in.',
    keywords: <String>['tone mapping'],
    needs: <Need>{Need.wireframe},
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/render_settings.dart',
      'packages/flutter3d_core/lib/src/engine/render/frame_result.dart',
    ],
  ),
  Feature(
    id: 'draw-batching',
    title: 'Identical-draw batching',
    category: Category.shading,
    summary:
        'A run of nodes sharing a mesh and a material collapses into one '
        'instanced call instead of one draw each.',
    since: '0.7.0',
    evidence: '`RenderSettings.batchIdenticalDraws`',
    keywords: <String>['batchidenticaldraws'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/render_settings.dart',
      'packages/flutter3d_core/lib/src/engine/render/renderer_batch.dart',
    ],
  ),
];
