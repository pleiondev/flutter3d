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
    id: 'procedural-levels',
    title: 'Levels from a seed',
    category: Category.simAudioXr,
    summary:
        'Rooms and corridors laid out from a seed and a few rules, the player '
        'in one room and the exit in the farthest, and refused unless the '
        'exit can be walked to.',
    since: '1.0.0-rc.1',
    evidence: 'Levels from a seed and some rules (N11).',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['generateLevel', 'ExitReachable'],
    packages: <String>['flutter3d_sim'],
    engineFiles: <String>[
      'packages/flutter3d_sim/lib/src/procgen/generate_level.dart',
      'packages/flutter3d_sim/lib/src/procgen/wfc.dart',
      'packages/flutter3d_sim/lib/src/procgen/exit_reachable.dart',
    ],
  ),
  Feature(
    id: 'voxel-world',
    title: 'A world of blocks',
    category: Category.simAudioXr,
    summary:
        'Ground of blocks drawn from a seed, dug into and built on, each edit '
        'meshing its chunk again and replacing its collision boxes, and a '
        'save that holds only the edits.',
    since: '1.0.0-rc.1',
    evidence: 'A world of blocks, kept as a seed and the edits since.',
    evidenceFile: 'packages/flutter3d_voxel/CHANGELOG.md',
    keywords: <String>['VoxelWorld'],
    packages: <String>['flutter3d_voxel'],
    engineFiles: <String>[
      'packages/flutter3d_voxel/lib/src/voxel_world.dart',
      'packages/flutter3d_voxel/lib/src/voxel_mesher.dart',
      'packages/flutter3d_voxel/lib/src/voxel_collision.dart',
    ],
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
  Feature(
    id: 'level-mechanisms',
    title: 'Doors, lifts and buttons',
    category: Category.simAudioXr,
    summary:
        'One machine that travels between two places, and a switch that '
        'relays an activation to it by name.',
    since: '0.4.0',
    approximate: true,
    evidence: 'no explicit origin',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['world logic'],
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'light-fixtures',
    title: 'Flickering lights',
    category: Category.simAudioXr,
    summary:
        'A light that flickers like fire or pulses like something magical, '
        'with one brightness number driving both the glow and the light.',
    since: '0.4.0',
    approximate: true,
    evidence: 'no explicit origin',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['world logic'],
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'actors',
    title: 'Actors, brains and health',
    category: Category.simAudioXr,
    summary:
        'A thin handle onto an entity\'s components: health that can run '
        'out, and a brain a game writes for itself.',
    since: '0.4.0',
    approximate: true,
    evidence: 'no explicit origin',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['world logic'],
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'camera-shake',
    title: 'The shared camera rig',
    category: Category.simAudioXr,
    summary:
        'Easing towards where a chasing view should be, carrying a knock or '
        'a shake that fades, and staying out of the walls.',
    since: '0.4.0',
    approximate: true,
    evidence: 'no explicit origin',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['camera rig'],
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'splines',
    title: 'A Catmull-Rom path',
    category: Category.simAudioXr,
    summary:
        'A smooth closed curve through a list of points, measured once so '
        'everything after that can ask for a point by distance in metres.',
    since: '0.4.0',
    approximate: true,
    evidence: 'no explicit origin',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['the maths'],
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'difficulty',
    title: 'Difficulty axes',
    category: Category.simAudioXr,
    summary:
        'Four numbers a genre applies where it decides, instead of a name it '
        'has to interpret.',
    since: '0.5.0',
    evidence: 'four axes a genre applies where it decides',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'positional-audio',
    title: 'Positional audio',
    category: Category.simAudioXr,
    summary:
        'A sound placed in the world, heard louder or softer and panned '
        'left or right depending on the listener\'s position and facing.',
    since: '0.1.0',
    evidence: 'Positional audio: attenuation, panning and voice limiting',
    evidenceFile: 'packages/flutter3d_audio/CHANGELOG.md',
    packages: <String>['flutter3d_audio'],
  ),
  Feature(
    id: 'audio-rolloff',
    title: 'Distance rolloff',
    category: Category.simAudioXr,
    summary:
        'Three curves for how a sound gets quieter with distance, and a '
        'shared distance past which it is silent.',
    since: '0.1.0',
    evidence: 'attenuation',
    evidenceFile: 'packages/flutter3d_audio/CHANGELOG.md',
    packages: <String>['flutter3d_audio'],
  ),
  Feature(
    id: 'audio-buses',
    title: 'Mixer buses',
    category: Category.simAudioXr,
    summary:
        'A group of sounds a player can turn down as one, read against a '
        'shared master every frame.',
    since: '0.2.0',
    evidence: 'Mix buses opened like',
    evidenceFile: 'packages/flutter3d_audio/CHANGELOG.md',
    packages: <String>['flutter3d_audio'],
  ),
  Feature(
    id: 'voice-limit',
    title: 'Voice limiting',
    category: Category.simAudioXr,
    summary:
        'How many sounds may play at once, and which ones win when more '
        'than that are asking to be heard.',
    since: '0.1.0',
    evidence: 'voice limiting',
    evidenceFile: 'packages/flutter3d_audio/CHANGELOG.md',
    packages: <String>['flutter3d_audio'],
  ),
  Feature(
    id: 'audio-occlusion',
    title: 'Occlusion',
    category: Category.simAudioXr,
    summary:
        'What the world does to a sound between there and here, as a '
        'callback the scene asks and never a wall test of its own.',
    since: '0.1.0',
    approximate: true,
    evidence: 'no explicit origin',
    evidenceFile: 'packages/flutter3d_audio/CHANGELOG.md',
    keywords: <String>['attenuation'],
    packages: <String>['flutter3d_audio'],
  ),
  Feature(
    id: 'blended-engine-loop',
    title: 'A blended engine loop',
    category: Category.simAudioXr,
    summary:
        'Several loops of the same engine, recorded at different revs, '
        'crossfaded by one number so the seams do not show.',
    since: '0.1.0',
    approximate: true,
    evidence: 'no explicit origin',
    evidenceFile: 'packages/flutter3d_audio/CHANGELOG.md',
    keywords: <String>['attenuation'],
    packages: <String>['flutter3d_audio'],
  ),
  Feature(
    id: 'pendulum-lab',
    title: 'The virtual pendulum lab',
    category: Category.simAudioXr,
    summary:
        'A worked example small enough that one changed number visibly '
        'changes a run, and a digest that finds exactly where two runs part.',
    since: '0.7.0',
    evidence: 'is a damped pendulum stepped with',
    evidenceFile:
        'packages/flutter3d_education/doc/changelogs/flutter3d_lab.md',
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'stereo-rig',
    title: 'The stereo rig',
    category: Category.simAudioXr,
    summary:
        'Two cameras under a head, under a stage the application moves, '
        'drawn side by side into one frame.',
    since: '0.1.0',
    evidence: 'places two eyes under a head under a stage',
    evidenceFile: 'packages/flutter3d_stereo/CHANGELOG.md',
    packages: <String>['flutter3d_stereo'],
  ),
  Feature(
    id: 'viewer-profiles',
    title: 'Cardboard viewer profiles',
    category: Category.simAudioXr,
    summary:
        'The numbers a folded holder and a moulded one differ by, turned '
        'into an off-centre frustum per eye.',
    since: '0.1.0',
    evidence: 'carries the numbers holders differ by',
    evidenceFile: 'packages/flutter3d_stereo/CHANGELOG.md',
    packages: <String>['flutter3d_stereo'],
  ),
  Feature(
    id: 'stereo-lesson',
    title: 'A lesson through the rig',
    category: Category.simAudioXr,
    summary:
        'The same lesson document a step panel authors, played back through '
        'a stereo rig with a button instead of a keyboard.',
    since: '0.7.0',
    evidence: 'holds which step of an',
    evidenceFile: 'packages/flutter3d_stereo/CHANGELOG.md',
    packages: <String>['flutter3d_stereo', 'flutter3d_sim'],
  ),
  Feature(
    id: 'head-tracking',
    title: 'Head tracking',
    category: Category.simAudioXr,
    summary:
        'A pose that says which way the head is turned, fed to the rig '
        'every frame, from a sensor or from a mouse-driven stand-in.',
    since: '0.1.0',
    evidence: "points the head with the device's own rotation sensor",
    evidenceFile: 'packages/flutter3d_stereo/CHANGELOG.md',
    packages: <String>['flutter3d_stereo'],
  ),
  Feature(
    id: 'replay-tests',
    title: 'Replays as tests',
    category: Category.simAudioXr,
    summary:
        'A recorded run played back with no screen, its digests checked at the steps it took them, so a change to the game fails at the step it first shows.',
    since: '1.0.0-rc.1',
    evidence: 'turns a recorded run into a test that needs no GPU',
    evidenceFile: 'packages/flutter3d_testing/CHANGELOG.md',
    packages: <String>['flutter3d_sim'],
  ),
  Feature(
    id: 'navmesh-crowds',
    title: 'Navigation meshes and crowds',
    category: Category.simAudioXr,
    summary:
        'A level baked into convex polygons, a route round a wall pulled tight by the funnel, a jump onto a ledge, a broken wall baked again by its tiles, and a crowd that never touches.',
    since: '1.0.0-rc.1',
    evidence: 'A level bakes into a navigation mesh as well as a grid.',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['NavMesh', 'Avoidance'],
    packages: <String>['flutter3d_sim'],
    engineFiles: <String>[
      'packages/flutter3d_sim/lib/src/nav/navmesh/navmesh.dart',
      'packages/flutter3d_sim/lib/src/nav/navmesh/route.dart',
      'packages/flutter3d_sim/lib/src/nav/navmesh/mesh_links.dart',
      'packages/flutter3d_sim/lib/src/nav/avoidance.dart',
    ],
  ),
  Feature(
    id: 'behaviour-trees',
    title: 'Behaviour trees',
    category: Category.simAudioXr,
    summary:
        'A guard\'s mind read from JSON: patrol until the target comes into sight, then chase, with the path the tree took drawn over it.',
    since: '1.0.0-rc.1',
    evidence: 'Behaviour trees and utility choices as data.',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['BehaviourTree', 'Blackboard', 'BehaviourOverlay'],
    packages: <String>['flutter3d_sim', 'flutter3d_game'],
    engineFiles: <String>[
      'packages/flutter3d_sim/lib/src/actors/behaviour_tree.dart',
      'packages/flutter3d_sim/lib/src/actors/behaviour_kinds.dart',
      'packages/flutter3d_sim/lib/src/actors/behaviour_brain.dart',
      'packages/flutter3d_game/lib/src/visuals/behaviour_overlay.dart',
    ],
  ),
  Feature(
    id: 'cutscenes',
    title: 'Cutscenes',
    category: Category.simAudioXr,
    summary:
        'A scene written as a document: a camera on a curve, subtitles, a fade and signals the game answers, played in the fixed step and skipped to the same end.',
    since: '1.0.0-rc.1',
    evidence: 'A cutscene is a document played in the fixed step.',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['SequencePlayer'],
    packages: <String>['flutter3d_sim'],
    engineFiles: <String>[
      'packages/flutter3d_sim/lib/src/cinema/sequence.dart',
      'packages/flutter3d_sim/lib/src/cinema/sequence_player.dart',
    ],
  ),
  Feature(
    id: 'sharing-ghosts',
    title: 'Sharing runs and racing ghosts',
    category: Category.simAudioXr,
    summary:
        'A level and a run through it filed behind a short code, refused when the run is for another version of the level, and played again as a ghost to race.',
    since: '1.0.0-rc.1',
    evidence: 'A level can be shared behind a short code.',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['ShareBundle', 'RunService'],
    packages: <String>['flutter3d_sim'],
    engineFiles: <String>[
      'packages/flutter3d_sim/lib/src/share/share_bundle.dart',
      'packages/flutter3d_sim/lib/src/share/run_service.dart',
    ],
  ),
  Feature(
    id: 'terrain-erosion',
    title: 'Terrain erosion',
    category: Category.simAudioXr,
    summary:
        'One hill before and after scree has slid off it and rain has run down it, with none of the ground lost.',
    since: '1.0.0-rc.1',
    evidence:
        '`erodeThermally` and `erodeHydraulically` shape a `Heightfield`.',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['erodeThermally', 'erodeHydraulically'],
    packages: <String>['flutter3d_sim'],
    engineFiles: <String>[
      'packages/flutter3d_sim/lib/src/procgen/erosion.dart',
    ],
  ),
  Feature(
    id: 'playtest-heatmaps',
    title: 'Playtest heatmaps',
    category: Category.simAudioXr,
    summary:
        'Recorded runs played again through the same simulation, and where they went and where they were lost drawn over the level.',
    since: '1.0.0-rc.1',
    evidence: 'bins trails into cells, counting samples and distinct runs',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    keywords: <String>['resimulate', 'Heatmap'],
    packages: <String>['flutter3d_sim'],
    engineFiles: <String>[
      'packages/flutter3d_sim/lib/src/telemetry/resimulation.dart',
      'packages/flutter3d_sim/lib/src/telemetry/heatmap.dart',
    ],
  ),
];
