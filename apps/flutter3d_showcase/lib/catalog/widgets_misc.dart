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
];
