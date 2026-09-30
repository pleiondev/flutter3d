/// River Sortie: a jet up a river that never ends, a Flame game drawn in 3D.
///
///     flutter run -d macos
///     flutter run -d macos --dart-define=RIVER_VERSUS=turns
///
/// Two players take turns on one machine with `RIVER_VERSUS=turns`: a lost
/// jet hands the keys over. On two machines, through the relay
/// `flutter3d_net` ships (`dart run flutter3d_net:relay 8199`), one makes a
/// room and the other joins it:
///
///     flutter run -d macos --dart-define=RIVER_VERSUS=turns \
///       --dart-define=RIVER_ROOM=bridge
///     flutter run -d macos --dart-define=RIVER_VERSUS=turns \
///       --dart-define=RIVER_ROOM=bridge --dart-define=RIVER_JOIN=true
///
/// With `RIVER_VERSUS=race` both fly at once and see each other as a ghost.
/// `--dart-define=relay=ws://host:8199/` points both at a relay elsewhere.
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
/// the game.
library;

import 'dart:async';

import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_net/flutter3d_net.dart'
    show NetTransportWire, WebSocketTransport;

import 'src/river_game.dart';

void main() => runApp(const RiverApp());

/// `turns` or `race` for two players; empty for one.
const String _versus = String.fromEnvironment('RIVER_VERSUS');

/// The room two machines meet in; empty for one machine.
const String _room = String.fromEnvironment('RIVER_ROOM');

/// Whether this machine joins [_room] rather than making it; whoever made it
/// flies first.
const bool _join = bool.fromEnvironment('RIVER_JOIN');

/// Where the relay is.
final Uri _relay = Uri.parse(
  const String.fromEnvironment('relay', defaultValue: 'ws://127.0.0.1:8199/'),
);

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
  final RiverGame _game = RiverGame(
    models: true,
    billboards: true,
    versus: switch (_versus) {
      'turns' => Versus.turns,
      'race' => Versus.race,
      _ => null,
    },
    room: _room.isEmpty ? null : _room,
    slot: _join ? 1 : 0,
  )..startOnLevel(
      const int.fromEnvironment('RIVER_LEVEL', defaultValue: 1) - 1,
    );

  /// A phone or a tablet has no keys, so it gets Flame's stick and trigger.
  @override
  void initState() {
    super.initState();
    if (hasTouchControls(defaultTargetPlatform)) _game.addTouchControls();
    // Taking off is the player's first key, touch or button, and a browser
    // lets a page make a sound only after one.
    _game.onFirstFlight = () => unawaited(_game.sound.open());
    // `--dart-define=RIVER_HITBOXES=true` draws every hitbox in the scene,
    // round the craft it belongs to.
    _game.debugHitboxes3d = const bool.fromEnvironment('RIVER_HITBOXES');
    if (_room.isNotEmpty) unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      _game.goOnline(
        NetTransportWire(
          await WebSocketTransport.connect(_relay.resolve('room/$_room')),
        ),
      );
    } on Object catch (error) {
      _game.say('NO RELAY AT $_relay', seconds: 30.0);
      debugPrint('River Sortie: no relay at $_relay: $error');
    }
  }

  @override
  void dispose() {
    unawaited(_game.sound.close());
    // The world lives with the game, not the widget: it goes here.
    _game.close3d();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF14161A),
    body: Flutter3dFlameWidget(game: _game),
  );
}
