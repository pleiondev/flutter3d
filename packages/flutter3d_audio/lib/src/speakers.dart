import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show IssueSink, ResourceException;
import 'package:flutter3d_matter/flutter3d_matter.dart' show WorldProperties;
import 'package:vector_math/vector_math.dart';

import 'soloud_backend.dart';

/// The device a game plays through, opened, with the scene playing through
/// it.
///
/// **Three games wrote this and all three wrote the same trap around it.** The
/// backend throws when there is no audio device — a headless machine, a
/// container, a build whose plugin never linked — and a game that lets that
/// through dies on launch for want of a sound. So the throw is one type,
/// [AudioDeviceException], and a game catches it and plays silent, which is a
/// perfectly good way to play: every call into an `AudioScene` a game never
/// got is a call it simply does not make.
///
/// ```dart
/// try {
///   speakers = await openSpeakers(bank: bank);
/// } on AudioDeviceException catch (error) {
///   issues(Issue('no sound: ${error.message}'));
/// }
/// ```
///
/// The trap this repository has paid for twice, kept here where it is read
/// rather than in three comments: **a plugin added to an already built
/// application does not bring its native framework with it**, and the only
/// symptom is one line about "no available native assets" and then nothing at
/// all. If that is what the exception's cause says, the answer is
/// `flutter clean`.
///
/// [world] is the air the scene's sounds travel in (`AudioScene.world`): the
/// standard world unless a game hands in its own, and settable on the scene
/// afterwards, for a level that brings its own air.
///
/// Throws [AudioDeviceException] when the device does not open; nothing is
/// left open then.
Future<Speakers> openSpeakers({
  required SoundBank bank,
  Mixer? mixer,
  int maxVoices = 24,
  double Function(Vector3 from, Vector3 to)? occlusion,
  IssueSink? onIssue,
  SpatialRenderer spatial = const EqualPowerPanner(),
  WorldProperties? world,
}) async {
  final backend = SoLoudBackend(onIssue: onIssue);
  try {
    await backend.open();
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(
      AudioDeviceException(
        'the audio device did not open, so there is no sound',
        cause: error,
      ),
      stackTrace,
    );
  }

  final scene = AudioScene(
    backend: backend,
    mixer: mixer,
    maxVoices: maxVoices,
    occlusion: occlusion,
    spatial: spatial,
    world: world,
  );
  await scene.preload(bank);
  return Speakers(backend: backend, scene: scene);
}

/// No audio device would open: a headless machine, a container, a build
/// whose audio plugin never linked. A game catches it and plays silent.
final class AudioDeviceException extends ResourceException {
  /// An exception saying why there is no sound, with the backend's own
  /// error as [cause] when there was one.
  const AudioDeviceException(this.message, {this.cause});

  @override
  final String message;

  @override
  final Object? cause;
}

/// What [openSpeakers] hands back: the device, and the scene playing through it.
///
/// Both, because a game needs the one to pause and dispose and the other to
/// play, and handing back only the scene is how a backend gets left open when
/// the window closes. [backend] is any [AudioBackend], so a test or a host
/// with its own device hands one in the same shape.
final class Speakers {
  /// The pair of an open [backend] and the [scene] playing through it.
  const Speakers({required this.backend, required this.scene});

  /// The device the scene plays through.
  final AudioBackend backend;

  /// The scene: play, place and mix here.
  final AudioScene scene;

  /// Holds every voice where it is: the view paused, the application went
  /// to the background, a route covered the game, the player opened a menu.
  ///
  /// **Called by the game, not for it.** `Flutter3dView.onPausedChanged` is
  /// where a view says it stopped being shown or the application left the
  /// foreground; a game wires it here (`(paused) => paused ?
  /// speakers.pause() : speakers.resume()`), and a pause menu calls it too.
  ///
  /// **What it holds.** Every voice the device is playing stops at the
  /// sample it was on, loops included, and a voice the scene starts while
  /// paused — a sound the game plays under the menu — is held from its first
  /// sample rather than played over it (`AudioBackend.pause`).
  ///
  /// **What it does not.** The [scene] is not paused: an
  /// `AudioScene.update` still mixes, voices still change gain, pan and
  /// muffle, and the ones out of range are still stopped, so on [resume]
  /// the voices go on as the mix last left them, not as they were when the
  /// pause began. A game that wants the mix to dip under its pause menu
  /// blends a mix snapshot in alongside. Nothing is released either: a
  /// pause holds the device open, [dispose] closes it.
  ///
  /// Twice in a row is the same as once, and a [resume] undoes both.
  void pause() => backend.pause();

  /// Lets the voices [pause] held go on from where they were, and the ones
  /// started during the pause from their beginning. Without a [pause]
  /// first, nothing happens.
  void resume() => backend.resume();

  /// Stops the scene's voices and closes the device; nothing is played
  /// after this.
  Future<void> dispose() => backend.dispose();
}
