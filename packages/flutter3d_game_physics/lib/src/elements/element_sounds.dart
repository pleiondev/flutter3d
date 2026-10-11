import 'dart:math' as math;

import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:vector_math/vector_math.dart';

/// Which sounds the elements make: a loop held to every fire, a loop held to
/// every fall of water, a splash played once, and a loop held to every body
/// wading through water.
///
/// **Data, and a game's own.** [near] is a level of halls and yards; a game
/// of small stone rooms writes its own with a shorter reach, and [circuit] is
/// a race heard from the stands. The recordings are the effects package's
/// ([effectsAssets]).
final class ElementCues {
  const ElementCues({
    required this.fire,
    required this.falls,
    required this.splash,
    SoundDef? wash,
    this.wading = WadingHearing.standard,
  }) : _wash = wash; // ignore: prefer_initializing_formals

  /// Where `flutter3d_effects` keeps its recordings, as a bundle path.
  static const String effectsAssets = 'packages/flutter3d_effects/assets';

  /// Full within a few metres, halving with each doubling of distance past
  /// that, gone across a hall.
  static const Attenuation _near = InverseRolloff(
    reference: 4.0,
    maximum: 50.0,
  );

  /// The effects package's own recordings, heard across a hall.
  static const ElementCues near = ElementCues(
    fire: SoundDef(
      name: 'fire',
      asset: '$effectsAssets/fire_loop.wav',
      loop: true,
      gain: 0.7,
      attenuation: _near,
      maxInstances: 8,
    ),
    falls: SoundDef(
      name: 'falls',
      asset: '$effectsAssets/falls_loop.wav',
      loop: true,
      attenuation: InverseRolloff(reference: 6.0, maximum: 70.0),
      maxInstances: 4,
    ),
    splash: SoundDef(
      name: 'splash',
      asset: '$effectsAssets/splash.wav',
      attenuation: _near,
      rateVariance: 0.1,
      maxInstances: 3,
    ),
  );

  /// A race heard across a circuit: a wreck burning from far down the
  /// straight, the wheels of a car ploughing through a ford held as falling
  /// water is, and its splash going in.
  static const ElementCues circuit = ElementCues(
    fire: SoundDef(
      name: 'fire',
      asset: '$effectsAssets/fire_loop.wav',
      loop: true,
      attenuation: InverseRolloff(reference: 6.0, maximum: 120.0),
      maxInstances: 6,
    ),
    falls: SoundDef(
      name: 'wash',
      asset: '$effectsAssets/falls_loop.wav',
      loop: true,
      attenuation: InverseRolloff(reference: 8.0, maximum: 140.0),
      maxInstances: 4,
    ),
    splash: SoundDef(
      name: 'splash',
      asset: '$effectsAssets/splash.wav',
      priority: 3,
      rateVariance: 0.12,
      attenuation: InverseRolloff(reference: 8.0, maximum: 160.0),
    ),
    wading: WadingHearing.car,
  );

  /// Looping, held to each burning thing.
  final SoundDef fire;

  /// Looping, held to each fall of water.
  final SoundDef falls;

  /// Once, for each splash heard.
  final SoundDef splash;

  /// Looping, held to each body wading ([ElementSounds.wade]): [falls]
  /// unless a game gives its own. Held apart from the falls either way.
  SoundDef get wash => _wash ?? falls;
  final SoundDef? _wash;

  /// How loud a body wading is, by how fast it goes.
  final WadingHearing wading;

  /// What has to be loaded for these to play, each once.
  List<SoundDef> get all => <SoundDef>{fire, falls, splash, wash}.toList();
}

/// How a body wading through water is heard, by how fast it goes: what
/// [ElementSounds.wade] plays.
///
/// **The game's mapping, as `HearingScale` is for what the physics does.**
/// [standard] is a person or an animal; [car] a car through a ford.
final class WadingHearing {
  const WadingHearing({
    required this.splashFrom,
    required this.washFrom,
    required this.loud,
    required this.washLoud,
    required this.washFast,
    this.hush = 0.4,
  });

  /// A walker: a splash from an ordinary walk on dry ground, 1.4 m/s
  /// (Mohler et al., Exp. Brain Res. 181, 2007), heard washing from half
  /// that, and as loud and as fast as it plays at a run of 6 m/s.
  static const WadingHearing standard = WadingHearing(
    splashFrom: 1.4,
    washFrom: 0.7,
    loud: 6.0,
    washLoud: 6.0,
    washFast: 6.0,
  );

  /// A car: a splash from a jog's pace, loudest at a hundred and forty
  /// kilometres an hour.
  static const WadingHearing car = WadingHearing(
    splashFrom: 4.0,
    washFrom: 3.0,
    loud: 40.0,
    washLoud: 35.0,
    washFast: 60.0,
  );

  /// The least speed, m/s, at which going into water splashes.
  final double splashFrom;

  /// The least speed, m/s, at which a body in water is heard washing.
  final double washFrom;

  /// The speed, m/s, at which a body goes in as loud as a splash plays; a
  /// splash is never quieter than three tenths.
  final double loud;

  /// The speed, m/s, at which the wash is as loud as it plays, and the one
  /// at which it plays three tenths fast; it is never quieter than a fifth.
  final double washLoud, washFast;

