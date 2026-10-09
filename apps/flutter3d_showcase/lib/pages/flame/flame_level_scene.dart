/// A Flame game that moves from one level to the next with
/// `replaceScene3d`, and a `ViewCamera` that frames the whole party as it
/// walks.
///
/// Quoted by `flame_level_scene.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flame/components.dart' show Component, TextComponent;
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/flame_layer.dart';

/// Seconds on each level before the party moves on.
const double _stay = 6.0;

final class FlameLevelSceneDemo extends ShowcaseDemo {
  late final _Tour _game;
  late final Widget _body = Flutter3dFlameWidget(
    game: _game,
    existing: (device: _context.device, renderer: _context.renderer),
  );
  late final DemoContext _context;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 14.0
      ..pitch = 0.7
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _context = context;
    // #region levels
    // Two levels, each a scene of its own: its floor, its light, its air.
    // The first is the one the game opens on; the second waits unseen.
    final List<Scene> levels = <Scene>[
      _level(
        context.device,
        floor: Vector4(0.36, 0.5, 0.3, 1.0),
        air: Vector3(0.55, 0.6, 0.7),
        rocks: Vector4(0.6, 0.58, 0.52, 1.0),
        seed: 1,
      ),
      _level(
        context.device,
        floor: Vector4(0.3, 0.28, 0.34, 1.0),
        air: Vector3(0.35, 0.3, 0.5),
        rocks: Vector4(0.45, 0.4, 0.6, 1.0),
        seed: 2,
      ),
    ];
    _game = _Tour(context.camera, levels)
      ..open3d(context.device, scene: levels.first);
    // #endregion levels
    return levels.first;
  }

  /// A floor, a sun and a scatter of rocks.
  static Scene _level(
    GraphicsDevice device, {
    required Vector4 floor,
    required Vector3 air,
    required Vector4 rocks,
    required int seed,
  }) {
    final math.Random random = math.Random(seed);
    final DeviceMesh rock = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(0.8, 1.2, 0.8)).build(),
    );
    final RenderMaterial stone = RenderMaterial(
      name: 'rock',
      baseColor: _fromSrgb(rocks),
    );
    final Scene level = Scene()
      ..ambientColor = air.toLinearColor()
      ..ambientIntensity = 0.35 * Photometric.legacyUnit
      ..add(
        MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3(20.0, 0.1, 20.0)).build(),
          ),
          RenderMaterial(name: 'floor', baseColor: _fromSrgb(floor)),
          name: 'floor',
        )..setPosition(0.0, -0.05, 0.0),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.4 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
    for (var i = 0; i < 14; i++) {
      level.add(
        MeshNode(rock, stone, name: 'rock $i')..setPosition(
          random.nextDouble() * 18.0 - 9.0,
          0.6,
          random.nextDouble() * 18.0 - 9.0,
        ),
      );
    }
    return level;
  }

  @override
  void update(DemoContext context, double dt) =>
      context.orbit.syncProjectionDepth(context.camera);

  /// The Flame game the page runs, for a test that steps it without a window.
  @visibleForTesting
  FlameGame get game => _game;

  /// The two levels, in the order the party visits them.
  @visibleForTesting
  List<Scene> get levels => _game.levels;

  /// The level the game draws now.
  @visibleForTesting
  Scene get level => _game.scene;

  /// The camera the view camera moves.
  @visibleForTesting
  CameraNode get camera => _game.camera3d;

  /// The party's markers.
  @visibleForTesting
  List<MeshNode> get party => _game.party;

  /// Where the view camera wants to be this frame.
  @visibleForTesting
  Vector3 get wantedEye {
    final Vector3 eye = Vector3.zero();
    _game.frameParty(eye, Vector3.zero());
    return eye;
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) => _body;

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('the first level was not drawn');
    if (!identical(scene, _game.levels.first)) {
      throw StateError('the page should open on the first level');
    }
  }
}

