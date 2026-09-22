import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// `ls-g-01`'s own rule, said once a run: the guard room's own layout —
/// `apps/flutter3d_demo_dungeon/tool/make_crypt.py`'s own design note —
/// gives distance before the runner closes it, and this is the sentence
/// that turns that layout into something a first-time player is told
/// rather than something only a second playthrough notices.
const String firstShotHint =
    'The doorway gives you room to aim before it reaches you.';

/// [firstShotHint], the first time [events] carries a [ShotFired] this run
/// — null on every other step, including every step after the first, so a
/// caller tracks nothing beyond the one flag it passes as [alreadyTaught].
///
/// A pure function rather than inline in `_GameScreenState._step`, the same
/// split `Reactions.listen` and `Soundtrack.listen` already make between
/// "what a step is worth saying" and the widget that says it.
String? firstShotHintFor(
  List<GameEvent> events, {
  required bool alreadyTaught,
}) {
  if (alreadyTaught) return null;
  if (!events.any((GameEvent e) => e is ShotFired)) return null;
  return firstShotHint;
}
