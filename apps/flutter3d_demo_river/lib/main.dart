/// River Sortie: a jet up a river that never ends, a Flame game drawn in 3D.
///
///     flutter run -d macos
///
/// A homage to River Raid, which Carol Shaw wrote for the Atari 2600 in 1982:
/// the river narrows and splits round islands, tankers and helicopters
/// cross it, jets cut over it, the tank runs dry unless the jet flies low
/// over a depot, and a bridge ends every stretch and has to be shot down
/// to pass. Lose a jet and the next starts past the last bridge brought
/// down. The river is the same every run, as it was on the cartridge,
/// because it is laid out by a seeded generator rather than drawn by hand.
///
/// **Flame runs the game, flutter3d draws it.** `lib/src/river_game.dart` is
/// an ordinary Flame game: components, hitboxes, `onCollisionStart`, a
/// keyboard handler, Flame's own joystick and button on a phone, and a HUD
/// Flame paints. It owns its 3D world through `HasFlutter3d`: the river, the
/// lens, the haze and the camera chasing the jet. Every component that moves
/// is an `Object3dComponent` from `flame_flutter3d`, which writes its Flame
/// position into a scene node each frame; `Flutter3dFlameWidget` puts the 3D
/// layer under Flame's and runs both from Flame's clock. This file hands it
/// the game and opens the speakers.
library;

import 'dart:async';

import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_audio/flutter3d_audio.dart'
    show SoLoudBackend, openSpeakers;

import 'src/river_game.dart';

void main() => runApp(const RiverApp());

/// Whether [platform] gets Flame's stick and fire button: a phone or a tablet,
/// which has no keys to fly with. A desktop and a browser keep the keys.
bool hasTouchControls(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS;

class RiverApp extends StatelessWidget {
  const RiverApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'River Sortie',
    debugShowCheckedModeBanner: false,
    home: RiverScreen(),
  );
}

class RiverScreen extends StatefulWidget {
  const RiverScreen({super.key});

  @override
  State<RiverScreen> createState() => _RiverScreenState();
}

class _RiverScreenState extends State<RiverScreen> {
  /// Starts on the level `--dart-define=RIVER_LEVEL=n` names, counting from
  /// one, so a later level can be looked at without flying up to it.
  final RiverGame _game = RiverGame(models: true)
    ..startOnLevel(
      const int.fromEnvironment('RIVER_LEVEL', defaultValue: 1) - 1,
    );

  /// The sound device, once the first take-off has opened it.
  SoLoudBackend? _speakers;

  /// A phone or a tablet has no keys, so it gets Flame's stick and trigger.
  @override
  void initState() {
    super.initState();
    if (hasTouchControls(defaultTargetPlatform)) _game.addTouchControls();
    _game.onFirstFlight = () => unawaited(_openAudio());
  }

  /// Opens the speakers, or leaves the game silent if they will not open.
  Future<void> _openAudio() async {
    final speakers = await openSpeakers(bank: Sounds.all, maxVoices: 16);
    if (speakers == null) return;
    if (!mounted) {
      // Gone while the device was opening: close it here, since dispose has
      // already run past it, and a SoLoud left open blocks the next open.
      unawaited(speakers.backend.dispose());
      return;
    }
    _speakers = speakers.backend;
    _game.hearWith(speakers.scene);
  }

  @override
  void dispose() {
    unawaited(_speakers?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF14161A),
    body: Flutter3dFlameWidget(game: _game),
  );
}
