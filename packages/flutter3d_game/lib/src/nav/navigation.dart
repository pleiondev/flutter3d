/// The level's walkable grid and the flow fields over it, kept together.
///
/// One of these is built per level and handed to whatever wants to walk
/// somewhere. It holds the bake, hands out a field per class of body, and
/// re-sweeps them when the goal moves — so a caller says "the player is here"
/// once a step and "which way from here" per agent, and never has to know that
/// either is a Dijkstra.
///
/// **Optional everywhere it is used.** `MonsterSystem.navigation` is nullable
/// and null keeps the old behaviour exactly: see the player, turn, walk
/// straight, get stuck on the corner. That is what makes this a thing a game
/// switches on rather than a thing it must build a grid for.
library;

import 'package:vector_math/vector_math.dart';

import '../level/level.dart';
import '../level/level_issue.dart';
import 'flow_field.dart';
import 'nav_grid.dart';

/// Somewhere to walk, and the way there.
final class Navigation {
  Navigation(this.grid);

  /// Bakes the level's architecture. See [NavGrid.bake] for what [issues]
  /// collects — a level with a walkway over a floor is worth hearing about.
  factory Navigation.bake(
    Level level, {
    double cellSize = 0.5,
    double agentHeight = 1.7,
    double stepHeight = 0.4,
    double maxFall = 2.0,
    List<LevelIssue>? issues,
  }) =>
      Navigation(NavGrid.bake(
        level.brushes,
        cellSize: cellSize,
        agentHeight: agentHeight,
        stepHeight: stepHeight,
        maxFall: maxFall,
        issues: issues,
      ));

  final NavGrid grid;

  final Map<int, FlowField> _fields = <int, FlowField>{};
  final Vector3 _goal = Vector3.zero();
  bool _hasGoal = false;

  /// Every field built so far, one per class of body.
  Iterable<FlowField> get fields => _fields.values;

  /// Where everything is currently walking towards.
  ///
  /// **Every** field is re-targeted, which is the point — one goal, one sweep
  /// per class of body — and also the one way to misuse this: two callers with
  /// different destinations cannot share a `Navigation`. The second one's
  /// fields quietly start flowing to the first one's goal, and the symptom is
  /// an agent that appears to be stuck rather than an error. Give each
  /// destination its own instance; the grid is the expensive part and it is
  /// what [Navigation.new] takes, so sharing that costs nothing.
  void update(Vector3 goal) {
    _goal.setFrom(goal);
    _hasGoal = true;
    for (final field in _fields.values) {
      field.update(goal);
    }
  }

  /// The field for a body of this size, built on first use.
  ///
  /// Keyed by the pair the field actually filters on, so two monsters of
  /// slightly different radius that round to the same clearance share one
  /// sweep — which, for a roster of three, is why there are two fields and not
  /// thirty.
  FlowField fieldFor({required double radius, double height = 0.0}) {
    final clearance = grid.clearanceForRadius(radius);
    // Heights are bucketed by a quarter metre for the same reason: nothing in
    // a level is built to finer tolerance than that, and a distinct field per
    // distinct float would defeat the sharing.
    final heightClass = (height / 0.25).ceil();
    final key = clearance * 1024 + heightClass;
    return _fields.putIfAbsent(key, () {
      final field = FlowField(
        grid,
        minClearance: clearance,
        minHeadroom: heightClass * 0.25,
      );
      // A field built after the goal was set has to catch up, or the agent
      // that asked for it walks nowhere until the player crosses a cell.
      if (_hasGoal) field.rebuild(_goal);
      return field;
    });
  }

  /// The direction to walk from [from] for a body of this size.
  ///
  /// False when the field has nothing to say — see [FlowField.descend]. The
  /// caller should then head straight at its target, which is both what it did
  /// before navigation existed and the right answer within a single cell.
  bool steer(
    Vector3 from,
    Vector3 out, {
    required double radius,
    double height = 0.0,
  }) =>
      fieldFor(radius: radius, height: height).descend(from, out);
}
