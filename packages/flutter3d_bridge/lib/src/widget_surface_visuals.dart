import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// The kind a genre's own [EntityRegistry] registers for `widget_surface` —
/// **found the hard way, not designed ahead of time**: `LevelValidator`
/// treats an entity type its registry does not know as an ERROR that fails
/// the whole document (`LevelLoader.load` throws), which is a stricter door
/// than `flutter3d_editor_core`'s `OpenKind` — the editor's open vocabulary
/// validates a level `flutter3d_sim`'s own loader would refuse. `wg-02` hit
/// this loading a real level with a `widget_surface` entity and no kind for
/// it registered; `wg-01`'s own write-up did not, because nothing in it
/// loaded a level through a genre's closed registry.
///
/// Spawns nothing on purpose: [WidgetSurfaceVisuals.add] reads the entity
/// directly off [Level.entities] rather than through [SpawnContext], the
/// same way a level's own `player_spawn` is read as a coordinate rather than
/// spawned into anything. This kind exists only so the type is not unknown.
final class WidgetSurfaceKind extends EntityKind {
  const WidgetSurfaceKind() : super(WidgetSurfaceVisuals.entityType);
}

/// `wg-01`: a `widget_surface` entity in a level document, resolved into a
/// live [WidgetSurface] the same way a fixture resolves into a mesh
/// (`fixture_visuals.dart`) — the simulation names an entity by its flat
/// property bag, and this is the one place that turns it into a node.
///
/// **The level names a widget, not a widget.** `EntityDef.string('widget')`
/// is a key into [registry], a plain `Map<String, WidgetBuilder>` the
/// application hands over — the same principle
/// `doc/edu-00-interactive-format.md`'s `edu_annotation.widget` already
/// settled on for the same reason: a level document naming an actual
/// `Widget` subclass would make `flutter3d_sim` (which reads levels) depend
/// on an application's own screens, which is exactly backwards.
final class WidgetSurfaceVisuals {
  WidgetSurfaceVisuals(
    this.scene, {
    required this.device,
    required this.registry,
    IssueSink? onIssue,
  }) : onIssue = onIssue ?? printIssue;

  final Scene scene;
  final GraphicsDevice device;

  /// Resolves the `widget` a `widget_surface` entity names. The application
  /// builds this, not the level or the engine — see the class doc.
  final Map<String, WidgetBuilder> registry;

  final IssueSink onIssue;

  final List<WidgetSurface> _surfaces = <WidgetSurface>[];

  /// Every surface this has built, for a caller that wants to route a
  /// raycast hit at one of them (`WidgetSurface.uvAt`) or ask which one is
  /// focused.
  List<WidgetSurface> get surfaces =>
      List<WidgetSurface>.unmodifiable(_surfaces);

  static const String entityType = 'widget_surface';

  /// Builds a [WidgetSurface] for [entity] if it names a `widget_surface`
  /// and the name it gives resolves in [registry]; otherwise reports why
  /// through [onIssue] rather than throwing — a level with a typo in its
  /// widget name should draw everything else and say what it could not, the
  /// same choice `FixtureVisuals` already makes for a model that fails to
  /// load.
  WidgetSurface? add(EntityDef entity) {
    if (entity.type != entityType) return null;

    final name = entity.string('widget');
    if (name == null) {
      onIssue(Issue('$entityType "${entity.name ?? '?'}" names no widget'));
      return null;
    }
    final builder = registry[name];
    if (builder == null) {
      onIssue(
        Issue(
          '$entityType "${entity.name ?? '?'}" names "$name", which this '
          'application\'s widget registry does not have',
        ),
      );
      return null;
    }

    final surface = WidgetSurface(
      device: device,
      width: entity.number('width') ?? 1.0,
      height: entity.number('height') ?? 1.0,
      name: entity.name,
      child: Builder(builder: builder),
    )..setPosition(entity.position);
    surface.yaw = entity.yaw;

    scene.add(surface.node);
    _surfaces.add(surface);
    return surface;
  }

  /// Runs [WidgetSurface.tick] on every surface this built — the answer to
  /// "how does the game loop know a `WidgetSurface` needs ticking": it asks
  /// whoever placed it, the same way `FixtureVisuals.sync` already is the
  /// answer for "how does a torch's flame know to move" — a game calls this
  /// once per frame rather than walking the scene graph for a node kind it
  /// would otherwise have to know how to recognise.
  Future<void> tickAll() async {
    for (final surface in _surfaces) {
      await surface.tick();
    }
  }

  /// Takes every surface this built out of the scene and releases its
  /// pipeline — the counterpart to [add], for the same reason
  /// `FixtureVisuals.dispose` exists: a level change should not strand a
  /// widget's element tree the way it must not strand a torch's mesh.
  void dispose() {
    for (final surface in _surfaces) {
      surface.dispose();
    }
    _surfaces.clear();
  }
}
