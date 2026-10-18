/// What this game sounds like.
///
/// The bank is declared as constants so the compiler checks every reference,
/// the same way the platformer declares its own — and every file in it is
/// written by `tool/make_sounds.py`, so the licence is the repository's.
///
/// The division is the one the whole stack keeps: the simulation raises a flag
/// or reports a number, and this file decides what is heard. Nothing here is
/// allowed to change a lap time.
library;

import 'dart:math' as math;

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';

/// Every sound the racing game plays, as one definition each, and [all], the
/// bank they are loaded from.
abstract final class Sounds {
  /// The engine, recorded at a third of the revs and at most of them.
  ///
  /// The centres are not decoration: [BlendedLoop] plays a band at the ratio
  /// between what is asked for and what the band holds, so these have to be the
  /// revs the files were written at. `tool/make_sounds.py` prints them when it
  /// runs, and they are the same two numbers.
  static const double lowRevs = 0.35;

  /// The revs, as a fraction of the most, that [engineHigh] was recorded at.
  static const double highRevs = 0.85;

  /// The engine low in its range, looped and recorded at [lowRevs]; blended
  /// with [engineHigh] by how hard the car is revving.
  static const SoundDef engineLow = SoundDef(
    name: 'engine-low',
    asset: 'assets/sounds/engine_low.wav',
    loop: true,
    gain: 0.55,
    attenuation: InverseRolloff(reference: 12.0, maximum: 260.0),
  );

  /// The engine high in its range, looped and recorded at [highRevs].
  static const SoundDef engineHigh = SoundDef(
    name: 'engine-high',
    asset: 'assets/sounds/engine_high.wav',
    loop: true,
    gain: 0.55,
    attenuation: InverseRolloff(reference: 12.0, maximum: 260.0),
  );

  /// TireSet letting go. Driven by how far the car is sliding, so it is one loop
  /// held at a volume rather than a sound played on an event.
  static const SoundDef skid = SoundDef(
    name: 'skid',
    asset: 'assets/sounds/skid.wav',
    loop: true,
    gain: 0.85,
    attenuation: InverseRolloff(reference: 10.0, maximum: 160.0),
  );

  /// Off the racing surface. The other half of what tells a driver they have
  /// run wide, and the half that works when they are looking at the apex.
  static const SoundDef rumble = SoundDef(
    name: 'rumble',
    asset: 'assets/sounds/rumble.wav',
    loop: true,
    gain: 0.7,
    attenuation: InverseRolloff(reference: 10.0, maximum: 140.0),
  );

  /// One beep of the countdown, heard at the same loudness wherever the camera
  /// is.
  static const SoundDef count = SoundDef(
    name: 'count',
    asset: 'assets/sounds/count.wav',
    gain: 0.9,
    priority: 4,
    attenuation: NoAttenuation(),
  );

  /// The start, played when the lights go out; the loudest cue, and above the
  /// countdown in priority.
  static const SoundDef go = SoundDef(
    name: 'go',
    asset: 'assets/sounds/go.wav',
    gain: 1.0,
    priority: 5,
    attenuation: NoAttenuation(),
  );

  /// A lap completed by the player.
  static const SoundDef lap = SoundDef(
    name: 'lap',
    asset: 'assets/sounds/lap.wav',
    gain: 0.9,
    priority: 4,
    attenuation: NoAttenuation(),
  );

  /// A lap that beat the player's best, played in place of [lap].
  static const SoundDef best = SoundDef(
    name: 'best',
    asset: 'assets/sounds/best.wav',
    gain: 1.0,
    priority: 5,
    attenuation: NoAttenuation(),
  );

  /// A checkpoint passed by the player; quiet and low in priority, since one
  /// comes every few seconds.
  static const SoundDef checkpoint = SoundDef(
    name: 'checkpoint',
    asset: 'assets/sounds/checkpoint.wav',
    gain: 0.5,
    priority: 2,
    attenuation: NoAttenuation(),
  );

