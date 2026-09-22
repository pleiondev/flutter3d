/// `FlameInputBridge` translating a Flame keyboard event into the same
/// `Bindings`/`InputState` pair `flutter3d_game`'s own desktop input writes
/// into.
///
/// Quoted by `flame_input_bridge.md` and shown whole in the Source tab.
library;

import 'package:flame/components.dart';
import 'package:flame/events.dart' show HasKeyboardHandlerComponents;
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/flame_layer.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// A Flame game that hands keyboard events to the components that ask.
final class _InputGame extends TransparentFlameGame
    with HasKeyboardHandlerComponents {}

final class FlameInputBridgeDemo extends ShowcaseDemo {
  late final String _report;
  late final bool _consumed;
  late final bool _heldByTheSharedState;
  late final double _actorX;

  /// Holds D for anyone without a keyboard to hand.
  bool holdD = false;

  late final DemoContext _context;
  late final Scene _scene;
  late final MeshNode _walker;
  late final _InputGame _game;
  late final FlameInputBridge _bridge;
  late final InputState _input;
  late final Widget _body = flameOrbit(
    _context,
    Flutter3dFlameWidget(
      game: _game,
      camera: _context.camera,
      existing: (device: _context.device, renderer: _context.renderer),
      buildScene: (GraphicsDevice device) => _scene,
    ),
  );
  bool _syntheticDown = false;

  static const double _speed = 3.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 8.0
      ..pitch = 0.7
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _context = context;
    final (String report, bool consumed, bool held, double actorX) = _run();
    _report = report;
    _consumed = consumed;
    _heldByTheSharedState = held;
    _actorX = actorX;

