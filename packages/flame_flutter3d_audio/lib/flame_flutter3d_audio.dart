/// Sound for a Flame game bridged to flutter3d.
///
/// [AudioSceneComponent] is the game's sound: silent until the player's
/// first input opens the speakers, heard from the game's 3D camera, mixed
/// after everything has moved. [SoundEmitterComponent] is a loop that plays
/// while its component lives and asks to be heard.
///
/// **A package of its own**, beside `flame_flutter3d` rather than in it,
/// because sound brings SoLoud's native library with it, and a bridged game
/// with no sound should not carry it.
library;

export 'src/audio_scene_component.dart';
export 'src/sound_emitter_component.dart';
