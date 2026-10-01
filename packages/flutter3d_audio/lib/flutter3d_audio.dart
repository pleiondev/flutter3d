/// Positional audio for flutter3d.
///
/// The spatialisation — attenuation, panning, occlusion and voice limiting —
/// is here; making noise is a backend's job. See [AudioScene] for why the
/// geometry is computed in Dart rather than handed to the audio engine.
///
/// Everything but the SoLoud backend lives in `flutter3d_audio_core` and is
/// re-exported here, so the types are the same whichever package a caller
/// imports them through.
library;

export 'package:flutter3d_audio_core/flutter3d_audio_core.dart';

export 'src/soloud_backend.dart';
export 'src/speakers.dart';
