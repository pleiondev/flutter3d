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
    changes: <Change>[
      Change(
        version: '0.9.0',
        note:
            'The body falls on whichever physics the run chose, the native core by default, since the step component takes the Dart reference\'s solver and the core\'s alike.',
        evidence: 'steps whichever physics the run chose.',
        evidenceFile: 'packages/flame_flutter3d/CHANGELOG.md',
      ),
    ],
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
  Feature(
    id: 'flame-owned-world',
    title: 'A Flame game that owns its 3D world',
    category: Category.flame,
    summary:
        'A game that builds its own scene, and crates that hear a tap on '
        'what the perspective camera shows of them.',
    since: '0.8.3',
    evidence: 'a flame game owns its 3d world',
    evidenceFile: 'packages/flame_flutter3d/CHANGELOG.md',
    packages: <String>['flame_flutter3d'],
  ),
  Feature(
    id: 'flame-crowd',
    title: 'Eighty sparks in one draw, fire and smoke in two',
    category: Category.flame,
    summary:
        'Flame components drawn through one instanced batch, and particle '
        'pools that add light and take it away.',
    since: '0.8.3',
    evidence: 'draws many small things as one',
    evidenceFile: 'packages/flame_flutter3d/CHANGELOG.md',
    packages: <String>['flame_flutter3d', 'flutter3d_particles'],
  ),
  Feature(
    id: 'flame-seats',
    title: 'Two layouts, and whoever presses first is player one',
    category: Category.flame,
    summary:
        'PlayerSeats over two keyboard layouts read from the keyboard '
        'itself: a layout joins on its own key, in the order people press.',
    since: '0.8.4',
    evidence: 'lets players claim one by pressing, in the order they join',
    evidenceFile: 'packages/flame_flutter3d/CHANGELOG.md',
    packages: <String>['flame_flutter3d', 'flutter3d_game', 'flutter3d_sim'],
  ),
  Feature(
    id: 'flame-horde',
    title: 'Ninety-six monsters in one draw, chasing two players',
    category: Category.flame,
    summary:
        'Simulated actors drawn as slots of one instanced batch, stepped '
        'towards two players at once, each going for the one it can reach.',
    since: '0.8.4',
    evidence: 'draws a simulated actor as a slot of a shared',
    evidenceFile: 'packages/flame_flutter3d/CHANGELOG.md',
    packages: <String>['flame_flutter3d', 'flutter3d_sim'],
  ),
  Feature(
    id: 'flame-level-scene',
    title: 'A level is a scene, and the camera frames the whole party',
    category: Category.flame,
    summary:
        'A Flame game moving from one level\'s scene to the next, and a '
        'camera eased towards a view worked out from four walkers at once.',
    since: '0.8.4',
    evidence: 'moves the game to the next level\'s scene with the camera',
    evidenceFile: 'packages/flame_flutter3d/CHANGELOG.md',
    packages: <String>['flame_flutter3d'],
  ),
];
