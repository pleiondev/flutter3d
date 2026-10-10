import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:vector_math/vector_math.dart';

/// Which sounds the elements make: a loop held to every fire, a loop held to
/// every fall of water, and a splash played once.
///
/// **Data, and a game's own.** [near] is a level of halls and yards; a game
/// of small stone rooms writes its own with a shorter reach. The recordings
/// are the effects package's ([effectsAssets]).
final class ElementCues {
  const ElementCues({
    required this.fire,
    required this.falls,
    required this.splash,
  });

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

  /// Looping, held to each burning thing.
  final SoundDef fire;

  /// Looping, held to each fall of water.
  final SoundDef falls;

  /// Once, for each splash heard.
  final SoundDef splash;

  /// What has to be loaded for these to play.
  List<SoundDef> get all => <SoundDef>[fire, falls, splash];
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
      _falls = HeldVoices(cues.falls, bus: bus);

  final ElementCues cues;

  /// The bus the elements play on, or null for each sound's own.
  final AudioBus? bus;

  final HeldVoices _fires;
  final HeldVoices _falls;

  /// How many voices are held, fires and falls together.
  int get held => _fires.count + _falls.count;

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
  }
}
