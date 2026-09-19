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
  Feature(
    id: 'animation-layers',
    title: 'Layers and masks',
    category: Category.animation,
    summary:
        'A second clip over part of a skeleton, while the base keeps '
        'playing over the rest of it.',
    since: '0.5.2',
    evidence:
        'Animation layers: a clip over part of a skeleton while the base '
        'plays over all of it.',
    keywords: <String>['AnimationLayer', 'AnimationMask'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/animation/animation_layer.dart',
      'packages/flutter3d_core/lib/src/formats/animation/animation_mask.dart',
    ],
  ),
  Feature(
    id: 'additive-blend',
    title: 'Additive layers',
    category: Category.animation,
    summary:
        'A layer that adds its own clip\'s distance from its rest frame on '
        'top of the base, instead of replacing the base outright.',
    since: '0.7.0',
    evidence: '`AnimationPlayer.rootMotionDelta` and additive layers',
    keywords: <String>['AnimationBlend.additive', 'referenceTime'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/animation/animation_layer.dart',
      'packages/flutter3d_core/lib/src/formats/animation/animation_clip.dart',
    ],
  ),
  Feature(
    id: 'root-motion',
    title: 'Root motion',
    category: Category.animation,
    summary:
        'The forward step a walk cycle already had, extracted out of its '
        'own track and handed back a frame at a time.',
    since: '0.7.0',
    evidence: '`AnimationPlayer.rootMotionDelta`',
    keywords: <String>['kRootMotionExtra', 'flutter3dRootMotion'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/animation/animation_player.dart',
    ],
  ),
  Feature(
    id: 'two-bone-ik',
    title: 'Two-bone IK',
    category: Category.animation,
    summary:
        'An arm or a leg bent so its tip reaches a point, solved on a pose '
        'with no scene behind it.',
    since: '0.7.0',
    evidence: '`TwoBoneIk` and `FabrikIk` with no scene behind them',
    keywords: <String>['no scene behind them'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/animation/inverse_kinematics.dart',
    ],
  ),
  Feature(
    id: 'fabrik-ik',
    title: 'A chain of any length',
    category: Category.animation,
    summary:
        'A rope or a tail bent to reach a point, solved by walking the '
        'chain backward and forward until it does.',
    since: '0.7.0',
    evidence: '`TwoBoneIk` and `FabrikIk` with no scene behind them',
    keywords: <String>['FABRIK', 'Aristidou'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/animation/inverse_kinematics.dart',
    ],
  ),
];
