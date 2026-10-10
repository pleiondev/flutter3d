import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show IssueSink, ResourceException;
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
/// Throws [AudioDeviceException] when the device does not open; nothing is
/// left open then.
Future<Speakers> openSpeakers({
  required SoundBank bank,
  Mixer? mixer,
  int maxVoices = 24,
  double Function(Vector3 from, Vector3 to)? occlusion,
  IssueSink? onIssue,
  SpatialRenderer spatial = const EqualPowerPanner(),
}) async {
  final backend = SoLoudBackend(onIssue: onIssue);
  try {
    await backend.open();
  } on Object catch (error) {
    throw AudioDeviceException(
      'the audio device did not open, so there is no sound',
      cause: error,
    );
  }

  final scene = AudioScene(
    backend: backend,
    mixer: mixer,
    maxVoices: maxVoices,
    occlusion: occlusion,
    spatial: spatial,
  );
  await scene.preload(bank);
  return Speakers(backend: backend, scene: scene);
}

/// No audio device would open: a headless machine, a container, a build
/// whose audio plugin never linked. A game catches it and plays silent.
final class AudioDeviceException extends ResourceException {
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
  const Speakers({required this.backend, required this.scene});

  /// The device the scene plays through.
  final AudioBackend backend;

  /// The scene: play, place and mix here.
  final AudioScene scene;

  /// Holds every voice: the view paused, the application went to the
  /// background.
  void pause() => backend.pause();

  /// Lets the voices [pause] held go on.
  void resume() => backend.resume();

  /// Stops the scene's voices and closes the device; nothing is played
  /// after this.
  Future<void> dispose() => backend.dispose();
}
