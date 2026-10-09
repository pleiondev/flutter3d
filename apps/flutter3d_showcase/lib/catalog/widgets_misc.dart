/// The pages of the `widgets_misc` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> widgetsMiscFeatures = <Feature>[
  Feature(
    id: 'widget-surface',
    title: 'Widgets in the scene',
    category: Category.widgetsMisc,
    summary:
        'A live Flutter widget drawn as a mesh in the scene, redrawn when '
        'the widget changes.',
    since: '0.7.0',
    evidence: 'WidgetSurface',
    evidenceFile: 'packages/flutter3d_app/CHANGELOG.md',
    packages: <String>['flutter3d_app'],
  ),
  Feature(
    id: 'scene-semantics',
    title: 'Describing the scene to a screen reader',
    category: Category.widgetsMisc,
    summary:
        'One accessibility node per object, positioned where the camera '
        'actually projects it, instead of one opaque rectangle.',
    since: '0.7.0',
    evidence: 'describes the scene to a screen reader',
    evidenceFile: 'packages/flutter3d_app/CHANGELOG.md',
    packages: <String>['flutter3d_app'],
  ),
  Feature(
    id: 'scene-surface',
    title: 'The scene surface and its status screens',
    category: Category.widgetsMisc,
    summary:
        'The widget every viewport is built from, and the screen an '
        'application shows when a renderer never opened at all.',
    since: '0.7.0',
    evidence: 'SceneSurface',
    evidenceFile: 'packages/flutter3d_app/CHANGELOG.md',
    packages: <String>['flutter3d_app'],
  ),
  Feature(
    id: 'level-loader',
    title: 'Loading a level',
    category: Category.widgetsMisc,
    summary:
        'The bridge between a level document and something drawable, and a '
        'cache that uploads each repeated shape once.',
    since: '0.7.0',
    evidence: 'LevelLoader',
    evidenceFile: 'packages/flutter3d_app/CHANGELOG.md',
    packages: <String>['flutter3d_app', 'flutter3d_sim'],
  ),
  Feature(
    id: 'storage',
    title: 'Storage on every platform',
    category: Category.widgetsMisc,
    summary:
        'Small documents a player\'s choices live in, kept the right way on '
        'whichever platform is running, and never throwing.',
    since: '0.7.0',
    evidence: 'for a document that is bytes and may be megabytes',
    evidenceFile: 'packages/flutter3d_app/CHANGELOG.md',
    packages: <String>['flutter3d_app'],
  ),
  Feature(
    id: 'diagnostics',
    title: 'Frame timing and memory pressure',
    category: Category.widgetsMisc,
    summary:
        'How long the last frame took, what a window of frames cost, and '
        'giving pooled render targets back when memory runs short.',
    since: '0.7.0',
    evidence: 'FrameClock',
    evidenceFile: 'packages/flutter3d_app/CHANGELOG.md',
    packages: <String>['flutter3d_app'],
  ),
  Feature(
    id: 'accommodations',
    title: 'Reduce motion',
    category: Category.widgetsMisc,
    summary:
        'What the player has already told the operating system, read as a '
        'default for a camera\'s own involuntary movement.',
    since: '0.7.0',
    approximate: true,
    evidence: 'no explicit origin',
    evidenceFile: 'packages/flutter3d_game/CHANGELOG.md',
    keywords: <String>['GameConfig'],
    packages: <String>['flutter3d_game'],
  ),
  Feature(
    id: 'game-settings',
    title: 'Settings, config and saves',
    category: Category.widgetsMisc,
    summary:
        'What a player has changed about how the game behaves for them, and '
        'where a run in progress is kept between launches.',
    since: '0.7.0',
    evidence: 'the settings overlay and panel, rebinding',
    evidenceFile: 'packages/flutter3d_game/CHANGELOG.md',
    packages: <String>['flutter3d_game'],
  ),
  Feature(
    id: 'run-timeline',
    title: 'Pausing and stepping a running game',
    category: Category.widgetsMisc,
    summary:
        'Pause, step one fixed frame at a time, preview a rewind and '
        'release into the past so the run continues from there.',
    since: '0.7.0',
    evidence: 'a running game paused, stepped and rewound from outside',
    evidenceFile: 'packages/flutter3d_game/CHANGELOG.md',
    packages: <String>['flutter3d_game', 'flutter3d_sim'],
  ),
  Feature(
    id: 'rollback-netcode',
    title: 'Rollback netcode over a loopback',
    category: Category.widgetsMisc,
    summary:
        'Two players\' worth of a fixed-step simulation kept in step across '
        'a delayed, lossy connection, with prediction and rollback.',
    since: '0.6.0',
    evidence: 'prediction by the last frame that arrived',
    evidenceFile: 'packages/flutter3d_net/CHANGELOG.md',
    packages: <String>['flutter3d_net', 'flutter3d_sim'],
  ),
  Feature(
    id: 'time-travel',
    title: 'A time-travel debugger',
    category: Category.widgetsMisc,
    summary:
        'Scrub a paused run to any step it holds and back, read each entity\'s history as lanes, and bisect two runs to the step and component where they part.',
    since: '1.0.0-rc.1',
    evidence: '`RunTimeline` scrubs without cutting.',
    evidenceFile: 'packages/flutter3d_game/CHANGELOG.md',
    packages: <String>['flutter3d_game', 'flutter3d_sim'],
  ),
  Feature(
    id: 'saves',
    title: 'Saves that survive an update',
    category: Category.widgetsMisc,
    summary:
        'A save schema whose old versions migrate on load, an autosave at pauses and checkpoints, and a cloud copy settled by step and digest.',
    since: '1.0.0-rc.1',
    evidence:
        'A save says what version of the game wrote it, and an old one is migrated.',
    evidenceFile: 'packages/flutter3d_sim/CHANGELOG.md',
    packages: <String>['flutter3d_sim', 'flutter3d_game', 'flutter3d_app'],
  ),
  Feature(
    id: 'parties',
    title: 'Parties of more than two',
    category: Category.widgetsMisc,
    summary:
        'Four machines rolling back over a late, lossy wire to one state, and a spectator who arrives late played the settled steps.',
    since: '1.0.0-rc.1',
    evidence: 'The relay holds parties.',
    evidenceFile: 'packages/flutter3d_net/CHANGELOG.md',
    keywords: <String>['RollbackSession', 'PeerWire.party'],
    packages: <String>['flame_multiplayer'],
    engineFiles: <String>['packages/flame_multiplayer/lib/src/party.dart'],
  ),
  Feature(
    id: 'scene-widgets',
    title: 'A scene written as widgets',
    category: Category.widgetsMisc,
    summary:
        'Mesh3D, Light3D, Node3D and Material3D: the scene as a widget tree, each widget owning one node.',
    since: '1.0.0-rc.1',
    evidence: 'A scene written as widgets',
    evidenceFile: 'packages/flutter3d_app/CHANGELOG.md',
    packages: <String>['flutter3d_app'],
    engineFiles: <String>[
      'packages/flutter3d_app/lib/src/declarative/scene_widgets.dart',
      'packages/flutter3d_app/lib/src/declarative/scene_widgets_mount.dart',
    ],
  ),
  Feature(
    id: 'render-inspection',
    title: 'Inspecting a running frame',
    category: Category.widgetsMisc,
    summary:
        'The passes, the draws, a pixel and the node under a point, read from the frame the game drew.',
    since: '1.0.0-rc.1',
    evidence:
        'A tool attached to a running game can read the game\'s own frame',
    evidenceFile: 'packages/flutter3d_app/CHANGELOG.md',
    packages: <String>['flutter3d_app'],
    engineFiles: <String>[
      'packages/flutter3d_app/lib/src/diagnostics/render_inspection.dart',
      'packages/flutter3d_app/lib/src/diagnostics/render_extensions.dart',
    ],
  ),
  Feature(
    id: 'hot-swap',
    title: 'Changing a running game\'s assets',
    category: Category.widgetsMisc,
    summary:
        'A texture, a model, a material field and a tunable changed under a running world, in the nodes it already has.',
    since: '1.0.0-rc.1',
    evidence: 'A hot reload shows the shaders it reloaded',
    evidenceFile: 'packages/flutter3d_app/CHANGELOG.md',
    packages: <String>['flutter3d_app', 'flutter3d_sim'],
    engineFiles: <String>[
      'packages/flutter3d_app/lib/src/hot_swap/hot_swap.dart',
      'packages/flutter3d_sim/lib/src/input/tunables.dart',
    ],
  ),
];
