/// The pages of the `flame` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> flameFeatures = <Feature>[
  Feature(
    id: 'flame-overview',
    title: 'Two engines, one Stack',
    category: Category.flame,
    summary:
        'The Flame and flutter3d layers composited in one widget, nothing '
        'bridged between them yet.',
    since: '0.7.0',
    evidence: 'composites the two in one',
    evidenceFile: 'packages/flame_flutter3d/CHANGELOG.md',
    packages: <String>['flame_flutter3d'],
  ),
  Feature(
    id: 'flame-transform-bridge',
    title: 'Keeping a Flame position and a flutter3d node in step',
    category: Category.flame,
    summary:
        'A Flame component and a flutter3d node kept at the same place, '
        'either side free to be the one that moves.',
    since: '0.7.0',
    evidence: 'the same place on one',
    evidenceFile: 'packages/flame_flutter3d/CHANGELOG.md',
    packages: <String>['flame_flutter3d'],
  ),
  Feature(
    id: 'flame-ecs-bridge',
    title: 'Bridging a flutter3d_sim actor',
    category: Category.flame,
    summary:
        'A simulated actor\'s own body driving a Flame position and the mesh '
        'that follows it.',
    since: '0.7.0',
    evidence: 'own position across the same seam',
    evidenceFile: 'packages/flame_flutter3d/CHANGELOG.md',
    packages: <String>['flame_flutter3d', 'flutter3d_sim'],
  ),
  Feature(
    id: 'flame-physics-bridge',
    title: 'Bridging a falling rigid body and its collision',
    category: Category.flame,
    summary:
        'A physics body falling through a real collision world, its contact '
        'with the floor relayed as a Flame collision callback.',
    since: '0.7.0',
    evidence: "re-fires flutter3d's collision events as flame's own",
    evidenceFile: 'packages/flame_flutter3d/CHANGELOG.md',
    packages: <String>['flame_flutter3d', 'flutter3d_physics'],
  ),
  Feature(
    id: 'flame-input-bridge',
    title: 'One key, read by both engines',
    category: Category.flame,
    summary:
        'A Flame key event translated into the same Bindings/InputState a '
        'native flutter3d_game reads.',
    since: '0.7.0',
    evidence:
        'one rebinding UI and one saved binding file, not two input models',
    evidenceFile: 'packages/flame_flutter3d/CHANGELOG.md',
    packages: <String>['flame_flutter3d', 'flutter3d_game'],
  ),
  Feature(
    id: 'flame-camera-bridge',
    title: 'Reconciling an orthographic camera and a Flame viewfinder',
    category: Category.flame,
    summary:
        'A flutter3d camera and a Flame viewfinder framed the same, either '
        'side free to lead.',
    since: '0.7.0',
    evidence:
        "keeps an orthographic flutter3d camera and flame's own 2d "
        'viewfinder framed the same',
    evidenceFile: 'packages/flame_flutter3d/CHANGELOG.md',
    packages: <String>['flame_flutter3d'],
  ),
];
