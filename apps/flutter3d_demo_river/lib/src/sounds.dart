part of 'river_game.dart';

/// Everything River Sortie can say, written by `tool/make_sounds.py`.
///
/// **The engine sits under everything else.** It never stops, so it is the
/// quietest thing in the mix: a drone as loud as a shot buries the shot, and
/// the first version of this bank did exactly that.
///
/// **None of it fades with distance.** A cartridge had one speaker and no
/// idea where anything was, and a river seen from behind the jet has nothing
/// to gain from panning a tanker a few metres left; every sound is played at
/// the listener with [NoAttenuation].
abstract final class Sounds {
  static const SoundDef engine = SoundDef(
    name: 'engine',
    asset: 'assets/sounds/engine.wav',
    loop: true,
    gain: 0.16,
    attenuation: NoAttenuation(),
    priority: 3,
    maxInstances: 1,
  );

  static const SoundDef refuel = SoundDef(
    name: 'refuel',
    asset: 'assets/sounds/refuel.wav',
    loop: true,
    gain: 0.5,
    attenuation: NoAttenuation(),
    priority: 2,
    maxInstances: 1,
  );

  static const SoundDef lowFuel = SoundDef(
    name: 'low-fuel',
    asset: 'assets/sounds/low_fuel.wav',
    loop: true,
    gain: 0.4,
    attenuation: NoAttenuation(),
    priority: 3,
    maxInstances: 1,
  );

  static const SoundDef shot = SoundDef(
    name: 'shot',
    asset: 'assets/sounds/shot.wav',
    gain: 0.6,
    attenuation: NoAttenuation(),
    maxInstances: 3,
    rateVariance: 0.04,
  );

  static const SoundDef boom = SoundDef(
    name: 'boom',
    asset: 'assets/sounds/boom.wav',
    gain: 0.9,
    attenuation: NoAttenuation(),
    priority: 1,
    maxInstances: 3,
    rateVariance: 0.08,
  );

  static const SoundDef bigBoom = SoundDef(
    name: 'big-boom',
    asset: 'assets/sounds/big_boom.wav',
    gain: 1.0,
    attenuation: NoAttenuation(),
    priority: 2,
    maxInstances: 2,
  );

  static const SoundDef crash = SoundDef(
    name: 'crash',
    asset: 'assets/sounds/crash.wav',
    gain: 1.0,
    attenuation: NoAttenuation(),
    priority: 5,
    maxInstances: 1,
  );

  static const SoundDef spark = SoundDef(
    name: 'spark',
    asset: 'assets/sounds/spark.wav',
    gain: 0.45,
    attenuation: NoAttenuation(),
    maxInstances: 2,
  );

  static const SoundDef tracer = SoundDef(
    name: 'tracer',
    asset: 'assets/sounds/tracer.wav',
    gain: 0.35,
    attenuation: NoAttenuation(),
    maxInstances: 3,
  );

  static const SoundDef level = SoundDef(
    name: 'level',
    asset: 'assets/sounds/level.wav',
    gain: 0.5,
    attenuation: NoAttenuation(),
    priority: 4,
    maxInstances: 1,
  );

  static const SoundDef extraJet = SoundDef(
    name: 'extra-jet',
    asset: 'assets/sounds/extra_jet.wav',
    gain: 0.5,
    attenuation: NoAttenuation(),
    priority: 4,
    maxInstances: 1,
  );

  static final SoundBank all = SoundBank(<SoundDef>[
    engine,
    refuel,
    lowFuel,
    shot,
    boom,
    bigBoom,
    crash,
    spark,
    tracer,
    level,
    extraJet,
  ]);
}

/// The game's voice: the three loops its state holds open, and a one-shot
/// for each event.
///
/// Until [RiverGame.hearWith] hands it a real scene it speaks into a
/// [SilentBackend], which is also how the tests hear it.
extension RiverGameSound on RiverGame {
  /// Swaps the silent scene for [scene], once the speakers are open. The
  /// loops playing on the old one stop and start again on the new.
  void hearWith(AudioScene scene) {
    for (final loop in <SoundEmitter?>[_engineLoop, _refuelLoop, _alarmLoop]) {
      loop?.stop();
    }
    _engineLoop = _refuelLoop = _alarmLoop = null;
    audio = scene;
  }

  void _say(SoundDef sound) => audio.play(sound, _ears.position);

  /// Opens or closes each loop by the state it stands for, bends the engine
  /// with the throttle, and hands the scene its frame.
  void _listen() {
    final flying = phase == Phase.flying;
    _engineLoop = _hold(_engineLoop, Sounds.engine, open: flying);
    _refuelLoop = _hold(_refuelLoop, Sounds.refuel, open: flying && refuelling);
    _alarmLoop = _hold(
      _alarmLoop,
      Sounds.lowFuel,
      open: flying && run.fuelLow && !refuelling,
    );
    final throttle =
        ((speed - RiverGame.slowSpeed) /
                (RiverGame.fastSpeed - RiverGame.slowSpeed))
            .clamp(0.0, 1.0);
    _engineLoop?.rate = 0.75 + 0.6 * throttle;

    if (run.reserve > _reserveHeard) _say(Sounds.extraJet);
    _reserveHeard = run.reserve;
    audio.update(_ears);
  }

  SoundEmitter? _hold(
    SoundEmitter? loop,
    SoundDef sound, {
    required bool open,
  }) {
    if (open) return loop ?? audio.play(sound, _ears.position);
    loop?.stop();
    return null;
  }
}
