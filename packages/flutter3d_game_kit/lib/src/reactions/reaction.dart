import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter3d_audio_core/flutter3d_audio_core.dart' show Heard;
import 'package:flutter3d_camera/flutter3d_camera.dart' show CameraRig;
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:vector_math/vector_math.dart';

/// Something that keeps emitting for a while after the event that caused it.
///
/// A blast's smoke outlives its fire by the best part of a second, and a
/// [Shown] burst cannot say that. Each one carries a key of its own rather
/// than its position: two blasts in the same doorway are two plumes, and a
/// shared key would mean the second restarted the first.
final class Lingering {
  const Lingering(
    this.key,
    this.effect,
    this.at, {
    required this.perSecond,
    required this.seconds,
  });

  /// Whatever is emitting. A fresh `Object()` for a one-off plume.
  final Object key;
  final ParticleEffect effect;
  final Vector3 at;

  /// How many particles it emits per second.
  final double perSecond;

  /// How long it keeps emitting, in seconds.
  final double seconds;
}

/// Which of a camera's three verbs a [Felt] is.
///
/// An open value class rather than an enum (ARCHITECTURE.md §13.1): a camera
/// that learns a fourth verb is a minor release, not a break for every
/// `switch` written against three.
final class Jolt {
  const Jolt._(this.name);

  /// A nudge the camera recovers from: `CameraRig.kick`.
  static const Jolt kick = Jolt._('kick');

  /// A rattle over a stretch of time: `CameraRig.shake`.
  static const Jolt shake = Jolt._('shake');

  /// The view pulled out, decaying back: `CameraRig.widen`.
  static const Jolt widen = Jolt._('widen');

  final String name;

  @override
  String toString() => name;
}

/// What the camera does about something, as a description rather than a call.
///
/// Three verbs, because [CameraRig] has three. A description rather than a
/// call so that a test can ask what a landing does to the camera without
/// owning one, and so the camera's `motion` setting — which the rig applies —
/// stays the one place reduced motion is decided.
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

  /// Only for a kick: which way and how far, in metres.
  final Vector3? offset;

  /// A shake's width in metres, or a widening in radians.
  final double amount;

  /// How long a shake lasts, in seconds.
  final double seconds;

  /// Performs it on [rig]. The only place this package touches a camera.
  void applyTo(CameraRig rig) {
    if (identical(jolt, Jolt.kick)) {
      rig.kick(offset!);
    } else if (identical(jolt, Jolt.shake)) {
      rig.shake(amount, seconds: seconds);
    } else {
      rig.widen(amount);
    }
  }

  @override
  String toString() => 'Felt(${jolt.name})';
}

/// A pulse of the device in the player's hand, as a description.
///
/// For a game on a phone or a pad: a landing felt in the palm as well as
/// seen. An open value class, one constant per pulse Flutter's
/// `HapticFeedback` offers, so a test can ask what a step buzzed without a
/// device, and a platform with no motor performs nothing.
final class Haptic {
  const Haptic._(this.name, this._perform);

  static const Haptic selection = Haptic._(
    'selection',
    HapticFeedback.selectionClick,
  );
  static const Haptic light = Haptic._('light', HapticFeedback.lightImpact);
  static const Haptic medium = Haptic._('medium', HapticFeedback.mediumImpact);
  static const Haptic heavy = Haptic._('heavy', HapticFeedback.heavyImpact);

  final String name;
  final Future<void> Function() _perform;

  /// Asks the platform for the pulse. Never waits and never fails: a device
  /// with no motor answers by doing nothing.
  void perform() {
    _perform();
  }

  @override
  String toString() => 'Haptic($name)';
}

/// Something a reaction does that has no field of its own on [Reaction]: a
/// moment of slow motion, a rumble in a pad's two motors, a light that
/// flares.
///
/// **The open end of a reaction.** [Reaction] names the five things every
/// game here does — bursts, plumes, jolts, sounds, haptics — and a sixth used
/// to mean a field in this package. A game extends this instead, holding
/// whatever it performs on, and a rule adds one with [ReactionBuilder.add]:
///
/// ```dart
/// final class SlowMotion extends ReactionEffect {
///   const SlowMotion(this.clock, this.seconds);
///   final GameClock clock;
///   final double seconds;
///   @override
///   void perform() => clock.slow(0.3, seconds: seconds);
/// }
/// ```
///
/// A description first, like the rest of a reaction: a test asks what a
/// step decided by reading [Reaction.effects], and nothing is performed until
/// the game calls [Reaction.perform]. `base`, so a member added later
/// arrives with a default.
abstract base class ReactionEffect {
  const ReactionEffect();

  /// Does it. Nothing by default, for an effect a game only reads.
  void perform() {}
}

/// Everything one step showed, felt and sounded like, decided rather than
/// performed.
///
/// **A decision, not an effect.** What a step ought to show is a fact about
/// the simulation and can be asserted without a device; bursting it needs a
/// particle system, kicking it a camera, and playing it a mixer. Three games
/// wrote a class of this name, each with two of these fields; this is the
/// union, and a game fills the ones it has.
///
/// [flash] is a boolean rather than an amount on purpose: how bright is an
/// accessibility question, and the answer belongs to the player's own
/// settings (see [ScreenFlash]).
final class Reaction {
  const Reaction({
    this.bursts = const <Shown>[],
    this.lingering = const <Lingering>[],
    this.jolts = const <Felt>[],
    this.heard = const <Heard>[],
    this.haptics = const <Haptic>[],
    this.flash = false,
    this.effects = const <ReactionEffect>[],
  });

  /// Nothing at all.
  static const Reaction none = Reaction();

  final List<Shown> bursts;
  final List<Lingering> lingering;
  final List<Felt> jolts;

  /// Sounds that belong with what is seen, at the same place: sparks off a
  /// wall and the bang of hitting it.
  final List<Heard> heard;
  final List<Haptic> haptics;

  /// Whether something landed hard enough to whiten the screen.
  final bool flash;

  /// What the game's own rules added beyond the fields above — see
  /// [ReactionEffect].
  final List<ReactionEffect> effects;

  /// Whether this shows, sounds and does nothing.
  bool get isEmpty =>
      bursts.isEmpty &&
      lingering.isEmpty &&
      jolts.isEmpty &&
      heard.isEmpty &&
      haptics.isEmpty &&
      effects.isEmpty &&
      !flash;

  /// Bursts [bursts] and starts [lingering] in [particles]. The particles
  /// half of performing a reaction; the camera's is [feel].
  void showIn(ParticleSystem particles) {
    for (final shown in bursts) {
      particles.burst(shown.effect, shown.at, direction: shown.direction);
    }
    for (final plume in lingering) {
      particles.emitTimed(
        plume.key,
        plume.effect,
        plume.at,
        perSecond: plume.perSecond,
        seconds: plume.seconds,
      );
    }
  }

  /// Applies every jolt to [rig], and performs the haptics when [haptic] is
  /// true — a game passes its own setting.
  void feel(CameraRig? rig, {bool haptic = true}) {
    if (rig != null) {
      for (final felt in jolts) {
        felt.applyTo(rig);
      }
    }
    if (haptic) {
      for (final pulse in haptics) {
        pulse.perform();
      }
    }
  }

  /// Performs [effects], in the order the rules added them.
  void perform() {
    for (final effect in effects) {
      effect.perform();
    }
  }

  @override
  String toString() =>
      'Reaction(${bursts.length} bursts, ${lingering.length} lingering, '
      '${jolts.length} jolts, ${heard.length} heard, '
      '${effects.length} effects'
      '${flash ? ', flash' : ''})';
}
