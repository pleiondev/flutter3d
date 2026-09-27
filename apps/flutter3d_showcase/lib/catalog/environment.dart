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
    id: 'clustered-lights',
    title: 'Clustered lights',
    category: Category.environment,
    summary:
        'The view is cut into small cells that each list the lights reaching '
        'them, so one floor under sixty-four lamps is lit by all of them.',
    since: '0.8.0',
    evidence: 'Clustered lights.',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['clusteredLights', 'clustered lights'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/render_settings.dart',
      'packages/flutter3d_core/lib/src/engine/render/light_clusters.dart',
    ],
  ),
  Feature(
    id: 'volumetric-fog',
    title: 'Volumetric fog',
    category: Category.environment,
    summary:
        'Air that the lights shine through, so each lamp glows in the haze '
        'around it and the air thins out with height.',
    since: '0.8.0',
    evidence: 'Volumetric fog.',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['VolumetricFogSettings', 'volumetric fog'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/render_settings.dart',
      'packages/flutter3d_core/lib/src/engine/render/renderer_fog_pass.dart',
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
  Feature(
    id: 'reflection-probes',
    title: 'Reflection probes',
    category: Category.environment,
    summary:
        'A mirror finish that shows the room it stands in: the scene '
        'captured into a cube from one point and blurred once per '
        'roughness on the device.',
    since: '0.4.3',
    evidence: 'Reflection probes',
    keywords: <String>['reflectionprobenode'],
    needs: <Need>{Need.cubeTextures, Need.renderToMip},
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/reflection_probe_node.dart',
      'packages/flutter3d_core/lib/src/engine/render/renderer_probe_pass.dart',
    ],
  ),
  Feature(
    id: 'irradiance-field',
    title: 'One bounce of diffuse light',
    category: Category.environment,
    summary:
        'A grid of probes, each filled by casting rays out from it and '
        'recording what colour comes back, so a red wall tints the light '
        'reaching what faces it.',
    since: '0.7.0',
    evidence: '`IrradianceField` for one bounce of diffuse light',
    keywords: <String>['irradiancefield'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/irradiance_field.dart',
      'packages/flutter3d_core/lib/src/engine/scene/irradiance_gather.dart',
    ],
    changes: <Change>[
      Change(
        version: '0.8.0',
        note:
            'Each pixel reads the eight probes around it, weighed by facing and by a visibility test, and the light is no longer scaled by the ambient strength twice.',
        evidence: 'An `IrradianceField` is read at every pixel.',
      ),
    ],
  ),
  Feature(
    id: 'irradiance-updates',
    title: 'The field kept current',
    category: Category.environment,
    summary:
        'The renderer looks at the room again from a few probes each frame, '
        'so the bounced light follows a wall that changes colour.',
    since: '0.8.0',
    evidence: 'The irradiance field can update on the GPU.',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['gpuUpdates'],
    needs: <Need>{Need.cubeTextures},
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/irradiance_field.dart',
      'packages/flutter3d_core/lib/src/engine/render/renderer_irradiance_pass.dart',
    ],
  ),
  Feature(
    id: 'lightmaps',
    title: 'Lightmaps',
    category: Category.environment,
    summary:
        'Indirect light baked into a texture ahead of time and read '
        'through a second coordinate the vertex colour carries.',
    since: '0.4.2',
    evidence:
        '`MeshNode.lightmapped` picks a vertex stage that reads the '
        'colour attribute as a place in `Material.lightmap`',
    keywords: <String>['lightmapped'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/mesh_node.dart',
      'packages/flutter3d_core/lib/src/engine/render/material.dart',
      'packages/flutter3d_shaders/shaders/mesh_lightmapped.vert',
    ],
  ),
];
