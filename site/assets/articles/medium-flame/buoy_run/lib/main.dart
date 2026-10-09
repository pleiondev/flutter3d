import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart'
    show ActionMap, Bindings, InputSource;
import 'package:flutter3d_sim/flutter3d_sim.dart';

// Step 4: the widget. The game is made once, not in build().
void main() => runApp(const MaterialApp(home: BuoyRunScreen()));

class BuoyRunScreen extends StatefulWidget {
  const BuoyRunScreen({super.key});

  @override
  State<BuoyRunScreen> createState() => _BuoyRunScreenState();
}

class _BuoyRunScreenState extends State<BuoyRunScreen> {
  final BuoyRun _game = BuoyRun();

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Flutter3dFlameWidget(game: _game));
}

// Step 3: the game owns its 3D world.
class BuoyRun extends FlameGame
    with HasFlutter3d, HasFixedStep, HasCollisionDetection, KeyboardEvents {
  /// Flame's 2D world, laid flat on the water: Flame's y runs along the
  /// scene's z.
  static final BridgePlane water = BridgePlane.ground();

  final InputState input = InputState();
  late final FlameInputBridge inputBridge = FlameInputBridge(
    actions: ActionMap(
      actions: ActionSet.common,
      buttons: Bindings(<InputSource, GameAction>{
        InputSource.key(LogicalKeyboardKey.arrowUp.keyId):
            GameAction.moveForward,
        InputSource.key(LogicalKeyboardKey.arrowDown.keyId):
            GameAction.moveBack,
        InputSource.key(LogicalKeyboardKey.arrowLeft.keyId):
            GameAction.moveLeft,
        InputSource.key(LogicalKeyboardKey.arrowRight.keyId):
            GameAction.moveRight,
      }),
    ),
    inputState: input,
  );

  late final Boat boat;
  final TextComponent score = TextComponent(
    text: 'Buoys: 0',
    position: Vector2(16, 16),
  );
  int collected = 0;

  MeshNode _mesh(Shape shape, LinearColor color) => MeshNode(
    DeviceMesh.upload(device, shape.build()),
    RenderMaterial(name: 'paint', baseColor: color, roughness: 0.5),
  );

  @override
  void onOpen3d() {
    clearColor = LinearColor.fromSrgb(0.55, 0.75, 0.95); // the sky
    scene
      ..add(
        _mesh(
          PlaneShape(width: 400, depth: 400),
          LinearColor.fromSrgb(0.15, 0.35, 0.55),
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 17000) // lux, a hazy sun
          ..setLocalForward(Vector3(-0.4, -1, -0.3)),
      );

    boat = Boat(
      node: _mesh(
        CuboidShape(size: Vector3(0.8, 0.4, 1.6)),
        LinearColor.fromSrgb(0.9, 0.9, 0.85),
      ),
      scene: scene,
    );
    add(boat);
    for (final (x, y) in <(double, double)>[
      (3, -6),
      (-4, -12),
      (2, -18),
      (-2, -24),
      (5, -30),
    ]) {
      add(
        Buoy(
          node: _mesh(
            SphereShape(radius: 0.4),
            LinearColor.fromSrgb(0.95, 0.35, 0.1),
          ),
          scene: scene,
          position: Vector2(x, y),
        ),
      );
    }

    add(
      FlameChaseCameraComponent(
        FlameChaseCamera(
          camera: camera3d,
          target: boat,
          offset: Vector3(0, 6, 8),
          lookOffset: Vector3(0, 0, -6),
        ),
      ),
    );
    add(score);
  }

  void collect(Buoy buoy) {
    buoy.removeFromParent();
    score.text = 'Buoys: ${++collected}';
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) => inputBridge.onGameKeyEvent(event, keysPressed);
}

// Step 5: a Flame component with a body in the scene.
class Boat extends Object3dComponent
    with CollisionCallbacks, FixedStepUpdate, HasGameReference<BuoyRun> {
  Boat({required super.node, required super.scene})
    : super(
        plane: BuoyRun.water,
        direction: SyncDirection.flameToScene,
        elevation: 0.2,
        size: Vector2(0.8, 1.6),
        anchor: Anchor.center,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }

  // Step 7: the same distance per second at any frame rate.
  @override
  void fixedUpdate(double dt) {
    final axis = game.input.moveAxis;
    // Forward is up the screen in Flame, which is -y.
    position.add(Vector2(axis.x, -axis.y) * (6 * dt));
  }

  // Step 6: an ordinary Flame collision.
  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Buoy) game.collect(other);
  }
}

class Buoy extends Object3dComponent {
  Buoy({required super.node, required super.scene, super.position})
    : super(
        plane: BuoyRun.water,
        direction: SyncDirection.flameToScene,
        elevation: 0.2,
        size: Vector2.all(0.8),
        anchor: Anchor.center,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(CircleHitbox());
  }
}
