/// The pages of the `sim_audio_xr` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> simAudioXrFeatures = <Feature>[
  Feature(
    id: 'fixed-step',
    title: 'Fixed step and interpolation',
    category: Category.simAudioXr,
    summary:
        'A simulation that always advances by the same amount, smoothed for '
        'a screen that draws at a different rate.',
    since: '0.4.0',
    approximate: true,
    evidence: 'no explicit origin',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['fixed step'],
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'ecs-world',
    title: 'The ECS world',
    category: Category.simAudioXr,
    summary:
        'Entities and components, saved as one document and carried '
        'across a level that has since been edited.',
    since: '0.7.0',
    evidence: 'save across an edited level',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['EcsWorld'],
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'step-systems',
    title: 'Systems and events',
    category: Category.simAudioXr,
    summary:
        'Work a game hangs off a fixed step it does not own, run in a stated '
        'order, and the events a step reports for a frame to read.',
    since: '0.5.0',
    evidence: 'what a step did, drained by whoever owns it',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'replay-digest',
    title: 'Replays and digests',
    category: Category.simAudioXr,
    summary:
        'A checkpoint trace that names the first step two runs of the same '
        'tape stop agreeing at.',
    since: '0.7.0',
    evidence:
        'a replay can be compared checkpoint by checkpoint against the run '
        'it claims to repeat',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'portable-math',
    title: 'Portable determinism',
    category: Category.simAudioXr,
    summary:
        'Transcendental functions and a random generator that give the same '
        'bits on every platform, and a random state a snapshot can carry.',
    since: '0.5.1',
    evidence: 'so two platforms cannot disagree about them',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'rewind',
    title: 'Rewinding',
    category: Category.simAudioXr,
    summary:
        'The last few seconds of a run, kept as a snapshot a second and the '
        'raw inputs between them, for a kill camera or a rewind mechanic.',
    since: '0.7.0',
    evidence: 'what each step cost, keyed by step number',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'headless-run',
    title: 'Running without a screen',
    category: Category.simAudioXr,
    summary:
        'The interface a tool that plays a game blind is written against: a '
        'step, a save, and a sentence about how things stand.',
    since: '0.7.0',
    evidence: 'because the tools live above the genres',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'nav-grid',
    title: 'Path-finding',
    category: Category.simAudioXr,
    summary:
        'Where an agent can stand, baked once from the level into a lattice '
        'a step can query in one array lookup.',
    since: '0.4.1',
    evidence: 'finds the gaps and ledges a',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'flow-field',
    title: 'A flow field',
    category: Category.simAudioXr,
    summary:
        'One sweep from a goal, read by every agent as the direction to walk '
        'from wherever it stands.',
    since: '0.4.1',
    approximate: true,
    evidence: 'no explicit origin',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['FlowField'],
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'automap',
    title: 'An automap',
    category: Category.simAudioXr,
    summary:
        'The level as the player has seen it, floor where they walked and '
        'walls where it stopped, built over the same grid the monsters use.',
    since: '0.4.1',
    approximate: true,
    evidence: 'no explicit origin',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['NavGrid'],
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'lightmap-bake',
    title: 'Baking a lightmap',
    category: Category.simAudioXr,
    summary:
        'Unwrapping a level\'s brush faces onto an atlas, then gathering the '
        'light the walls throw on each other into it.',
    since: '0.4.1',
    evidence: 'unwraps every visible brush face onto a',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'baked-visibility',
    title: 'Baked visibility',
    category: Category.simAudioXr,
    summary:
        'Which parts of a brush level can be seen from where, baked once and '
        'applied every frame by hiding what the eye cannot see.',
    since: '0.7.0',
    evidence: 'VisibilityCuller',
    evidenceFile: 'packages/flutter3d_app/CHANGELOG.md',
    packages: <String>['flutter3d_sim', 'flutter3d_app'],
  ),
  Feature(
    id: 'terrain-tiles',
    title: 'Terrain in tiles',
    category: Category.simAudioXr,
    summary:
        'Ground cut into tiles buildable at more than one resolution, and a '
        'level chosen by distance, with a skirt closing the seam.',
    since: '0.7.0',
    evidence: 'Ground in tiles, at a level of detail chosen by distance',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'level-format',
    title: 'The level format',
    category: Category.simAudioXr,
    summary:
        'A level as a document: brushes, entities and lights, round-tripped '
        'through JSON and checked by a validator before anyone plays it.',
    since: '0.4.2',
    evidence: 'A brush can say how it casts, not only whether',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    packages: <String>['flutter3d_sim'],
  ),
];
