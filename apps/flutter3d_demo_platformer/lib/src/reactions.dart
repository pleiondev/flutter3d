import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:vector_math/vector_math.dart';

import 'effects.dart';

/// What the camera does about something, as a description rather than a call.
///
/// Three verbs, because `FollowCamera` has three: a [kick] is a nudge the
/// camera recovers from, a [shake] is a rattle over a stretch of time, and a
/// [widen] pulls the view out. A description rather than a call so that a test
/// can ask what a stomp does to the camera without owning one.
final class Felt {
  const Felt.kick(Vector3 by)
    : jolt = Jolt.kick,
      offset = by,
      amount = 0.0,
      seconds = 0.0;

  const Felt.shake(this.amount, {this.seconds = 0.0})
    : jolt = Jolt.shake,
      offset = null;

  const Felt.widen(this.amount)
    : jolt = Jolt.widen,
      offset = null,
      seconds = 0.0;

  final Jolt jolt;
  final Vector3? offset;
  final double amount;
  final double seconds;

  /// Performs it. The only place this file touches a camera.
  void applyTo(FollowCamera camera) {
    switch (jolt) {
      case Jolt.kick:
        camera.kick(offset!);
      case Jolt.shake:
        camera.shake(amount, seconds: seconds);
      case Jolt.widen:
        camera.widen(amount);
    }
  }

  @override
  String toString() => 'Felt(${jolt.name})';
}

/// Which of the camera's three verbs a [Felt] is.
enum Jolt { kick, shake, widen }

/// Everything one step of the game showed, decided rather than performed.
final class Reaction {
  const Reaction(this.bursts, this.jolts);

  final List<Shown> bursts;
  final List<Felt> jolts;
}

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
/// The shape is `Soundtrack`'s exactly: deciding is a pure function of the
/// simulation, and bursting and kicking are effects the widget performs. What
/// that buys is the same smoke alarm — a coin that is collected and shows
/// nothing fails a test, where before it was a thing somebody had to notice.
///
/// Kept beside the sound rather than merged into it, because they answer
/// different questions and get answered differently: a stomp is one sound and
/// two visible things, and a landing is a sound decided by whether it happened
/// and a camera kick decided by how hard.
final class Reactions {
  /// Everything this step is worth showing.
  ///
  /// Called once per simulation step, in order, and the lists are what to do.
  Reaction listen(
    PlatformerSimulation sim,
    Runner runner,
    List<GameEvent> events,
  ) {
    final bursts = <Shown>[];
    final jolts = <Felt>[];
    final at = runner.position;

    if (runner.dashedThisStep) {
      bursts.add(Shown(Effects.dash, at));
      jolts.add(const Felt.widen(0.1));
    }
    if (runner.wallJumpedThisStep) bursts.add(Shown(Effects.dust, at));

    // **Three flags the runner has always set and nobody has ever read**, which
    // is the same shape of gap as the silent coin: the simulation was right and
    // the game said nothing. Each one is a moment a player commits to something
    // and deserves to be told it landed.
    if (runner.longJumpedThisStep) {
      // A long jump is a commitment — low, far, and no steering. It gets a wide
      // skirt of dust, because it is the slide it came out of, launched.
      bursts.add(Shown(Effects.dust, at));
      jolts.add(const Felt.widen(0.08));
    }
    if (runner.grabbedThisStep) {
      // Catching a rope or a ladder: the camera settles rather than kicking,
      // because the runner has just stopped falling.
      bursts.add(Shown(Effects.dust, at));
    }
    if (runner.bouncedThisStep) {
      // The hop off something stomped. `EnemyStomped` says an enemy died;
      // this says the runner was thrown by it, and they are not the same
      // event.
      jolts.add(Felt.kick(Vector3(0.0, 0.05, 0.0)));
      bursts.add(Shown(Effects.spring, at, direction: _up));
    }

    // One burst per event. Two coins swept up in one step are two of these;
    // under the flags they replace, two enemies stomped were one slam.
    for (final GameEvent event in events) {
      switch (event) {
        case CollectibleTaken():
          bursts.add(Shown(Effects.coin, event.collectible.origin));
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

    // Everything the level's own machinery did this step. A spring that throws
    // somebody and a shelf that gives way are both events nobody was watching
    // for until there was something to show for them.
    for (final Mechanism mechanism
        in sim.mechanisms?.all ?? const <Mechanism>[]) {
      if (mechanism is Spring && mechanism.firedThisStep) {
        bursts.add(Shown(Effects.spring, mechanism.origin, direction: _up));
      }
      if (mechanism is Crumbling && mechanism.crumbledThisStep) {
        bursts.add(Shown(Effects.crumble, mechanism.origin));
      }
      if (mechanism is Breakable && mechanism.brokeThisStep) {
        bursts.add(Shown(Effects.slam, mechanism.origin));
      }
    }

    if (runner.landedThisStep) {
      _land(
        runner.landingSpeed,
        at,
        pounded: runner.poundedThisStep,
        bursts: bursts,
        jolts: jolts,
      );
    }

    return Reaction(bursts, jolts);
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
