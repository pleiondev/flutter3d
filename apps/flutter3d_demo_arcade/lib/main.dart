/// Meteor Yard: a top-down ship over a 3D yard, and all five bridges at once.
///
///     flutter run -d macos
///
/// The fifth demo game in this repository, and the smallest: one
/// self-contained app rather than a separate `flutter3d_game_arcade`
/// simulation package, the way `packages/flutter3d_game/example` and
/// `packages/flutter3d_app/example` are self-contained, just bigger. There is
/// no genre package behind this because there is no genre here to reuse — the
/// point of this app is `packages/flutter3d_flame`, wired up for real:
///
/// * **Transform** — the ship is a `RigidBodyComponent` (`ShipComponent`), so
///   its 3D collider is what actually moves and the Flame position is a read
///   of that, not the other way round.
/// * **ECS** — three drones are `flutter3d_sim` `Actor`s, patrolling under a
///   `PatrolBrain` stepped by a real `ActorSystem`, not animated by hand.
/// * **Physics** — the ship and the drones' colliders share one
///   `CollisionWorld`; a `CollisionBridge` on the ship reports a hit back
///   into Flame, which blinks the ship and clears the drone.
/// * **Input** — `FlameInputBridge` drives a `Bindings`/`InputState` pair,
///   the same objects `flutter3d_game`'s own `DesktopInput` would write into.
/// * **Camera** — a `CameraSyncController` keeps an orthographic flutter3d
///   camera framed on wherever Flame's own `Viewfinder` follows the ship to.
///
/// See `lib/src/arcade_game.dart`'s own doc comment for the one non-obvious
/// design call this app makes: a drone is an `ActorComponent`, never a
/// `RigidBodyComponent`, because one physical collider cannot honestly be
/// both.
library;

import 'package:flame/camera.dart' show Viewfinder;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/arcade_game.dart';

void main() => runApp(const ArcadeApp());

class ArcadeApp extends StatelessWidget {
  const ArcadeApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Meteor Yard',
    debugShowCheckedModeBanner: false,
    home: ArcadeScreen(),
  );
}

class ArcadeScreen extends StatefulWidget {
  const ArcadeScreen({super.key});

  @override
  State<ArcadeScreen> createState() => _ArcadeScreenState();
}

class _ArcadeScreenState extends State<ArcadeScreen> {
  final ArcadeGame _game = ArcadeGame();

  /// Looks straight down at the yard, `up` chosen so the camera's own +Z
  /// points the same way Flame's own +Y already does on screen — the two
  /// layers agree about which way is "down the page" without either one
  /// flipping an axis to match the other.
  late final CameraNode _camera =
      CameraNode(
          name: 'eye',
          projection: const OrthographicProjection(height: 22.0),
        )
        ..setPosition(0.0, cameraHeight, 0.0)
        ..setLocalForward(Vector3(0.0, -1.0, 0.0), up: Vector3(0.0, 0.0, -1.0));

  late final CameraSyncController _cameraSync = CameraSyncController(
    camera: _camera,
    viewfinder: _game.camera.viewfinder,
    plane: ArcadeGame.cameraPlane,
    direction: SyncDirection.flameToScene,
  );

  /// Flame's own viewfinder follows the ship; the flutter3d camera then
  /// copies that onto its own plane, once a frame, in [_cameraSync.advance].
  void _onTick(double dt) {
    final Viewfinder viewfinder = _game.camera.viewfinder;
    viewfinder.position = _game.ship.position;
    _cameraSync.advance(dt);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF14161A),
    body: Stack(
      children: <Widget>[
        Flutter3dFlameWidget(
          game: _game,
          camera: _camera,
          buildScene: (GraphicsDevice device) {
            final scene = Scene();
            _game.spawnWorld(device, scene);
            return scene;
          },
          onTick: _onTick,
        ),
        Positioned(left: 16, top: 16, child: _Hud(game: _game)),
      ],
    ),
  );
}

/// Score, hits and the win/lose banner — read straight off [ArcadeGame],
/// which is safe because [Flutter3dFlameWidget] already rebuilds this whole
/// subtree once a frame (see its own doc comment on `_onFlameTick`).
class _Hud extends StatelessWidget {
  const _Hud({required this.game});

  final ArcadeGame game;

  @override
  Widget build(BuildContext context) {
    final style = const TextStyle(
      color: Colors.white,
      fontSize: 16.0,
      shadows: <Shadow>[Shadow(blurRadius: 4.0)],
    );
    final String status = game.gameOver
        ? 'YARD LOST — ${game.elapsed.toStringAsFixed(1)}s'
        : game.cleared
        ? 'YARD CLEARED — ${game.elapsed.toStringAsFixed(1)}s'
        : 'WASD / arrows to fly';

    return DefaultTextStyle(
      style: style,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Survived: ${game.elapsed.toStringAsFixed(1)}s'),
          Text('Hits: ${game.hits} / ${ArcadeGame.maxHits}'),
          Text('Drones left: ${game.drones.length}'),
          const SizedBox(height: 8.0),
          Text(status),
        ],
      ),
    );
  }
}