  /// A car struck hard enough to throw sparks ([Reactions.scrapeAbove]), its
  /// pitch varied a little each time so that a run of knocks does not sound
  /// like one sample repeated.
  static const SoundDef bump = SoundDef(
    name: 'bump',
    asset: 'assets/sounds/bump.wav',
    gain: 0.8,
    priority: 3,
    rateVariance: 0.12,
    attenuation: InverseRolloff(reference: 14.0, maximum: 200.0),
  );

  /// Every sound this game has, and the only list of them.
  ///
  /// A [SoundBank] rather than a `List` beside the constants above, because a
  /// second list is a second thing to keep in step — and this game's sibling
  /// once lost six definitions out of fourteen that way, and was half mute for
  /// months with nothing to notice.
  static final SoundBank all = SoundBank(<SoundDef>[
    engineLow,
    engineHigh,
    skid,
    rumble,
    count,
    go,
    lap,
    best,
    checkpoint,
    bump,
  ]);
}

/// One car's continuous noises: its engine, its tyres, and the ground under it.
///
/// One of these per car, so that the field is heard where it is — the mixer
/// does the distance and the panning, and SoLoud is asked for nothing it cannot
/// do.
final class CarVoice {
  /// Starts [vehicle]'s engine, skid and rumble loops in [scene] at the car's
  /// position, the skid and rumble silent until [update] hears a reason.
  CarVoice({required AudioScene scene, required this.vehicle})
    : _engine = BlendedLoop(
        scene: scene,
        bands: const <LoopBand>[
          LoopBand(sound: Sounds.engineLow, center: Sounds.lowRevs, width: 0.5),
          LoopBand(
            sound: Sounds.engineHigh,
            center: Sounds.highRevs,
            width: 0.5,
          ),
        ],
        at: vehicle.position,
      ),
      _skid = scene.play(Sounds.skid, vehicle.position)..gain = 0.0,
      _rumble = scene.play(Sounds.rumble, vehicle.position)..gain = 0.0;

  /// The car this voice follows: where its sounds are placed, and what its
  /// revs and slips are read from.
  final VehicleController vehicle;

  /// The engine's own mix, for a test or a debug readout.
  ///
  /// Exposed because a band mixed down to nothing has no voice at all, so
  /// anything asking "how fast is the engine playing" through the backend gets
  /// an answer only for whichever band happens to be audible.
  BlendedLoop get engine => _engine;
  final BlendedLoop _engine;
  final AudioEmitter _skid;
  final AudioEmitter _rumble;

  /// How sideways the tyres have to be before they are heard at all.
  static const double _skidFrom = 0.12;

  /// And where the noise is at its loudest.
  static const double _skidTo = 0.55;

  /// Brings every continuous sound up to date. Called once a frame.
  ///
  /// [offRoad] is the race's opinion rather than the car's, because "off the
  /// racing surface" is a lap's idea and a car has none.
  void update({required bool offRoad}) {
    // Idling counts as revs: an engine at rest is not silent, and a car whose
    // note appears only once it is moving sounds like it was pushed.
    final revs = math.max(0.12, vehicle.rpm);
    _engine.update(revs, at: vehicle.position);

    // Both slips, because a car can be sideways, or spinning its wheels, or
    // locked up, and all three squeal.
    final sideways = vehicle.slipAngle.abs();
    final spinning = vehicle.slipRatio.abs();
    final sliding = math.max(sideways, spinning * 0.7);
    final loudness = vehicle.isGrounded
        ? ((sliding - _skidFrom) / (_skidTo - _skidFrom)).clamp(0.0, 1.0)
        : 0.0;
    // Quiet at a crawl: a car turning in the pit lane is not squealing, whatever
    // the arithmetic says about the angle between where it points and where it
    // is going.
    final moving = (vehicle.speed / 8.0).clamp(0.0, 1.0);

    _skid
      ..gain = loudness * moving
      ..position.setFrom(vehicle.position);

    _rumble
      ..gain = offRoad && vehicle.isGrounded ? moving : 0.0
      ..position.setFrom(vehicle.position);
  }

  /// Stops all three loops. Call it when the car leaves the race or the scene
  /// is torn down.
  void stop() {
    _engine.stop();
    _skid.stop();
    _rumble.stop();
  }
}
