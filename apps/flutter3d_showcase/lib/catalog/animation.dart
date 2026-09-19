/// The pages of the `animation` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> animationFeatures = <Feature>[
  Feature(
    id: 'skinning',
    title: 'Skinned meshes',
    category: Category.animation,
    summary:
        'A mesh whose vertices follow a chain of joints, blended smoothly '
        'where two joints share a vertex.',
    since: '0.1.0',
    evidence: 'skinning, animation',
    keywords: <String>['skinning'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/skeleton.dart',
      'packages/flutter3d_core/lib/src/engine/animation/skin_blend.dart',
    ],
  ),
  Feature(
    id: 'clip-playback',
    title: 'Clips and crossfades',
    category: Category.animation,
    summary:
        'A player that plays one clip, fades smoothly to another, and '
        'answers to a speed and a wrap mode.',
    since: '0.1.0',
    evidence: 'animation',
    keywords: <String>['AnimationPlayer', 'crossFadeTo'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/animation/animation_player.dart',
    ],
  ),
  Feature(
    id: 'interpolation',
    title: 'Step, linear and cubic tracks',
    category: Category.animation,
    summary:
        'The same keyframes read three ways: a snap, a straight line and a '
        'curve with tangents.',
    since: '0.7.0',
    evidence: 'three interpolations',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['AnimationInterpolation', 'cubic spline'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/animation/animation_track.dart',
    ],
  ),
  Feature(
    id: 'morph-targets',
    title: 'Morph targets',
    category: Category.animation,
    summary:
        'A shape a mesh can blend towards, packed as a texture and dialled '
        'in by a weight from nought to one.',
    since: '0.5.2',
    evidence: 'Morph targets are drawn, on the GPU, on all three backends',
    keywords: <String>['morph target', 'MorphTexture'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/morph_state.dart',
      'packages/flutter3d_core/lib/src/geometry/morph_texture.dart',
    ],
  ),
  Feature(
    id: 'instanced-morphs',
    title: 'A face per copy',
    category: Category.animation,
    summary:
        'One batched draw where every copy wears its own morph weights '
        'instead of the one shape a uniform would give them all.',
    since: '0.5.2',
    evidence: 'A batch can wear a face per copy',
    keywords: <String>['setMorphWeights'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/instanced_mesh_node.dart',
    ],
  ),
];
