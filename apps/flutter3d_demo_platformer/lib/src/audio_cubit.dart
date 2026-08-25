import 'dart:async';

import 'package:flutter3d_app/flutter3d_app.dart'; // applySavedVolumes
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart'; // GameConfig
import 'package:flutter_bloc/flutter_bloc.dart';

import 'sounds.dart';

/// Whether the game can be heard, and whether its music has started.
///
/// Two flags rather than the scene itself: the scene is played through sixty
/// times a second, and a state object that carried it would be rebuilding the
/// widget tree at that rate — the line `ARCHITECTURE.md` §11.3 draws through this
/// package. What changes rarely goes in the state; what is touched every frame
/// stays a field on the cubit and is reached directly.
final class AudioReady {
  const AudioReady({this.open = false, this.musicPlaying = false});

  /// Whether real speakers were found. False is not a failure — see
  /// [AudioCubit.open].
  final bool open;

  final bool musicPlaying;

  AudioReady copyWith({bool? open, bool? musicPlaying}) => AudioReady(
        open: open ?? this.open,
        musicPlaying: musicPlaying ?? this.musicPlaying,
      );

  @override
  bool operator ==(Object other) =>
      other is AudioReady &&
      other.open == open &&
      other.musicPlaying == musicPlaying;

  @override
  int get hashCode => Object.hash(open, musicPlaying);
}

/// Everything the game is heard through.
///
/// **Five fields and three methods that only ever spoke to each other.** The
/// scene, the listener, the backend, the music flag and the volumes sat in
/// `_GameScreenState` between the renderer and the pad; nothing outside this
/// group ever read one of them except to play a sound or aim the ears.
///
/// A cubit rather than a plain object because opening speakers and starting the
/// music are screen state — the same class of thing as loading a level or
/// opening the settings, which is what `flutter_bloc` is here for. The scene and
/// the listener stay fields: they are touched every frame, and the boundary in
/// `ARCHITECTURE.md` §11.3 is explicit that per-frame state does not go through a
/// cubit.
final class AudioCubit extends Cubit<AudioReady> {
  AudioCubit() : super(const AudioReady());

  /// Silent until real speakers are found, which is a perfectly good way to
  /// play.
  AudioScene scene = AudioScene(backend: SilentBackend());

  /// Where the player is listening from. Aimed once a frame, from the camera.
  final AudioListener ears = AudioListener();

  /// The mixer the settings panel offers, which is the scene's own.
  Mixer get mixer => scene.mixer;

  SoLoudBackend? _backend;

  /// Finds real speakers, or stays silent.
  ///
  /// Opened by `flutter3d_audio`, which owns the trap: no device, no plugin, no
  /// native assets — every one of those is a launch that dies for want of a
  /// sound unless somebody catches it, and all three games had written the same
  /// catch. Null means silent.
  ///
  /// [stillWanted] is asked after the await, because a widget can be gone by
  /// the time speakers answer.
  Future<void> open(
    GameConfig config, {
    required bool Function() stillWanted,
  }) async {
    final speakers = await openSpeakers(bank: Sounds.all, mixer: scene.mixer);
    if (speakers == null || !stillWanted()) return;
    _backend = speakers.backend;
    scene = speakers.scene;
    applyVolumes(config);
    emit(state.copyWith(open: true));
  }

  /// Starts the loop, once, whichever of the two arrives second.
  ///
  /// The audio device and the first level open in parallel and either may win,
  /// so both call this and the flag decides. Once only: a looping sound played
  /// twice is the same sound out of phase with itself.
  ///
  /// [levelReady] is the other half of the race, asked rather than held so that
  /// this does not need to know what a level is.
  void startMusic({required bool levelReady}) {
    if (state.musicPlaying || !levelReady || _backend == null) return;
    // Position is immaterial — the track carries [NoAttenuation] — and the
    // listener is where a sound with no place in the world belongs.
    scene.play(Sounds.music, ears.position);
    emit(state.copyWith(musicPlaying: true));
  }

  /// Copies the saved volumes into the mixer the scene is reading.
  ///
  /// The list of buses is `flutter3d_ui`'s, beside the panel that offers them:
  /// there were four copies of it and they had already disagreed once.
  void applyVolumes(GameConfig config) =>
      applySavedVolumes(config, scene.mixer);

  @override
  Future<void> close() {
    scene.stopAll();
    // The backend is this cubit's to shut down: it opened it.
    unawaited(_backend?.dispose());
    return super.close();
  }
}
