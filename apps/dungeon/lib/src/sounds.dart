import 'package:flutter3d_audio/flutter3d_audio.dart';

/// Everything the crypt can make a noise about.
///
/// Constants so every reference is checked by the compiler, the way the
/// weapons and the monsters are declared. The files are synthesised by
/// tool/make_sounds.py — crude on purpose, and meant to be replaced, but a
/// game with crude sound reads as a game and a silent one reads as broken.
abstract final class Sounds {
  /// Heard across a room but not across the level.
  static const Attenuation nearby = InverseRolloff(
    reference: 2.0,
    maximum: 26.0,
    factor: 1.4,
  );

  /// Machinery, which carries further than a footstep.
  static const Attenuation machinery = InverseRolloff(
    reference: 3.0,
    maximum: 40.0,
  );

  static const SoundDef pistol = SoundDef(
    name: 'pistol',
    asset: 'assets/sounds/pistol.wav',
    attenuation: nearby,
    priority: 6,
    maxInstances: 3,
  );

  static const SoundDef shotgun = SoundDef(
    name: 'shotgun',
    asset: 'assets/sounds/shotgun.wav',
    attenuation: machinery,
    priority: 6,
    maxInstances: 2,
  );

  /// While a door or a lift is travelling. Looping, and stopped by hand when
  /// the thing stops — which is why the emitter is kept rather than fired and
  /// forgotten.
  static const SoundDef stoneMove = SoundDef(
    name: 'stone_move',
    asset: 'assets/sounds/stone_move.wav',
    attenuation: machinery,
    loop: true,
    priority: 4,
    maxInstances: 3,
  );

  static const SoundDef stoneStop = SoundDef(
    name: 'stone_stop',
    asset: 'assets/sounds/stone_stop.wav',
    attenuation: machinery,
    priority: 5,
  );

  static const SoundDef monsterPain = SoundDef(
    name: 'monster_pain',
    asset: 'assets/sounds/monster_pain.wav',
    attenuation: nearby,
    priority: 3,
    maxInstances: 3,
  );

  static const SoundDef monsterDie = SoundDef(
    name: 'monster_die',
    asset: 'assets/sounds/monster_die.wav',
    attenuation: nearby,
    priority: 7,
    maxInstances: 4,
  );

  /// Loudest of the lot regardless of distance, because it is the game
  /// answering something the player just did.
  static const SoundDef pickup = SoundDef(
    name: 'pickup',
    asset: 'assets/sounds/pickup.wav',
    attenuation: NoAttenuation(),
    priority: 9,
    maxInstances: 2,
  );

  static const SoundDef locked = SoundDef(
    name: 'locked',
    asset: 'assets/sounds/locked.wav',
    attenuation: NoAttenuation(),
    priority: 9,
    maxInstances: 1,
  );

  /// One per torch, running for ever. What makes the mixer's voice limit earn
  /// its keep: five torches are five loops competing with everything else.
  static const SoundDef torch = SoundDef(
    name: 'torch',
    asset: 'assets/sounds/torch_loop.wav',
    attenuation: InverseRolloff(reference: 1.5, maximum: 12.0, factor: 2.0),
    loop: true,
    priority: 1,
    maxInstances: 6,
  );

  static const List<SoundDef> all = <SoundDef>[
    pistol,
    shotgun,
    stoneMove,
    stoneStop,
    monsterPain,
    monsterDie,
    pickup,
    locked,
    torch,
  ];
}
