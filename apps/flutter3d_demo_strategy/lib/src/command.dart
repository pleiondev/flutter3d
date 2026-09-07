/// Who the player has picked out, and what they are told to do.
///
/// **What this replaced was a click that moved everybody.** `main.dart` took a
/// tap on the ground and sent `Staged.mine` — the crowd the map opened with —
/// to the spot. Three things were wrong with that at once, and only the first
/// is about selection. A move order ends the job it lands on, deliberately (see
/// `Squad.moveTo`), so one click stopped every harvester this side had and the
/// stockpile stopped growing: the player's own economy was the price of moving
/// anybody. The list was also filled once, when the document was read, so a
/// worker built by a hall during the match was never in it and could not be
/// ordered anywhere; and nothing ever took a unit out of it, so the day a unit
/// can be lost it would still be receiving orders.
///
/// **The picking is [Selection]'s, not the renderer's.** The picking pass
/// answers with the node that was drawn, and the crowd is one instanced batch —
/// `Renderer.pickPixel` says so in its own doc: an instanced batch answers as
/// the batch. So the pass can say *a unit was clicked* and never *which one*,
/// and the only way to make it say which would be a node per unit, which is the
/// arrangement the crowd exists to avoid. A ray against each unit's radius is
/// what answers the question, and it is in the game package with tests of its
/// own. Buildings keep the pass: they are real nodes, and a silhouette is a
/// better answer there than the box around a hall.
///
/// **The orders go into the queue.** Nothing here assigns `Unit.order`. A
/// pointer callback runs between steps, so an order written straight onto a
/// unit lands at whatever moment the mouse happened to be released and is
/// invisible to a recorder; queued, it is carried out at the top of the next
/// step alongside the bot's, and the tape sees it. See `OrderQueue`.
library;

import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:vector_math/vector_math.dart';

/// The units one side has picked out, and the orders it gives them.
///
/// Mutable, because a selection is state: it is the one thing on this screen
/// that is neither a fact about the simulation nor a fact about the camera, and
/// it changes only when the player says so. The widget owns one of these for
/// the length of a match.
final class CommandPost {
  /// Commands [side] of [simulation]. Nothing is selected to begin with.
  CommandPost({required this.simulation, required this.side});

  /// The crowd this reads and writes orders for.
  final StrategySimulation simulation;

  /// Whose units may be selected and ordered. A number rather than a hard-coded
  /// nought, for the reason the rest of this genre gives: how many sides a match
  /// has is read out of the document, and a map with three camps is a map this
  /// screen has to be able to sit in front of.
  final int side;

  final List<Unit> _selected = <Unit>[];

  /// Who is picked out, in the order they were picked, which is the order the
  /// arrangement hands out its places in.
  List<Unit> get selected => List<Unit>.unmodifiable(_selected);

  /// How many are picked out.
  int get count => _selected.length;

  /// This side's units, as they stand now.
  ///
  /// **Asked of the simulation every time rather than kept.** A hall turns a
  /// stockpile back into workers while the match runs, so any list held from
  /// the opening is a list that is wrong by minute two — which is exactly the
  /// bug the crowd-wide click was built on.
  List<Unit> get mine => <Unit>[
    for (final Unit unit in simulation.units)
      if (unit.side == side) unit,
  ];

  /// The unit a ray hits first, whoever it belongs to, or null.
  ///
  /// Both sides, because this is also what the readout under the cursor asks:
  /// a player pointing at the other side's worker wants to be told it is
  /// theirs, not told there is nothing there.
  Unit? unitUnder(Vector3 origin, Vector3 direction) =>
      Selection(simulation.units).unitAt(origin, direction);

  /// Picks out [unit] alone, and returns whether it could be.
  ///
  /// A click replaces the selection rather than adding to it. The other side's
  /// unit picks out nothing — and leaves what was already picked standing,
  /// because a click that cannot be obeyed should not quietly disband the squad
  /// the player gathered.
  bool select(Unit unit) {
    if (unit.side != side) return false;
    _selected
      ..clear()
      ..add(unit);
    return true;
  }

  /// Picks out the unit under a ray, and returns whether anything was picked.
  bool selectAt(Vector3 origin, Vector3 direction) {
    final Unit? hit = unitUnder(origin, direction);
    return hit != null && select(hit);
  }

  /// Picks out every unit of this side standing inside the rectangle whose
  /// opposite corners are [corner] and [opposite], and returns how many.
  ///
  /// The rectangle is in the world, on the ground, which is what [Selection]
  /// takes and why: a frustum test would put the camera inside the answer and
  /// make a replay depend on where somebody was looking.
  int selectWithin(Vector3 corner, Vector3 opposite) {
    final List<Unit> inside = Selection(
      simulation.units,
    ).unitsWithin(corner, opposite);
    _selected
      ..clear()
      ..addAll(inside.where((Unit unit) => unit.side == side));
    return _selected.length;
  }

  /// Picks out nothing.
  void clear() => _selected.clear();

  /// Asks the next step to send whoever is picked out to [goal], and returns
  /// whether anybody was asked.
  ///
  /// **An empty selection orders nobody, and that is the whole point.** The
  /// click this replaced sent the opening crowd, so every click on the ground
  /// cancelled every job on this side; now a player who has picked out six
  /// workers moves six and the other fifty-four carry on digging.
  bool orderTo(Vector3 goal) {
    prune();
    if (_selected.isEmpty) return false;
    simulation.orders.moveTo(_selected, goal);
    return true;
  }

  /// Drops anybody who is no longer on the map.
  ///
  /// Nothing takes a unit out of the simulation today — there is no fight, so
  /// nothing can be lost — and this is here rather than waiting for one because
  /// the alternative is a list that holds a unit the world has forgotten and
  /// keeps naming it in orders. `MoveOrder` would drop such a name (it addresses
  /// units by entity index and skips what it cannot find), so the symptom would
  /// not be a crash: it would be a HUD counting a squad larger than the one that
  /// moves, which is the kind of wrong that gets explained away for a year.
  void prune() {
    if (_selected.isEmpty) return;
    final Set<Unit> onMap = Set<Unit>.identity()..addAll(simulation.units);
    _selected.removeWhere((Unit unit) => !onMap.contains(unit));
  }
}
