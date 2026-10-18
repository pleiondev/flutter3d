/// A soundtrack for flutter3d games: sounds keyed by events, footsteps paid
/// for in metres, and sounds with a lifetime.
///
/// A [CueSheet] keeps what each event sounds like; [SoundtrackPlugin] hears
/// it from the engine's bus on its frame channel and plays it. [Sounding] and
/// [SustainedVoices] are for sounds that outlive a step — a door grinding
/// open. The fires and water `flutter3d_effects` reports are played by
/// `ElementSounds`, in `flutter3d_game_physics`' `elements.dart`.
///
/// The game's own cue lists — its `SoundDef`s and which event plays which —
/// stay with the game, as data. The sound types are `flutter3d_audio_core`'s,
/// and a game that writes a sheet's `SoundDef`s imports them from there.
library;

export 'src/soundtrack/cue_sheet.dart';
export 'src/soundtrack/footsteps.dart';
export 'src/soundtrack/soundtrack_plugin.dart';
export 'src/soundtrack/sustained.dart';