    _walker = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 24).build()),
      Material(name: 'walker', baseColor: Vector4(0.5, 0.7, 0.9, 1.0)),
      name: 'walker',
    )..setPosition(0.0, 0.5, 0.0);
    _scene = Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(8.0, 0.1, 8.0)).build(),
          ),
          Material(name: 'floor', baseColor: Vector4(0.36, 0.4, 0.38, 1.0)),
          name: 'floor',
        )..setPosition(0.0, -0.05, 0.0),
      )
      ..add(_walker)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );

    // #region live
    // Four keys in the one table both engines read. The Flame side is a
    // component that hands each key event to the bridge; it draws four
    // keycaps that light while their action is held. The flutter3d side is
    // `update` below, which reads the same state and walks the sphere.
    final Bindings bindings = Bindings()
      ..bind(
        InputSource.key(LogicalKeyboardKey.keyW.keyId),
        GameAction.moveForward,
      )
      ..bind(
        InputSource.key(LogicalKeyboardKey.keyA.keyId),
        GameAction.moveLeft,
      )
      ..bind(
        InputSource.key(LogicalKeyboardKey.keyS.keyId),
        GameAction.moveBack,
      )
      ..bind(
        InputSource.key(LogicalKeyboardKey.keyD.keyId),
        GameAction.moveRight,
      );
    _input = InputState();
    _bridge = FlameInputBridge(bindings: bindings, inputState: _input);
    _game = _InputGame()
      ..add(_Keys(_bridge))
      ..add(_KeyCap('W', GameAction.moveForward, _input, Vector2(56.0, 72.0)))
      ..add(_KeyCap('A', GameAction.moveLeft, _input, Vector2(16.0, 112.0)))
      ..add(_KeyCap('S', GameAction.moveBack, _input, Vector2(56.0, 112.0)))
      ..add(_KeyCap('D', GameAction.moveRight, _input, Vector2(96.0, 112.0)));
    // #endregion live
    _game
      ..add(flameCaption('click the scene, then press W A S D'))
      ..add(flameCaption(_report, at: Vector2(16.0, 40.0)));
    return _scene;
  }

  @override
  void update(DemoContext context, double dt) {
    context.orbit.syncProjectionDepth(context.camera);
    // For anyone without a keyboard: the same event a real D press makes.
    if (holdD != _syntheticDown) {
      _syntheticDown = holdD;
      _sendD(holdD);
    }
    // #region walk
    // The flutter3d side of the same key: it reads the state Flame wrote.
    final Vector2 axis = _input.moveAxis;
    final Vector3 at = _walker.readPosition();
    _walker.setPosition(
      (at.x + axis.x * _speed * dt).clamp(-3.5, 3.5),
      at.y,
      (at.z - axis.y * _speed * dt).clamp(-3.5, 3.5),
    );
    // #endregion walk
  }

  void _sendD(bool down) {
    const PhysicalKeyboardKey physical = PhysicalKeyboardKey.keyD;
    const LogicalKeyboardKey logical = LogicalKeyboardKey.keyD;
    _bridge.onKeyEvent(
      down
          ? const KeyDownEvent(
              physicalKey: physical,
              logicalKey: logical,
              timeStamp: Duration.zero,
            )
          : const KeyUpEvent(
              physicalKey: physical,
              logicalKey: logical,
              timeStamp: Duration.zero,
            ),
      const <LogicalKeyboardKey>{},
    );
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Hold D for me',
      value: () => holdD,
      onChanged: (bool v) => holdD = v,
    ),
  ];

  static (String, bool, bool, double) _run() {
    // #region shared
    // The same table and the same state a rebind screen edits and
    // `DesktopInput` reads natively — a bridged game and a native one share
    // one rebinding UI and one saved binding file, not two.
    final bindings = Bindings()
      ..bind(
        InputSource.key(LogicalKeyboardKey.keyD.keyId),
        GameAction.moveRight,
      );
    final inputState = InputState();
    final bridge = FlameInputBridge(bindings: bindings, inputState: inputState);
    // #endregion shared

    // #region press
    // `onKeyEvent` returns false when it consumed the key, matching
    // `KeyboardHandler`'s own polarity.
    final bool consumed = !bridge.onKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyD,
        logicalKey: LogicalKeyboardKey.keyD,
        timeStamp: Duration.zero,
      ),
      const <LogicalKeyboardKey>{},
    );
    // #endregion press

    // #region reactions
    // The Flame side already knows it consumed the key; the flutter3d side
    // reads the very same `InputState` the press just wrote into, the way an
    // actor's own movement would.
    final bool held = inputState.held(GameAction.moveRight);
    final double actorX = held ? 1.5 : 0.0;
    // #endregion reactions

    return (
      'the Flame key handler consumed the press: $consumed; the flutter3d '
          'side reads the same action held: $held',
      consumed,
      held,
      actorX,
    );
  }

  /// The Flame game the page runs, for a test that steps it without a window.
  @visibleForTesting
  TransparentFlameGame get game => _game;

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) => _body;

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the walker marker was not drawn');
    }
    // Compared as booleans, not read back out of `_report`: see
    // `sim_audio_xr/actors.dart` for why.
    if (!_consumed) {
      throw StateError('a bound key should be consumed, not passed through');
    }
    if (!_heldByTheSharedState) {
      throw StateError(
        'the flutter3d side should read the same InputState the Flame '
        'bridge just pressed',
      );
    }
    if (_actorX != 1.5) {
      throw StateError('the flutter3d-side reaction should have moved');
    }
  }
}

/// Hands every key event Flame sees to the bridge, which answers false when it
/// consumed the key.
final class _Keys extends Component with KeyboardHandler {
  _Keys(this._bridge);

  final FlameInputBridge _bridge;

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) =>
      _bridge.onKeyEvent(event, keysPressed);
}

/// A key drawn on Flame's side, lit while the shared state holds its action.
final class _KeyCap extends PositionComponent {
  _KeyCap(this._label, this._action, this._state, Vector2 at)
    : super(position: at, size: Vector2.all(36.0));

  final String _label;
  final GameAction _action;
  final InputState _state;

  @override
  void render(Canvas canvas) {
    final bool held = _state.held(_action);
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect(), const Radius.circular(6.0)),
      Paint()..color = held ? const Color(0xFFE8A33D) : const Color(0xAA14161A),
    );
    TextPaint(
      style: TextStyle(
        color: held ? const Color(0xFF14161A) : const Color(0xFFE8E8EC),
        fontSize: 18.0,
        fontWeight: FontWeight.bold,
      ),
    ).render(canvas, _label, Vector2(11.0, 8.0));
  }
}
