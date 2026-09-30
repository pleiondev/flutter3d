/// What a crawl hands `flame_multiplayer`'s `RollbackPlay` for two machines:
/// one hero's hands for a step, as they travel.
///
/// Everything else — the room, the rollback, the ending both machines agree
/// on — is the package's. The crawl was built for it: fixed steps, a save
/// that carries the horde and the shots, and a restore that takes the world
/// back to before a monster was born, which is what a rollback past a birth
/// is.
library;

import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';

/// What one hero is asked to do for a step, as it travels.
///
/// **The stick in whole hundredths.** The session compares a frame it guessed
/// with the one that arrives by equality, and the two machines must apply the
/// same numbers; a double read off a stick is neither short nor stable, and
/// a hundredth of a stick is finer than a thumb.
Map<String, Object?> heroFrame(
  double x,
  double z, {
  required bool fire,
  required bool drink,
}) => <String, Object?>{
  'x': (x.clamp(-1.0, 1.0) * 100.0).round(),
  'z': (z.clamp(-1.0, 1.0) * 100.0).round(),
  'fire': fire,
  'drink': drink,
};

/// The far side of [heroFrame]: writes it onto [hero] for the step about to
/// run. An empty frame — nothing heard yet — is a hero standing still.
void applyHeroFrame(Map<String, Object?> frame, Hero hero) {
  hero.wish.setValues(
    ((frame['x'] as num?) ?? 0) / 100.0,
    0.0,
    ((frame['z'] as num?) ?? 0) / 100.0,
  );
  hero.fire = frame['fire'] == true;
  hero.drink = frame['drink'] == true;
}