/// The party's colours, one a member.
final List<Vector4> _colors = <Vector4>[
  Vector4(0.95, 0.55, 0.2, 1.0),
  Vector4(0.3, 0.7, 0.95, 1.0),
  Vector4(0.6, 0.9, 0.35, 1.0),
  Vector4(0.9, 0.4, 0.75, 1.0),
];

final class _Tour extends FlameGame with HasFlutter3d {
  _Tour(this._eye, this.levels);

  final CameraNode _eye;
  final List<Scene> levels;
  final List<MeshNode> party = <MeshNode>[];
  late final TextComponent _caption = flameCaption('level one');

  int _level = 0;
  double _clock = 0.0;

  @override
  CameraNode createCamera3d() => _eye;

  // #region camera
  @override
  void onOpen3d() {
    final DeviceMesh ball = DeviceMesh.upload(
      device,
      SphereShape(segments: 20, radius: 0.4).build(),
    );
    for (var i = 0; i < _colors.length; i++) {
      final MeshNode member = MeshNode(
        ball,
        RenderMaterial(name: 'member $i', baseColor: _fromSrgb(_colors[i])),
        name: 'member $i',
      );
      party.add(member);
      scene.add(member);
    }
    _walk();
    // Eased each frame towards wherever `frameParty` says, after the party
    // has walked: no one member decides where the camera goes.
    addAll(<Component>[
      ViewCameraComponent(
        ViewCamera(camera: camera3d, view: frameParty, stiffness: 2.5),
      ),
      _caption,
    ]);
  }
  // #endregion camera

  // #region frame
  /// Above and behind the party's middle, further back the more it spreads.
  bool frameParty(Vector3 eye, Vector3 target) {
    if (party.isEmpty) return false;
    final Vector3 middle = party.fold(
      Vector3.zero(),
      (Vector3 sum, MeshNode m) => sum..add(m.readPosition()),
    )..scale(1.0 / party.length);
    final double spread = party.fold(
      0.0,
      (double far, MeshNode m) =>
          math.max(far, m.readPosition().distanceTo(middle)),
    );
    target.setFrom(middle);
    eye.setValues(
      middle.x,
      middle.y + 3.5 + spread * 1.5,
      middle.z + 5.0 + spread * 1.5,
    );
    return true;
  }
  // #endregion frame

  @override
  void update(double dt) {
    // The party walks before the camera, which is one of the children
    // `super.update` runs.
    if (has3d && party.isNotEmpty) {
      _clock += dt;
      if (_clock >= _stay) _nextLevel();
      _walk();
    }
    super.update(dt);
  }

  // #region next
  /// The next level: the party is carried across, then the scene is
  /// replaced, and the camera goes with it. What the old level holds stays
  /// there for the next visit.
  void _nextLevel() {
    _clock = 0.0;
    _level = (_level + 1) % levels.length;
    final Scene next = levels[_level];
    for (final MeshNode member in party) {
      member.removeFromParent();
      next.add(member);
    }
    replaceScene3d(next);
    _caption.text = _level == 0 ? 'level one' : 'level two';
  }
  // #endregion next

  /// Each level has its own walk: across the first, round the second, the
  /// party spreading and closing as it goes.
  void _walk() {
    final double t = _clock / _stay;
    final Vector3 middle = _level == 0
        ? Vector3(-3.0, 0.4, 6.0 - 12.0 * t)
        : Vector3(
            5.0 * math.cos(t * 2.0 * math.pi),
            0.4,
            5.0 * math.sin(t * 2.0 * math.pi),
          );
    final double spread = 1.0 + 0.8 * math.sin(_clock * 1.3);
    for (var i = 0; i < party.length; i++) {
      final double angle = _clock * 0.8 + i * 2.0 * math.pi / party.length;
      party[i].setPosition(
        middle.x + spread * math.cos(angle),
        middle.y,
        middle.z + spread * math.sin(angle),
      );
    }
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
