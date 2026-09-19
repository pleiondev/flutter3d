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
  Feature(
    id: 'punctual-lights',
    title: 'Directional, point and spot lights',
    category: Category.shading,
    summary:
        'The three light shapes that leave a single point, so the direction '
        'to them is one vector and the falloff is glTF\'s own attenuation.',
    since: '0.2.0',
    evidence:
        'Cascaded directional shadows, cube shadows for point and spot '
        'lights into an atlas',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/light_node.dart',
    ],
  ),
  Feature(
    id: 'area-lights',
    title: 'Rectangle area lights',
    category: Category.shading,
    summary:
        'A rectangle with width and height, so an interior reads as lit by a '
        'window instead of by a bright dot behind one.',
    since: '0.7.0',
    evidence: '`LightType.area`, `Photometric`, masked shadow casters',
    keywords: <String>['lighttype.area'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/light_node.dart',
    ],
  ),
  Feature(
    id: 'photometric-units',
    title: 'Lights in lumens and lux',
    category: Category.shading,
    summary:
        'A lamp off a datasheet, in lumens or lux, converted into the '
        'engine\'s own light intensity instead of tuned by eye.',
    since: '0.7.0',
    evidence: '`Photometric`, masked shadow casters',
    keywords: <String>['photometric'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/light_node.dart',
    ],
  ),
  Feature(
    id: 'light-channels',
    title: 'Light channels',
    category: Category.shading,
    summary:
        'A bit mask a light and an object meet on: a light reaches an object '
        'only when they share a bit.',
    since: '0.7.0',
    evidence: '`LightNode.channels` against',
    keywords: <String>['lightnode.channels'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/light_node.dart',
      'packages/flutter3d_core/lib/src/engine/scene/light_buffer.dart',
    ],
  ),
  Feature(
    id: 'many-lights',
    title: 'Thirty-two lights and the fade band',
    category: Category.shading,
    summary:
        'Eight lights in the shader\'s own slots and twenty-four more '
        'through a light list, with a ramp instead of a cliff where the '
        'list ends.',
    since: '0.7.0',
    evidence:
        'Up to thirty-two lights on one draw, the last twenty-four without '
        'shadows, `lightFadeBand`',
    keywords: <String>['thirty-two lights'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/light_buffer.dart',
      'packages/flutter3d_core/lib/src/engine/render/renderer_light_list.dart',
    ],
  ),
  Feature(
    id: 'ambient-light',
    title: 'Ambient light',
    category: Category.shading,
    summary:
        'The flat colour and strength a surface falls back to wherever no '
        'direct light reaches it.',
    since: '0.4.3',
    evidence:
        '`Scene.ambientIntensity`, which the sky environment shares with '
        'the flat',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/scene.dart',
    ],
  ),
  Feature(
    id: 'fmat-files',
    title: '.fmat material files',
    category: Category.shading,
    summary:
        'A material as a file of its own: an artist\'s unit of work, worn by '
        'every mesh that shares the look.',
    since: '0.3.0',
    evidence: 'a material as a file of its own, with `MaterialDecoder`',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/fmat/fmat.dart',
      'packages/flutter3d_core/lib/src/formats/material_document.dart',
    ],
  ),
  Feature(
    id: 'material-language',
    title: 'The material expression language',
    category: Category.shading,
    summary:
        'A small GLSL-flavoured source, parsed once into a tree that either '
        'emits a fragment shader or is evaluated directly.',
    since: '0.7.0',
    evidence: 'a material source language behind',
    keywords: <String>['material source language'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/material_language/material_parser.dart',
      'packages/flutter3d_core/lib/src/formats/material_language/material_eval.dart',
      'packages/flutter3d_core/lib/src/formats/material_language/material_glsl.dart',
    ],
  ),
];
