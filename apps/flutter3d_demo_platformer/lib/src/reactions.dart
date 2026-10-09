import 'package:flutter3d_game_kit/reactions.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'effects.dart';

/// What a step of this game looks like.
///
/// **The other half of the split `Soundtrack` made, and the half its own doc
/// comment got wrong.** That file says particles and camera shake stay in the
/// widget because they "are already covered by the frame tests" — and no test
/// in this application mentions a particle, an effect or a shake. So the
/// visible half of the reaction to every event in the game sat in a private
/// method of a `State` that nothing can mount, with the coverage that excused
/// it existing only in a sentence.
///
/// The shape is `Soundtrack`'s exactly, and the reactions addon's: deciding is
/// a pure function of the simulation, returning a [Reaction] of bursts and
/// [Felt] jolts, and bursting and kicking are effects the widget performs. What
/// that buys is the same smoke alarm — a coin that is collected and shows
/// nothing fails a test, where before it was a thing somebody had to notice.
///
/// Kept beside the sound rather than merged into it, because they answer
/// different questions and get answered differently: a stomp is one sound and
/// two visible things, and a landing is a sound decided by whether it happened
/// and a camera kick decided by how hard.
final class Reactions {
  Reactions() {
    placed
      ..on<CollectibleTaken>(
        (CollectibleTaken event, ReactionBuilder out) =>
            out.bursts.add(Shown(Effects.coin, event.collectible.origin)),
      )
      // Everything the level's own machinery did. A spring that throws
      // somebody and a shelf that gives way are both events nobody was
      // watching for until there was something to show for them.
      // **What was here was a walk over every mechanism in the level, once a
      // frame, asking each of them three questions.** The simulation makes
      // that pass anyway; these arrive on the bus with everything else.
      ..on<SpringFired>(
        (SpringFired event, ReactionBuilder out) =>
            out.bursts.add(Shown(Effects.spring, event.at, direction: _up)),
      )
      ..on<BlockCrumbled>(
        (BlockCrumbled event, ReactionBuilder out) =>
            out.bursts.add(Shown(Effects.crumble, event.at)),
      )
      ..on<BlockBroke>(
        (BlockBroke event, ReactionBuilder out) =>
            out.bursts.add(Shown(Effects.slam, event.at)),
      );
  }

  /// The bursts an event places by itself — a coin where it lay, a spring, a
  /// shelf — which need nothing of the step but the event.
  ///
  /// **What the game hands a `ReactionsPlugin`**, which decides them off the
  /// bus's frame channel once a frame, after the frame's steps; the game
  /// shows what it took before the particles advance, so they burst in the
  /// frame and from the places they always did, and a step run again on a
  /// rollback no longer bursts twice. Everything else here reads the runner
  /// as one step left it and stays in [shownOnStep].
  final ReactionTable placed = ReactionTable();

  /// Everything this step is worth showing: [shownOnStep], then [placed].
  ///
  /// Called once per simulation step, in order, and the lists are what to do.
  /// What a test asks; the game shows [placed] through its plugin.
  Reaction listen(
    PlatformerSimulation sim,
    Runner runner,
    List<GameEvent> events,
  ) {
    final step = shownOnStep(sim, runner, events);
    final byEvent = placed.react(events);
    return Reaction(
      bursts: <Shown>[...step.bursts, ...byEvent.bursts],
      jolts: <Felt>[...step.jolts, ...byEvent.jolts],
    );
  }

  /// What this step shows that needs the runner as the step left it: the
  /// dashes, the jumps, the landing, and the moments shown where the runner
  /// stands. Not [placed].
  ///
  /// Called once per simulation step, in order, and the lists are what to do.
  Reaction shownOnStep(
    PlatformerSimulation sim,
    Runner runner,
    List<GameEvent> events,
  ) {
    final bursts = <Shown>[];
    final jolts = <Felt>[];
    final at = runner.position;

    if (events.whereType<Dashed>().isNotEmpty) {
      bursts.add(Shown(Effects.dash, at));
      jolts.add(const Felt.widen(0.1));
    }
    if (events.whereType<WallJumped>().isNotEmpty) {
      bursts.add(Shown(Effects.dust, at));
    }

    // **Three flags the runner has always set and nobody has ever read**, which
    // is the same shape of gap as the silent coin: the simulation was right and
    // the game said nothing. Each one is a moment a player commits to something
    // and deserves to be told it landed.
    if (events.whereType<LongJumped>().isNotEmpty) {
      // A long jump is a commitment — low, far, and no steering. It gets a wide
      // skirt of dust, because it is the slide it came out of, launched.
      bursts.add(Shown(Effects.dust, at));
      jolts.add(const Felt.widen(0.08));
    }
    if (events.whereType<Grabbed>().isNotEmpty) {
      // Catching a rope or a ladder: the camera settles rather than kicking,
      // because the runner has just stopped falling.
      bursts.add(Shown(Effects.dust, at));
    }
    if (events.whereType<Bounced>().isNotEmpty) {
      // The hop off something stomped. `EnemyStomped` says an enemy died;
      // this says the runner was thrown by it, and they are not the same
      // event.
      jolts.add(Felt.kick(Vector3(0.0, 0.05, 0.0)));
      bursts.add(Shown(Effects.spring, at, direction: _up));
    }

    // One burst per event. Two enemies stomped in one step are two of these;
    // under the flags they replace, they were one slam.
    for (final GameEvent event in events) {
      switch (event) {
        case EnemyStomped():
          bursts.add(Shown(Effects.slam, at));
          jolts.add(Felt.kick(Vector3(0.0, -0.12, 0.0)));
        case CheckpointReached():
          bursts.add(Shown(Effects.checkpoint, at, direction: _up));
        case RunnerDied():
          bursts.add(Shown(Effects.death, at));
          jolts.add(const Felt.shake(0.5, seconds: 0.4));
      }
    }

    if (events.whereType<Landed>().isNotEmpty) {
      _land(
        runner.landingSpeed,
        at,
        pounded: runner.poundedThisStep,
        bursts: bursts,
        jolts: jolts,
      );
    }

    return Reaction(bursts: bursts, jolts: jolts);
  }

  /// What a landing shows, from how hard it was. The pose is `RunnerLooks`'.
  void _land(
    double speed,
    Vector3 at, {
    required bool pounded,
    required List<Shown> bursts,
    required List<Felt> jolts,
  }) {
    if (pounded) {
      bursts.add(Shown(Effects.slam, at));
    } else if (speed > 6.0) {
      bursts.add(Shown(Effects.dust, at));
    }

    // Below walking pace the camera does nothing: one that dips every time the
    // player steps off a kerb is a camera nobody can look at.
    if (speed < 6.0 && !pounded) return;
    final hardness = (speed / 20.0).clamp(0.0, 1.0);
    jolts.add(Felt.kick(Vector3(0.0, -0.18 * hardness, 0.0)));
    if (pounded) jolts.add(const Felt.shake(0.22, seconds: 0.3));
  }
}

final Vector3 _up = Vector3(0.0, 1.0, 0.0);
