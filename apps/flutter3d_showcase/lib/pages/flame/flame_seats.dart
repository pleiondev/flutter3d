/// `PlayerSeats` over two keyboard layouts: nobody plays until they press
/// their join key, and the first to press is player one.
///
/// Quoted by `flame_seats.md` and shown whole in the Source tab.
library;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/flame_layer.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

// #region layouts
/// What a layout presses to join, and to do nothing else yet.
const GameAction join = GameAction('join');

/// One way of holding the game: four keys to walk and one to join, in a
/// table and a state of its own.
FlameInputBridge _layout(
  LogicalKeyboardKey up,
  LogicalKeyboardKey left,
  LogicalKeyboardKey down,
  LogicalKeyboardKey right,
  LogicalKeyboardKey joins,
) => FlameInputBridge(
  actions: ActionMap(
    actions: ActionSet.common,
    buttons: Bindings()
      ..bind(InputSource.key(up.keyId), GameAction.moveForward)
      ..bind(InputSource.key(left.keyId), GameAction.moveLeft)
      ..bind(InputSource.key(down.keyId), GameAction.moveBack)
      ..bind(InputSource.key(right.keyId), GameAction.moveRight)
      ..bind(InputSource.key(joins.keyId), join),
  ),
  inputState: InputState(),
);

/// WASD and Space on the left of the keyboard, the arrows and Slash on the
/// right: two players at one keyboard, neither of them a player yet.
PlayerSeats _twoLayouts() => PlayerSeats(<FlameInputBridge>[
  _layout(
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.space,
  ),
  _layout(
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.slash,
  ),
]);
// #endregion layouts

// #region claim
/// Seats every free layout whose join key went down this step, in the order
/// the seats have them, and answers the ones it seated.
List<FlameInputBridge> seatNewcomers(PlayerSeats seats) => <FlameInputBridge>[
  for (final FlameInputBridge layout in seats.free.toList())
    if (layout.inputState.pressed(join) && seats.claim(layout)) layout,
];
// #endregion claim

final class FlameSeatsDemo extends ShowcaseDemo {
  late final DemoContext _context;
  late final Scene _scene;
  late final _Lobby _game;
  late final Widget _body = flameOrbit(
    _context,
    Flutter3dFlameWidget(
      game: _game,
      existing: (device: _context.device, renderer: _context.renderer),
    ),
  );

  late final bool _secondFirst;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.8
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _context = context;
    _secondFirst = _run();
    _scene = Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3 * Photometric.legacyUnit
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(9.0, 0.1, 9.0)).build(),
          ),
          RenderMaterial(
            name: 'floor',
            baseColor: LinearColor.fromSrgb(0.36, 0.4, 0.38, 1.0),
          ),
          name: 'floor',
        )..setPosition(0.0, -0.05, 0.0),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
    _game = _Lobby(context.camera, _twoLayouts())
      ..open3d(context.device, scene: _scene);
    return _scene;
  }

  @override
  void update(DemoContext context, double dt) =>
      context.orbit.syncProjectionDepth(context.camera);

  /// Checks, with no window, that the second layout pressing first is
  /// player one: seats go in the order people join, not the order listed.
  static bool _run() {
    final PlayerSeats seats = _twoLayouts();
    final FlameInputBridge arrows = seats.candidates[1];
    arrows.onKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.slash,
        logicalKey: LogicalKeyboardKey.slash,
        timeStamp: Duration.zero,
      ),
      const <LogicalKeyboardKey>{},
    );
    seatNewcomers(seats);
    return seats.seated.length == 1 && identical(seats.seated.first, arrows);
  }

  /// The Flame game the page runs, for a test that steps it without a window.
  @visibleForTesting
  FlameGame get game => _game;

  /// Who holds what, for a test that presses keys.
  @visibleForTesting
  PlayerSeats get seats => _game.seats;

  /// The marker each layout walks, in the order the seats list the layouts.
  @visibleForTesting
  List<MeshNode> get markers => _game.markers;

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) => _body;

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('the floor was not drawn');
    if (!_secondFirst) {
      throw StateError(
        'the arrows pressed Slash first and should have been player one',
      );
    }
  }
}

/// The colour of each seat, player one first.
final List<Vector4> _seatColours = <Vector4>[
  Vector4(0.95, 0.65, 0.2, 1.0),
  Vector4(0.3, 0.75, 0.95, 1.0),
];

// #region lobby
/// The game: every layout fed from the keyboard itself and closed after each
/// frame, a marker for each, hidden until its layout joins.
final class _Lobby extends FlameGame with HasFlutter3d {
  _Lobby(this._eye, this.seats);

  final CameraNode _eye;
  final PlayerSeats seats;
  final List<MeshNode> markers = <MeshNode>[];
  late final TextComponent _caption = flameCaption(
    'Space joins WASD, / joins the arrows',
  );

  @override
  CameraNode createCamera3d() => _eye;

  @override
  void onOpen3d() {
    final DeviceMesh cube = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3.all(0.8)).build(),
    );
    for (var i = 0; i < seats.candidates.length; i++) {
      final MeshNode marker =
          MeshNode(
              cube,
              RenderMaterial(name: 'player', baseColor: LinearColor.white),
              name: 'layout $i',
            )
            ..setPosition(-1.5 + 3.0 * i, 0.4, 0.0)
            ..isVisible = false;
      markers.add(marker);
      scene.add(marker);
    }
    addAll(<Component>[
      // From `HardwareKeyboard`, wherever the focus is.
      seats.listenToKeyboard(),
      _Seating(this),
      // Every layout's step closed, the free ones too, so a press made to
      // join is seen once.
      ...seats.stepEnds(),
      _caption,
    ]);
  }
  // #endregion lobby

  // #region seat
  /// A layout that has just joined shows its marker in its seat's colour;
  /// every seated layout walks its own.
  void seatAndWalk(double dt) {
    for (final FlameInputBridge joined in seatNewcomers(seats)) {
      final int seat = seats.seated.indexOf(joined);
      final MeshNode marker = markers[seats.candidates.indexOf(joined)];
      marker
        ..material.baseColor = _fromSrgb(_seatColours[seat])
        ..isVisible = true;
    }
    for (final FlameInputBridge player in seats.seated) {
      final Vector2 axis = player.inputState.moveAxis;
      final MeshNode marker = markers[seats.candidates.indexOf(player)];
      final Vector3 at = marker.readPosition();
      marker.setPosition(
        (at.x + axis.x * 3.0 * dt).clamp(-4.0, 4.0),
        at.y,
        (at.z - axis.y * 3.0 * dt).clamp(-4.0, 4.0),
      );
    }
    _caption.text = switch (seats.seated.length) {
      0 => 'Space joins WASD, / joins the arrows',
      1 => 'player one is in; the other layout can still join',
      _ => 'two players, in the order they pressed',
    };
  }
  // #endregion seat
}

/// Seats and walks between the keyboard's feed and the steps' ends, so a
/// join press is read in the frame it came in.
final class _Seating extends Component {
  _Seating(this._lobby);

  final _Lobby _lobby;

  @override
  void update(double dt) {
    super.update(dt);
    _lobby.seatAndWalk(dt);
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
