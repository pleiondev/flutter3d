import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:vector_math/vector_math.dart';

import 'effects.dart';

/// Something that keeps emitting for a while after the event that caused it.
///
/// A rocket's smoke outlives its fire by the best part of a second, and a burst
/// cannot say that. Each one carries a key of its own rather than its position:
/// two rockets landing in the same doorway are two plumes, and a shared key
/// would mean the second restarted the first.
final class Lingering {
  const Lingering(
    this.key,
    this.effect,
    this.at, {
    required this.perSecond,
    required this.seconds,
  });

  final Object key;
  final ParticleEffect effect;
  final Vector3 at;
  final double perSecond;
  final double seconds;
}

/// Everything one step showed, and how hard the screen should flash about it.
///
/// **Per game, and it should be.** [Shown] moved into the particles package
/// because both applications had written it identically; this did not, because
/// they had not: the platformer's carries what the camera does about it, and
/// this one's carries what lingers and whether the screen flashes. A shared
/// class covering both would be four fields where each game reads two.
final class Reaction {
  const Reaction(this.bursts, this.lingering, {this.flash = false});

  final List<Shown> bursts;
  final List<Lingering> lingering;

  /// Whether something landed hard enough to whiten the screen.
  ///
  /// A boolean rather than an amount, because how much is an accessibility
  /// question and the answer belongs to the player's own settings — a
  /// full-screen flash on every hit is a photosensitivity matter, and this
  /// class has no business deciding it.
  final bool flash;
}

/// What a step of this game looks like.
///
/// The other half of the split `Soundtrack` makes, and made for the same
/// reason: the decisions lived in three private methods of a `State` that
/// nothing can mount, so **no test in this application had ever mentioned a
/// particle**. A monster that dies with no sparks, a rocket that lands with no
/// fire and a shot with no muzzle flare were each a thing somebody had to
/// happen to notice.
///
/// The platformer learned this the hard way: its `Soundtrack` claimed the
/// visible half was "already covered by the frame tests", and the word
/// "particle" did not appear in its tests at all.
///
/// Deciding is a pure function of the simulation; bursting is an effect the
/// widget performs. What stays in the widget is the torches, and that is not
/// an oversight: a torch is not a reaction to an event, it is a continuous
/// emission from a fixture that also drives a light, and it has no step to be a
/// function of.
final class Reactions {
  /// Where the muzzle is, relative to the eye the shot came from.
  ///
  /// Forwards along the aim, a little down, and a little to the right — the
  /// flare is the one thing that should sit at the barrel rather than at the
  /// eye, unlike the sound, which pans wrong anywhere but the middle.
  static const double _reach = 0.6;
  static const double _drop = 0.12;
  static const double _side = 0.18;

  final Vector3 _aim = Vector3.zero();
  final Vector3 _right = Vector3.zero();

  /// Everything this step is worth showing.
  Reaction listen(
    GameSimulation sim,
    Player player,
    List<GameEvent> events,
  ) {
    final bursts = <Shown>[];
    final lingering = <Lingering>[];
    var flash = false;

    for (final GameEvent event in events) {
      switch (event) {
        case ShotFired():
          player
            ..aim(_aim)
            ..right(_right);
          bursts.add(
            Shown(
              Effects.muzzleFlash,
              Vector3(
                event.from.x + _aim.x * _reach - _right.x * _side,
                event.from.y + _aim.y * _reach - _drop,
                event.from.z + _aim.z * _reach - _right.z * _side,
              ),
              direction: _aim.clone(),
            ),
          );
        case ShotLanded(hit: final ShotHit hit) when hit.struckSomething:
          flash = true;
          bursts
            ..add(Shown(Effects.impactSparks, hit.point, direction: hit.normal))
            ..add(Shown(Effects.impactDust, hit.point, direction: hit.normal));
        case ActorDied():
          final where = event.actor.position;
          if (where != null) bursts.add(Shown(Effects.impactSparks, where));
      }
    }

    final projectiles = sim.projectiles;
    if (projectiles != null) {
      for (final blast in projectiles.detonations) {
        flash = true;
        bursts
          ..add(Shown(Effects.explosionCore, blast.position))
          ..add(Shown(Effects.explosionEmbers, blast.position));
        // Smoke for a second after the fire is out, under a key of its own.
        lingering.add(
          Lingering(
            Object(),
            Effects.explosionSmoke,
            blast.position,
            perSecond: 34.0,
            seconds: 0.85,
          ),
        );
      }
    }

    return Reaction(bursts, lingering, flash: flash);
  }
}
