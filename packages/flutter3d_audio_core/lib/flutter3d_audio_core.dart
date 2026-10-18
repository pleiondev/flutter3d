/// Positional audio for flutter3d, without a backend.
///
/// ## The audio model
///
/// * **Components of the scene.** An [AudioListener] and any number of
///   [AudioEmitter]s, each placed by hand or following a node's world
///   matrix ([PoseSource]), with a velocity for doppler.
/// * **A spatial renderer** ([SpatialRenderer]) turns where a sound is into
///   how it is heard. Today's is [EqualPowerPanner] — distance attenuation
///   ([Attenuation]), occlusion and an equal-power pan; binaural (HRTF) and
///   propagation renderers arrive later behind the same class.
/// * **A mixer** ([Mixer]) of buses in a tree, each with the player's
///   volume, the game's level and effect slots ([BusEffect]); named
///   [MixSnapshot]s blended in and out; [DuckRule]s.
/// * **A backend** ([AudioBackend]) that makes the noise, with
///   [MixingBackend] and [DirectionalBackend] as what one opts into.
/// * **The loop.** [AudioPlugin] runs the mix in the engine loop's `audio`
///   phase.
///
/// The units are the engine's: metres, seconds, hertz, radians, linear gain
/// and decibels — see `src/units.dart`, and [decibelsToGain].
///
/// `flutter3d_audio` re-exports all of it and adds the SoLoud backend; a
/// package that only names buses, sounds or a scene depends on this one and
/// carries no native audio code.
library;

export 'src/attenuation.dart';
export 'src/audio_plugin.dart';
export 'src/audio_scene.dart';
export 'src/backend.dart';
export 'src/bus_effect.dart';
export 'src/engine_sound.dart';
export 'src/held_voices.dart';
export 'src/listener.dart';
export 'src/mix_snapshot.dart';
export 'src/mixer.dart';
export 'src/pose.dart' show PoseSource;
export 'src/sound.dart';
export 'src/sound_bank.dart';
export 'src/spatial.dart';
export 'src/units.dart';
