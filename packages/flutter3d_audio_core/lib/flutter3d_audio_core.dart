/// Positional audio for flutter3d, without a backend.
///
/// The spatialisation — attenuation, panning, occlusion and voice limiting —
/// and the mixer's buses, with [AudioBackend] as the seam a backend fills.
/// `flutter3d_audio` re-exports all of it and adds the SoLoud backend; a
/// package that only names buses, sounds or a scene depends on this one and
/// carries no native audio code.
library;

export 'src/attenuation.dart';
export 'src/audio_scene.dart';
export 'src/backend.dart';
export 'src/engine_sound.dart';
export 'src/listener.dart';
export 'src/mixer.dart';
export 'src/sound.dart';
export 'src/sound_bank.dart';
