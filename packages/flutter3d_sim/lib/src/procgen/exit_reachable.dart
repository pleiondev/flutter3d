import '../level/entity_types.dart';
import '../level/level.dart';
import '../level/level_issue.dart';
import '../level/level_rule.dart';
import '../nav/navmesh/navmesh.dart';
import '../nav/navmesh/navmesh_config.dart';

/// A level whose exit no walk from the player's start reaches is refused:
/// the navigation mesh is baked, and a route asked of it from the start to
/// each exit until one arrives.
///
/// **On the mesh a monster walks, not on a guess.** A level can have every
/// room joined in its document and still be closed — a doorway a step too
/// high, a corridor a hand narrower than a body — and the bake is what
/// knows. It is the rule a generator holds its levels to before handing one
/// over, and one a game whose levels are hand-built can add to its own.
///
/// Says nothing of a level with no start or no exit: those are other rules'
/// to say ([ExactlyOne], [AtLeastOne]).
final class ExitReachable extends LevelRule {
  const ExitReachable({this.config = const NavMeshSettings()});

  /// What the mesh is baked as: the body that has to make the walk.
  final NavMeshSettings config;

  @override
  void check(Level level, List<LevelIssue> out) {
    final starts = level.ofType(EntityTypes.playerSpawn);
    final exits = level.ofType(EntityTypes.exit);
    if (starts.isEmpty || exits.isEmpty) return;
    final mesh = NavMesh.bakeLevel(level, config: config);
    final from = starts.first.position;
    for (final exit in exits) {
      final route = mesh.route(from, exit.position);
      if (route != null && route.complete) return;
    }
    out.add(
      LevelIssue(
        LevelIssueSeverity.error,
        'no walk from the player\'s start reaches '
        '${exits.length == 1 ? 'the exit' : 'any of the ${exits.length} exits'}'
        ', so the level cannot be finished',
        where: 'navigation',
      ),
    );
  }
}
