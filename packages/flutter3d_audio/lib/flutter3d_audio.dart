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

// Named, so a type added to the audio core is not this package's API until
// it is listed here too.
export 'package:flutter3d_audio_core/flutter3d_audio_core.dart'
    show
        Attenuation,
        AudioBackend,
        AudioBus,
        AudioEmitter,
        AudioListener,
        AudioPlugin,
        AudioScene,
        BlendedLoop,
        BusEffect,
        DirectionalBackend,
        DuckRule,
        EqualPowerPanner,
        ExponentialRolloff,
        Heard,
        Held,
        HeldVoices,
        InverseRolloff,
        LinearRolloff,
        LoopBand,
        LowPassEffect,
        MixSnapshot,
        Mixer,
        MixingBackend,
        NoAttenuation,
        PoseSource,
        ReverbEffect,
        SilentBackend,
        SilentVoice,
        SoundBank,
        SoundDef,
        SpatialQuery,
        SpatialRenderer,
        SpatialResult,
        VoiceId,
        decibelsToGain,
        gainToDecibels,
        silenceDecibels,
        speedOfSoundInAir;

export 'src/soloud_backend.dart';
export 'src/speakers.dart';
