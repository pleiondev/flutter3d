import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import '../enemy.dart';
import '../platformer_entities.dart';

/// Something that walks a route. See [Patrol] and [Leaper].
///
/// The route is the entity's own position followed by whatever `route` lists,
/// so the simplest enemy a level can author is a position and one more point.
/// A `kind` of `leaper` jumps the gaps in that route instead of turning at
/// them.
final class EnemyKind extends EntityKind {
  const EnemyKind() : super(PlatformerEntities.enemy);

  /// Shorter than the runner, so a stomp reads as landing *on* something.
  static Vector3 get defaultSize => Vector3(0.7, 0.7, 0.7);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final route = entity.properties['route'];
    if (route is! List || route.isEmpty) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "route", so it is a thing standing in one place — which is a '
          'hazard, and cheaper',
          where: scope.describe(entity),
        ),
      );
    }
    // **Each row, not just the list.** `spawn` reads three numbers out of every
    // row, and a row that is not three numbers used to leave by one of two bad
    // doors: an unchecked `as num` threw a `TypeError` out of `spawnInto`,
    // which the application reports as "that level would not load" with a cast
    // message; or a short row was dropped in silence, and if that left fewer
    // than two points the enemy was simply not in the level, with nothing said.
    // A registry exists to turn both of those into a sentence naming the file.
    if (route is List) {
      for (var i = 0; i < route.length; i++) {
        final row = route[i];
        final ok =
            row is List &&
            row.length >= 3 &&
            row[0] is num &&
            row[1] is num &&
            row[2] is num;
        if (ok) continue;
        out.add(
          LevelIssue(
            LevelIssueSeverity.error,
            'has a route whose point $i is not three numbers, and every point '
            'is a place in the world',
            where: scope.describe(entity),
          ),
        );
      }
    }

    final kind = entity.string('kind');
    if (kind != null && kind != 'patrol' && kind != 'leaper') {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'is a "$kind", and this game knows "patrol" and "leaper"',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final actors = context.actors;
    final rows = entity.properties['route'];
    if (rows is! List || rows.isEmpty) return;

    // Read defensively even so: `validate` is what names a bad row to the
    // author, and this is what stops a document that skipped validation from
    // taking the level down with a cast error instead.
    final route = <Vector3>[entity.position.clone()];
    for (final row in rows) {
      if (row is! List || row.length < 3) continue;
      final x = row[0];
      final y = row[1];
      final z = row[2];
      if (x is! num || y is! num || z is! num) continue;
      route.add(Vector3(x.toDouble(), y.toDouble(), z.toDouble()));
    }
    if (route.length < 2) return;

    final size = entity.vector('size') ?? defaultSize;
    final body = CharacterController(
      world: context.world,
      shape: CollisionBox(size / 2.0),
      // The document points at the floor, as it does for everything else.
      position: entity.position + Vector3(0.0, size.y / 2.0, 0.0),
      layer: CollisionLayers.actor,
    );

    final speed = entity.number('speed') ?? 0.55;
    final actor = actors.spawn(
      body: body,
      health: Health(entity.number('health') ?? 20.0),
      facing: Facing(),
      brain: entity.string('kind') == 'leaper'
          ? Leaper(route: route, speed: speed)
          : Patrol(route: route, speed: speed),
    );

    context.reveal(entity, collider: body.collider, size: size);
    // So a stomp can find what it landed on: the runner reads `ground.userData`
    // and everything else in this genre puts its own mechanism there.
    body.collider.userData = actor;
  }
}
