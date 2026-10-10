/// The crypt's fires and water heard: which recordings
/// `flutter3d_game_physics`' `ElementSounds` plays for what `PhysicsHearing` reads off the
/// effects world and the wading `CryptElements` counts.
library;

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game_physics/elements.dart' show ElementCues;

/// A fire across a room is heard; one three rooms away, through the walls the
/// mixer's occlusion takes its share of, barely.
const Attenuation _room = InverseRolloff(
  reference: 2.5,
  maximum: 30.0,
  factor: 1.3,
);

/// A looping crackle held to every burning crate, a roar to the water
/// spilling into the flooded vault, and a splash for each body that drops
/// into it and each stride taken through it.
///
/// The recordings are the effects package's own; the reach is a crypt's, of
/// small stone rooms. The torches are not here: each already has its loop in
/// `Sounds.torch`, started with the level.
const ElementCues cryptElementCues = ElementCues(
  fire: SoundDef(
    name: 'crate_fire',
    asset: '${ElementCues.effectsAssets}/fire_loop.wav',
    loop: true,
    attenuation: _room,
    priority: 3,
    maxInstances: 6,
  ),
  falls: SoundDef(
    name: 'culvert',
    asset: '${ElementCues.effectsAssets}/falls_loop.wav',
    loop: true,
    gain: 0.7,
    attenuation: InverseRolloff(reference: 2.0, maximum: 26.0, factor: 1.4),
    priority: 2,
    maxInstances: 2,
  ),
  splash: SoundDef(
    name: 'splash',
    asset: '${ElementCues.effectsAssets}/splash.wav',
    attenuation: _room,
    rateVariance: 0.12,
    priority: 4,
    maxInstances: 4,
  ),
);
