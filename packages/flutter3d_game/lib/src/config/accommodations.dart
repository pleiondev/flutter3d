import 'package:flutter/widgets.dart';

/// What the player has already told the operating system.
///
/// **The setting a game should not make anybody find twice.** Somebody who is
/// made ill by moving pictures has turned reduce-motion on in the system
/// settings, probably years ago, and a game that ignores it and offers its own
/// slider three menus deep has asked them to solve the same problem again — in
/// a menu they may have to get through a moving camera to reach.
///
/// ## A default, never an override
///
/// The system answer is the *fallback* a game uses when the player has not said
/// otherwise, which is exactly the shape `GameConfig.settingOf` already has:
///
/// ```dart
/// rig.motion = config.settingOf('a11y.cameraMotion', system.cameraMotion);
/// ```
///
/// The other way round — the system flag winning over a slider the player just
/// moved — would be the game arguing with them, and the argument is unwinnable
/// because they cannot see why it is happening.
///
/// ## Only what a game can act on
///
/// Flutter reports several accessibility features; this names the ones this
/// engine has somewhere to put. `boldText` and `highContrast` are not here
/// because nothing yet reads them, and a field nobody reads is a promise nobody
/// keeps.
final class Accommodations {
  const Accommodations({this.reduceMotion = false});

  /// What the platform says, or the defaults where there is no platform to ask.
  ///
  /// `MediaQuery.maybeDisableAnimationsOf` rather than the throwing form: a game
  /// mounted outside a `MediaQuery` — a test, a golden — should get the
  /// unaccommodated defaults rather than an exception from an accessibility
  /// feature, which would be a particularly poor way to fail.
  factory Accommodations.of(BuildContext context) => Accommodations(
    reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
  );

  /// Whether the player has asked for less movement on screen.
  ///
  /// On Apple's platforms this is Reduce Motion, on Android it is the animator
  /// duration scale set to nought, and Flutter reports both as the same flag.
  final bool reduceMotion;

  /// How much of a camera's involuntary movement to keep by default.
  ///
  /// Nought when the player has asked for less movement, and that is the whole
  /// mapping: a camera that shakes on every landing is precisely what the system
  /// setting is about. See `CameraRig.motion` for what is and is not scaled.
  double get cameraMotion => reduceMotion ? 0.0 : 1.0;

  /// How much of a full-screen flash to keep by default.
  ///
  /// Separate from [cameraMotion] because they are different harms — a flash is
  /// a photosensitivity question and a moving camera is a vestibular one — and
  /// separate even though one flag drives both today, so that the day a platform
  /// reports them apart, the two callers do not have to be found again.
  double get screenFlash => reduceMotion ? 0.0 : 1.0;
}
