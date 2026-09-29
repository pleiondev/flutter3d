/// Where in a Flame frame each part of the bridge updates, by name.
///
/// **What every bridged game worked out for itself.** Flame updates a
/// game's children by ascending priority, and the bridge's parts have an
/// order that matters: the phone's stick is read before anything moves, the
/// simulation steps before whatever reads it, the camera follows once the
/// craft have moved, the sound mixes after all of it, and the clock that
/// draws the 3D frame comes last. Each game that used the bridge picked its
/// own numbers for that (the arcade -120 and -110, the example -100) and
/// each component's doc said "give it a priority below the readers". These
/// are those numbers, and the bridge's components take them by default.
///
/// A game's own components sit at Flame's default of 0, between the
/// simulation and the camera, which is where a player's craft wants to be.
abstract final class BridgePriority {
  /// A touch stick's deflection read into the input state: before anything
  /// that reads input.
  static const int input = -(1 << 30);

  /// `ActorSystemComponent`: the actors step before the bodies they push.
  static const int actors = -1100;

  /// `PhysicsStepComponent`: the solver, before anything reads a body.
  static const int physics = -1000;

  /// `ChaseCameraComponent` and `CameraSyncComponent`: after the craft they
  /// follow have moved this frame.
  static const int camera = 1000;

  /// A game's sound mixing, after everything that makes one has spoken.
  static const int audio = 1 << 19;

  /// `BridgeClock`, which draws the 3D frame: last of all.
  static const int clock = 1 << 20;
}
