/// Meteor Yard: a top-down ship over a 3D yard, and all five bridges at once.
///
///     flutter run -d macos
///
/// The fifth demo game in this repository, and the smallest: one
/// self-contained app rather than a separate `flutter3d_game_arcade`
/// simulation package, the way `packages/flutter3d_game/example` and
/// `packages/flutter3d_app/example` are self-contained, just bigger. There is
/// no genre package behind this because there is no genre here to reuse — the
/// point of this app is `packages/flame_flutter3d`, wired up for real:
///
/// * **Transform** — the ship is a `RigidBodyComponent` (`ShipComponent`), so
///   its 3D collider is what actually moves and the Flame position is a read
///   of that, not the other way round.
/// * **ECS** — each level's drones are `flutter3d_sim` `Actor`s under a
///   `DroneBrain` stepped by a real `ActorSystem`, not animated by hand: they
///   patrol, and on the later levels chase the ship and sidestep a ram.
/// * **Physics** — the ship and the drones' colliders share one
///   `CollisionWorld`; a `CollisionBridge` on the ship reports a contact back
///   into Flame, where a head-on ram downs the drone and anything else hits
///   the ship.
///
/// Four levels, in `lib/src/levels.dart`: more drones, faster, then hunting,
/// then dodging, with fewer hits allowed. Clear every drone to move on;
/// after a loss, Enter plays the level again.
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

import 'dart:async';

import 'package:flame/camera.dart' show Viewfinder;
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
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
  /// Starts on the level `--dart-define=ARCADE_LEVEL=n` names, counting from
  /// one, so a later level can be looked at without playing through the
  /// ones before it. Set before [ArcadeGameStaging.spawnWorld], which builds
  /// the drones of whatever level the game is on.
  final ArcadeGame _game = ArcadeGame()
    ..levelIndex =
        (const int.fromEnvironment('ARCADE_LEVEL', defaultValue: 1) - 1).clamp(
          0,
          arcadeLevels.length - 1,
        );

  /// Looks straight down at the yard, `up` chosen so the camera's own +Z
  /// points the same way Flame's own +Y already does on screen — the two
  /// layers agree about which way is "down the page" without either one
  /// flipping an axis to match the other.
  late final CameraNode _camera =
      CameraNode(
          name: 'eye',
          projection: const OrthographicProjection(height: viewHeight),
        )
        ..setPosition(0.0, cameraHeight, 0.0)
        ..setLocalForward(Vector3(0.0, -1.0, 0.0), up: Vector3(0.0, 0.0, -1.0));

  /// **The viewfinder's zoom is set to the camera's height before the first
  /// sync.** Flowing Flame to flutter3d, [CameraSyncController] writes
  /// `1 / zoom` into the orthographic height every frame, and a viewfinder
  /// left at Flame's default zoom of one turned the yard's 22 metres into
  /// one: the ship filled the screen.
  late final CameraSyncController _cameraSync = CameraSyncController(
    camera: _camera,
    viewfinder: _game.camera.viewfinder..zoom = 1.0 / viewHeight,
    plane: ArcadeGame.cameraPlane,
    direction: SyncDirection.flameToScene,
  );

  /// Flame's own viewfinder follows the ship; the flutter3d camera then
  /// copies that onto its own plane, once a frame, in [_cameraSync.advance].
  ///
  /// **The HUD is rebuilt from here.** [Flutter3dFlameWidget] rebuilds only
  /// itself, and the HUD is its sibling, so nothing else ever redraws it.
  /// After the frame rather than now, for the reason the widget gives: this
  /// runs inside `GameWidget`'s own build.
  ///
  /// **Held inside the yard.** Following the ship to the bottom of the yard
  /// put half the window below its floor, on black. The view is
  /// [viewHeight] metres tall and as wide as the window's shape makes it;
  /// along each axis where that is smaller than the yard it follows the
  /// ship up to the edge and no further, and where it is not, it stays on
  /// the middle of the yard.
  void _onTick(double dt) {
    final Viewfinder viewfinder = _game.camera.viewfinder;
    final Vector2 window = _game.size;
    final double aspect = window.y > 0.0 ? window.x / window.y : 16.0 / 9.0;
    double held(double at, double halfView, double halfYard) =>
        halfView >= halfYard
        ? 0.0
        : at.clamp(halfView - halfYard, halfYard - halfView);
    viewfinder.position = Vector2(
      held(_game.ship.position.x, viewHeight * 0.5 * aspect, arenaHalfWidth),
      held(_game.ship.position.y, viewHeight * 0.5, arenaHalfDepth),
    );
    _cameraSync.advance(dt);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) setState(() {});
    });
  }

  /// A phone or a tablet has no keys to fly with, so it gets the on-screen
  /// stick. A desktop and a browser keep the keys and a clean screen.
  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      _game.addJoystick();
    }
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
            // The craft models arrive a moment later and replace the
            // primitives the yard was built with; see [ArcadeGameCrafts].
            unawaited(_game.dressWithCrafts());
            return scene;
          },
          onTick: _onTick,
        ),
        // Below the status bar and any notch: a phone draws the app edge to
        // edge, and the HUD sat under the clock.
        Positioned(
          left: 16,
          top: 16,
          child: SafeArea(child: _Hud(game: _game)),
        ),
      ],
    ),
  );
}

/// Score, hits and the win/lose banner — read straight off [ArcadeGame],
/// and rebuilt once a frame by [_ArcadeScreenState._onTick]. Not by
/// [Flutter3dFlameWidget]: its rebuild reaches only its own subtree, and this
/// is its sibling.
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
    final int levelNumber = game.levelIndex + 1;
    final bool touch = game.joystick != null;
    final String status = game.gameOver
        ? 'LEVEL $levelNumber LOST — ${touch ? 'tap to' : 'Enter to'} try again'
        : game.cleared
        ? 'YARD CLEARED — ${game.elapsed.toStringAsFixed(1)}s'
        : game.levelCleared
        ? 'LEVEL $levelNumber CLEARED — next one coming'
        : game.level.hunters > 0
        ? 'Ram them head on. Magenta drones hunt you'
        : touch
        ? 'Ram the drones head on. Stick to fly'
        : 'Ram the drones head on. WASD / arrows to fly';

    return DefaultTextStyle(
      style: style,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Level $levelNumber / ${arcadeLevels.length}'),
          Text('Time: ${game.elapsed.toStringAsFixed(1)}s'),
          Text('Hits: ${game.hits} / ${game.maxHits}'),
          Text('Drones left: ${game.drones.length}'),
          Text('Rammed: ${game.rammed}'),
          const SizedBox(height: 8.0),
          // A lost level is replayed with Enter on a keyboard, and with a
          // tap on this line where there is none.
          if (game.gameOver)
            GestureDetector(onTap: game.retry, child: Text(status))
          else
            Text(status),
        ],
      ),
    );
  }
}
