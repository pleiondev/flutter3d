import 'package:flutter3d_game_kit/reactions.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'effects.dart';

/// What a step of this game looks like: the crypt's own table of reactions.
///
/// The shape is the reactions addon's — a [Reaction] decided as a pure
/// function of the simulation and performed by `FrameEffects` — and what is
/// here is only this game's: which event bursts what, and the blasts, which
/// are not events but the projectiles' own list.
///
/// The decisions used to live in three private methods of a `State` that
/// nothing can mount, so **no test in this application had ever mentioned a
/// particle**. A monster that dies with no sparks, a rocket that lands with no
/// fire and a shot with no muzzle flare were each a thing somebody had to
/// happen to notice.
///
/// What stays in the widget is the torches, and that is not an oversight: a
/// torch is not a reaction to an event, it is a continuous emission from a
/// fixture that also drives a light, and it has no step to be a function of.
final class Reactions {
  Reactions() {
    _table
      ..on<ShotFired>(_unlessQuiet<ShotFired>(_muzzle))
      ..on<ShotLanded>(
        _unlessQuiet<ShotLanded>((ShotLanded event, ReactionBuilder out) {
          final hit = event.hit;
          if (!hit.didStrikeSomething) return;
          out
            ..flash = true
            ..bursts.add(
              Shown(Effects.impactSparks, hit.point, direction: hit.normal),
            )
            ..bursts.add(
              Shown(Effects.impactDust, hit.point, direction: hit.normal),
            );
        }),
      )
      ..on<ActorDied>(
        _unlessQuiet<ActorDied>((ActorDied event, ReactionBuilder out) {
          final where = event.actor.position;
          if (where != null) out.bursts.add(Shown(Effects.impactSparks, where));
        }),
      );
  }

  /// The table heard from the engine's bus: what the game installs, and
  /// takes a [Reaction] from once a frame.
  ///
  /// **The events' half only.** The blasts are not events but the
  /// projectiles' own list, read in the step by [blasts]; the table's rows
  /// are decided on the frame channel, after the frame's steps and before
  /// it is drawn, so a burst lands on the frame it always did.
  late final ReactionsPlugin plugin = ReactionsPlugin(_table);

  /// The player whose barrel the flare sits at. Set by the game on every
  /// step; [listen] sets it to the one it is handed.
  Player? player;

  /// Whether what the bus is handing out now is to be left unshown — a
  /// skipped cutscene's steps, which happen and are not shown. Set by the
  /// game before each event is delivered.
  bool quiet = false;

  ReactionRule<T> _unlessQuiet<T extends BusEvent>(ReactionRule<T> rule) =>
      (T event, ReactionBuilder out) {
        if (!quiet) rule(event, out);
      };

  /// Where the muzzle is, relative to the eye the shot came from.
  ///
  /// Forwards along the aim, a little down, and a little to the right — the
  /// flare is the one thing that should sit at the barrel rather than at the
  /// eye, unlike the sound, which pans wrong anywhere but the middle.
  static const double _reach = 0.6;
  static const double _drop = 0.12;
  static const double _side = 0.18;

  final ReactionTable _table = ReactionTable();
  final Vector3 _aim = Vector3.zero();
  final Vector3 _right = Vector3.zero();

  void _muzzle(ShotFired event, ReactionBuilder out) {
    player
      ?..aim(_aim)
      ..right(_right);
    out.bursts.add(
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
  }

  /// Everything this step is worth showing: what the table makes of
  /// [events], and the blasts.
  ///
  /// The two halves the game hears apart — the table through [plugin] on the
  /// frame channel, the blasts through [blasts] in the step — together, for
  /// a test that steps the simulation by hand.
  Reaction listen(GameSimulation sim, Player player, List<GameEvent> events) {
    final out = ReactionBuilder();
    this.player = player;
    _table.decide(events, out);
    _blastsInto(sim, out);
    return out.build();
  }

  /// What the step just run detonated: fire, embers and the smoke after.
  Reaction blasts(GameSimulation sim) {
    final out = ReactionBuilder();
    _blastsInto(sim, out);
    return out.build();
  }

  void _blastsInto(GameSimulation sim, ReactionBuilder out) {
    final projectiles = sim.projectiles;
    if (projectiles == null) return;
    for (final blast in projectiles.detonations) {
      out
        ..flash = true
        ..bursts.add(Shown(Effects.explosionCore, blast.position))
        ..bursts.add(Shown(Effects.explosionEmbers, blast.position))
        // Smoke for a second after the fire is out, under a key of its own.
        ..lingering.add(
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
}
