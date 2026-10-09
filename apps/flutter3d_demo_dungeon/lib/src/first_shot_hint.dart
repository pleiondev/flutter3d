import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_ui/hud.dart' show MomentHint;
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// `ls-g-01`'s own rule, said once a run: the guard room's own layout —
/// `apps/flutter3d_demo_dungeon/tool/make_crypt.py`'s own design note —
/// gives distance before the runner closes it, and this is the sentence
/// that turns that layout into something a first-time player is told
/// rather than something only a second playthrough notices.
const String firstShotHint =
    'The doorway gives you room to aim before it reaches you.';

/// The crypt's half of the hint: its sentence, and its moment, the first
/// [ShotFired] of a run. When and how often it is said is the HUD addon's
/// [MomentHint].
const MomentHint<GameEvent> firstShot = MomentHint<GameEvent>(
  firstShotHint,
  when: _isShot,
);

bool _isShot(GameEvent event) => event is ShotFired;

/// [firstShotHint], the first time [events] carries a [ShotFired] this run
/// — null on every other step, including every step after the first, so a
/// caller tracks nothing beyond the one flag it passes as [alreadyTaught].
String? firstShotHintFor(
  List<GameEvent> events, {
  required bool alreadyTaught,
}) => firstShot.hintFor(events, alreadyTaught: alreadyTaught);
