/// A Flame game that owns its 3D world through `HasFlutter3d`, with crates
/// that hear a tap on what the camera shows.
///
/// Quoted by `flame_owned_world.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flame/collisions.dart' show RectangleHitbox;
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/flame_layer.dart';

final class FlameOwnedWorldDemo extends ShowcaseDemo {
  late final DemoContext _context;
  late final Scene _scene;
  late final _Yard _game;
  late final Widget _body = flameOrbit(
    _context,
    Flutter3dFlameWidget(
      game: _game,
      existing: (device: _context.device, renderer: _context.renderer),
    ),
  );

  late final bool _tapFound;
  late final bool _flameMissed;
  double _clock = 0.0;
  int _next = 0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.75
      ..yaw = 0.3;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _context = context;
    final (bool found, bool missed) = _run(context.device);
    _tapFound = found;
    _flameMissed = missed;

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

    // #region open
    // The game is handed the page's device and scene; it builds the rest
    // itself, in onOpen3d, once Flame has loaded it.
    _game = _Yard(context.camera)..open3d(context.device, scene: _scene);
    // #endregion open
    return _scene;
  }

  @override
  void update(DemoContext context, double dt) {
    context.orbit.syncProjectionDepth(context.camera);
    // A tap every second and a half, on the next crate, through the same
    // path a finger takes: the crate's place on screen, then the nearest
    // crate drawn under it.
    _clock += dt;
    if (_clock < 1.5 || _game.crates.isEmpty) return;
    _clock = 0.0;
    final crate = _game.crates[_next++ % _game.crates.length];
    final screen = _game.projector.toScreen(crate.scenePosition);
    if (screen != null) _game.taps.nearestAt(screen)?.onTap3d(screen);
  }

  /// Checks, with no window, that a tap on where a crate is drawn finds it,
  /// and that Flame's own test on the same point does not.
  static (bool, bool) _run(GraphicsDevice device) {
    final camera = CameraNode()
      ..setPosition(0.0, 6.0, 6.0)
      ..lookAt(Vector3(0.0, 0.0, -2.0));
    final projector = BridgeProjector(
      camera: camera,
      viewSize: () => Vector2(800.0, 600.0),
    );
    final crate = _Crate(device, Scene(), Vector2(1.0, -3.0))..update(0.0);
    final screen = projector.toScreen(crate.scenePosition)!;
    return (crate.hitAt3d(screen, projector), !crate.containsPoint(screen));
  }

  /// The Flame game the page runs, for a test that steps it without a window.
  @visibleForTesting
  FlameGame get game => _game;

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) => _body;

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('the floor was not drawn');
    if (!_tapFound) {
      throw StateError('a tap on where a crate is drawn did not find it');
    }
    if (!_flameMissed) {
      throw StateError(
        'Flame\'s own test found the crate at its drawn place, so this page '
        'shows nothing Flame could not do',
      );
    }
  }
}

// #region world
/// The game, owning its world: the page hands it a device and a scene, and
/// it adds the crates, the tap layer and the hitbox lines itself.
final class _Yard extends FlameGame with HasFlutter3d {
  _Yard(this._eye);

  final CameraNode _eye;
  final List<_Crate> crates = <_Crate>[];
  final Taps3dComponent taps = Taps3dComponent();

  /// The page's own orbiting camera, so the projector sees what is drawn.
  @override
  CameraNode createCamera3d() => _eye;

  @override
  void onOpen3d() {
    for (var i = 0; i < 3; i++) {
      final angle = i * 2.0 * math.pi / 3.0;
      crates.add(
        _Crate(
          device,
          scene,
          Vector2(2.4 * math.cos(angle), 2.4 * math.sin(angle)),
        ),
      );
    }
    addAll(<Component>[...crates, taps]);
    debugHitboxes3d = true;
  }
}
// #endregion world

// #region crate
/// A crate that hears a tap on what the camera shows of it, flashes, and
/// says so over itself.
final class _Crate extends Object3dComponent with Tap3dCallbacks {
  _Crate(GraphicsDevice device, Scene scene, Vector2 at)
    : super(
        node: MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3.all(1.0)).build(),
          ),
          RenderMaterial(
            name: 'crate',
            baseColor: LinearColor.fromSrgb(0.8, 0.65, 0.4, 1.0),
          ),
        ),
        scene: scene,
        plane: BridgePlane.ground(),
        direction: SyncDirection.flameToScene,
        elevation: 0.5,
        position: at,
        size: Vector2.all(1.0),
        anchor: Anchor.center,
        children: <Component>[RectangleHitbox()],
      );

  @override
  void onTap3d(Vector2 screen) {
    // A red flash over the material the other crates share: the tint is
    // this crate's alone.
    tint = const LinearColor(1.0, 0.3, 0.25);
    add(
      TimerComponent(
        period: 0.25,
        removeOnFinish: true,
        onTick: () => tint = LinearColor.white,
      ),
    );
    // "+1" over the crate, placed through the projector, in Flame's layer.
    final game = findGame()! as HasFlutter3d;
    game.add(
      TextComponent(
        text: '+1',
        position: game.projector.toScreen(scenePosition)!,
        anchor: Anchor.center,
      )..addAll(<Component>[
        MoveByEffect(Vector2(0.0, -40.0), EffectController(duration: 0.8)),
        RemoveEffect(delay: 0.8),
      ]),
    );
  }
}
// #endregion crate
