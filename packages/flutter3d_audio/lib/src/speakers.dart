import 'package:flutter/foundation.dart' show debugPrint;
import 'package:vector_math/vector_math.dart';

import 'audio_scene.dart';
import 'mixer.dart';
import 'soloud_backend.dart';
import 'sound_bank.dart';

/// The device a game plays through, opened, or nothing and a game that is
/// silent.
///
/// **Three games wrote this and all three wrote the same trap around it.** The
/// backend throws when there is no audio device — a headless machine, a
/// container, a build whose plugin never linked — and a game that lets that
/// through dies on launch for want of a sound. Every one of them therefore had
/// the same try, the same `debugPrint`, the same decision to carry on in
/// silence; and each said so in its own words, which is three places to be
/// right and three chances to forget.
///
/// The trap this repository has paid for twice, kept here where it is read
/// rather than in three comments: **a plugin added to an already built
/// application does not bring its native framework with it**, and the only
/// symptom is one line about "no available native assets" and then nothing at
/// all. If that is what this prints, the answer is `flutter clean`.
///
/// Null means silent, and silent is a perfectly good way to play: every call
/// into an `AudioScene` a game never got is a call it simply does not make.
Future<Speakers?> openSpeakers({
  required SoundBank bank,
  Mixer? mixer,
  int maxVoices = 24,
  double Function(Vector3 from, Vector3 to)? occlusion,
  IssueSink? onIssue,
}) async {
  final backend = SoLoudBackend(onIssue: onIssue);
  try {
    await backend.open();
  } catch (error) {
    // Through the sink as well, so a game that routes its issues to the screen
    // can say "no sound" rather than leaving the player to work it out. The
    // print stays because the default sink is one.
    (onIssue ?? debugPrint)(
      'audio: could not start SoLoud, playing silent ($error)',
    );
    return null;
  }

  final scene = AudioScene(
    backend: backend,
    mixer: mixer,
    maxVoices: maxVoices,
    occlusion: occlusion,
  );
  await scene.preload(bank);
  return Speakers(backend: backend, scene: scene);
}

/// What [openSpeakers] hands back: the device, and the scene playing through it.
///
/// Both, because a game needs the one to close and the other to play, and
/// handing back only the scene is how a backend gets left open when the window
/// closes.
final class Speakers {
  const Speakers({required this.backend, required this.scene});

  final SoLoudBackend backend;
  final AudioScene scene;
}
