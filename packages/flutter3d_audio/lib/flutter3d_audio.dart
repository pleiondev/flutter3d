/// Positional audio for flutter3d.
///
/// The spatialisation — attenuation, panning, occlusion and voice limiting —
/// is here; making noise is a backend's job. See [AudioScene] for why the
/// geometry is computed in Dart rather than handed to the audio engine.
library;

export 'src/attenuation.dart';
export 'src/audio_scene.dart';
export 'src/backend.dart';
export 'src/engine_sound.dart';
export 'src/listener.dart';
export 'src/mixer.dart';
export 'src/soloud_backend.dart';
export 'src/sound.dart';
export 'src/sound_bank.dart';