  /// How long, s, after one splash a body going in again is not heard
  /// splashing: a car hopping along the edge of a puddle is one splash.
  final double hush;
}

/// A body moving through or by water this frame, as [ElementSounds.wade]
/// hears it: the game's key for it, where it is, whether it is in water and
/// how fast it goes, m/s.
final class Wader {
  const Wader({
    required this.key,
    required this.at,
    required this.wet,
    required this.speed,
  });

  final int key;
  final Vector3 at;
  final bool wet;
  final double speed;
}

/// The elements heard: what [PhysicsHearing] reads off the effects world each
/// frame, played through a game's [AudioScene].
///
/// A looping voice held to every fire and every fall of water, as loud and
/// as fast as the physics says, begun when it is first heard and stopped when
/// it goes quiet, and a splash played once for each one heard.
///
/// Everything plays on [bus] — each sound's own unless one is given — so an
/// "under water" snapshot or a ducking rule reaches the elements as it
/// reaches the rest of the mix.
final class ElementSounds {
  ElementSounds([this.cues = ElementCues.near, this.bus])
    : _fires = HeldVoices(cues.fire, bus: bus),
      _falls = HeldVoices(cues.falls, bus: bus),
      _washes = HeldVoices(cues.wash, bus: bus);

  final ElementCues cues;

  /// The bus the elements play on, or null for each sound's own.
  final AudioBus? bus;

  final HeldVoices _fires;
  final HeldVoices _falls;
  final HeldVoices _washes;

  /// How many voices are held, fires, falls and washes together.
  int get held => _fires.count + _falls.count + _washes.count;

  /// Each wader's last frame: whether it was in water, and how long until
  /// going in is heard again.
  final Map<int, ({bool wet, double hush})> _waders =
      <int, ({bool wet, double hush})>{};

  /// This frame's [waders] heard on [scene], [dt] seconds after the last:
  /// a splash as each goes into water at [WadingHearing.splashFrom] or
  /// faster, as loud as it goes, and not again for [WadingHearing.hush]; a
  /// wash ([ElementCues.wash]) held to each in water at
  /// [WadingHearing.washFrom] or faster, louder and faster the faster it
  /// goes; a wader not given this frame is let go.
  ///
  /// What racing played of its cars through a ford, folded in here: the
  /// game says where its bodies are and whether they are in water, and
  /// this hears them.
  void wade(AudioScene scene, Iterable<Wader> waders, double dt) {
    final hearing = cues.wading;
    final washing = <Held>[];
    final seen = <int>{};
    for (final w in waders) {
      seen.add(w.key);
      final was = _waders[w.key];
      var hush = math.max(0.0, (was?.hush ?? 0.0) - dt);
      final goesIn = w.wet && !(was?.wet ?? false);
      if (goesIn && w.speed > hearing.splashFrom && hush <= 0.0) {
        hush = hearing.hush;
        scene.play(cues.splash, w.at, bus: bus).gain = (w.speed / hearing.loud)
            .clamp(0.3, 1.0);
      }
      _waders[w.key] = (wet: w.wet, hush: hush);
      if (w.wet && w.speed > hearing.washFrom) {
        washing.add((
          key: w.key,
          at: Vector3.copy(w.at),
          gain: (w.speed / hearing.washLoud).clamp(0.2, 1.0),
          rate: 0.9 + 0.3 * (w.speed / hearing.washFast).clamp(0.0, 1.0),
        ));
      }
    }
    _waders.removeWhere((key, _) => !seen.contains(key));
    _washes.hold(scene, washing);
  }

  /// This frame's fires, falls and splashes played on [scene], as [hearing]
  /// heard them.
  ///
  /// [splashes] are more of them the game counts itself — a stride through
  /// water. A fire [heldElsewhere] says yes to already has a voice of its
  /// own, as a torch with its loop started with the level does.
  void play(
    AudioScene scene,
    PhysicsHearing hearing, {
    Iterable<Audible> splashes = const <Audible>[],
    bool Function(Audible fire)? heldElsewhere,
  }) => hear(
    scene,
    fires: hearing.fires,
    falls: hearing.falls,
    splashes: hearing.splashes.followedBy(splashes),
    heldElsewhere: heldElsewhere,
  );

  /// [fires], [falls] and [splashes] played on [scene]: what [play] does with
  /// a [PhysicsHearing], for whatever else reports in the same shape.
  void hear(
    AudioScene scene, {
    Iterable<Audible> fires = const <Audible>[],
    Iterable<Audible> falls = const <Audible>[],
    Iterable<Audible> splashes = const <Audible>[],
    bool Function(Audible fire)? heldElsewhere,
  }) {
    _fires.hold(scene, <Held>[
      for (final h in fires)
        if (heldElsewhere == null || !heldElsewhere(h)) _held(h),
    ]);
    _falls.hold(scene, falls.map(_held));
    for (final s in splashes) {
      scene.play(cues.splash, s.at, bus: bus)
        ..gain = s.loudness
        ..rate = s.rate;
    }
  }

  static Held _held(Audible h) =>
      (key: h.key, at: Vector3.copy(h.at), gain: h.loudness, rate: h.rate);

  /// Every voice stopped, for a level taken down.
  void silence() {
    _fires.silence();
    _falls.silence();
    _washes.silence();
    _waders.clear();
  }
}
