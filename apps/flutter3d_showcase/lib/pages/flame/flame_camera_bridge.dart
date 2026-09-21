/// `CameraSyncController` reconciling an orthographic flutter3d `CameraNode`
/// and a Flame `Viewfinder`, in both `SyncDirection`s.
///
/// Quoted by `flame_camera_bridge.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flame/camera.dart';
import 'package:flame/components.dart' show Anchor, CircleComponent, Component;
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/flame_layer.dart';
import 'package:vector_math/vector_math.dart';

final class FlameCameraBridgeDemo extends ShowcaseDemo {
  late final String _report;
  late final double _viewfinderX;
  late final double _viewfinderZoom;
  late final double _cameraX;
  late final double _orthoHeight;

  /// Which side leads on the page: 0 the flutter3d camera, 1 the viewfinder.
  int _leader = 0;

  late final CameraNode _lens;
  late final RenderView _view;
  late final Scene _scene;
  late final TransparentFlameGame _game;
  late final CameraSyncController _sceneLeads;
  late final CameraSyncController _flameLeads;
  late final DemoContext _context;
  late final Widget _body = Flutter3dFlameWidget(
    game: _game,
    camera: _lens,
    existing: (device: _context.device, renderer: _context.renderer),
    buildScene: (GraphicsDevice device) => _scene,
  );
  double _clock = 0.0;

  /// Where the pillars stand, on the ground, in metres.
  static const List<(double, double)> _pillars = <(double, double)>[
    (-3.0, -3.0),
    (0.0, -3.0),
    (3.0, -3.0),
    (-3.0, 0.0),
    (0.0, 0.0),
    (3.0, 0.0),
    (-3.0, 3.0),
    (0.0, 3.0),
    (3.0, 3.0),
  ];

  /// Where the camera stands above the ground.
  static const double _eyeHeight = 6.0;

  @override
  List<RenderView> views(DemoContext context) => <RenderView>[_view];

  @override
  Scene build(DemoContext context) {
    _context = context;
    final (
      String report,
      double viewfinderX,
      double viewfinderZoom,
      double cameraX,
      double orthoHeight,
    ) = _run();
    _report = report;
    _viewfinderX = viewfinderX;
    _viewfinderZoom = viewfinderZoom;
    _cameraX = cameraX;
    _orthoHeight = orthoHeight;

    _lens = CameraNode(
      name: 'bridged-lens',
      projection: const OrthographicProjection(height: 9.0),
    )
      ..setPosition(0.0, _eyeHeight, 0.0)
      // Straight down, with -z at the top of the picture: Flame's y grows
      // downwards and the plane maps it to z, so the two agree on which way
      // is up.
      ..lookAt(Vector3.zero(), up: Vector3(0.0, 0.0, -1.0));
    _view = RenderView(camera: _lens, clearColor: Vector4(0.05, 0.05, 0.07, 1.0));

    _scene = Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.35
      ..add(_lens)
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(40.0, 0.1, 40.0)).build(),
          ),
          Material(name: 'floor', baseColor: Vector4(0.3, 0.33, 0.32, 1.0)),
          name: 'floor',
        )..setPosition(0.0, -0.05, 0.0),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -1.0, -0.4)),
      );
    for (final (int i, (double, double) at) in _pillars.indexed) {
      _scene.add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(0.6, 0.4 + 0.15 * (i % 4), 0.6)).build(),
          ),
          Material(
            name: 'pillar $i',
            baseColor: Vector4(
              0.55 + 0.4 * math.sin(i * 0.9),
              0.5 + 0.3 * math.sin(i * 1.7 + 1.0),
              0.4 + 0.3 * math.sin(i * 2.3 + 2.0),
              1.0,
            ),
          ),
          name: 'pillar $i',
        )..setPosition(at.$1, 0.2 + 0.075 * (i % 4), at.$2),
      );
    }

    // #region live
    // One plane for both, at the camera's own height: the controller writes
    // the camera's position through it when Flame leads, and a plane at zero
    // would put the lens on the floor.
    final BridgePlane plane = BridgePlane.ground(height: _eyeHeight);
    _game = TransparentFlameGame();
    final Viewfinder viewfinder = _game.camera.viewfinder;
    _sceneLeads = CameraSyncController(
      camera: _lens,
      viewfinder: viewfinder,
      plane: plane,
    );
    _flameLeads = CameraSyncController(
      camera: _lens,
      viewfinder: viewfinder,
      plane: plane,
      direction: SyncDirection.flameToScene,
    );
    // Flame's own picture of the same ground: a ring round every pillar, in
    // metres, seen through the viewfinder the controller is keeping in step.
    for (final (double, double) at in _pillars) {
      _game.world.add(
        CircleComponent(
          radius: 0.55,
          position: Vector2(at.$1, at.$2),
          anchor: Anchor.center,
          paint: Paint()
            ..color = const Color(0xFFFFD866)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.05,
        ),
      );
    }
    // #endregion live
    _game
      ..add(_Drive(this))
      ..add(flameCaption('yellow rings: Flame\'s world, through its viewfinder'))
      ..add(flameCaption(_report, at: Vector2(16.0, 40.0)));
    return _scene;
  }

  /// The half of the frame a page's own logic owns: whichever side leads
  /// moves, then the controller carries it over, then the Flame zoom is
  /// scaled from "one over the height" to pixels to the metre.
  void _drive(double dt) {
    _clock += dt;
    final double x = 1.8 * math.sin(_clock * 0.5);
    final double z = 1.2 * math.sin(_clock * 0.9);
    final double height = 9.0 + 2.0 * math.sin(_clock * 0.7);
    final Viewfinder viewfinder = _game.camera.viewfinder;
    // #region drive
    if (_leader == 0) {
      // flutter3d leads: the camera moves and the viewfinder is told.
      _lens
        ..setPosition(x, _eyeHeight, z)
        ..projection = OrthographicProjection(height: height);
      _sceneLeads.advance(dt);
    } else {
      // Flame leads: the viewfinder moves and the camera is told.
      viewfinder
        ..position = Vector2(x, z)
        ..zoom = 1.0 / height;
      _flameLeads.advance(dt);
    }
    // #endregion drive
    // The controller's zoom is one over the height, which is not a size on
    // screen. Turning it into pixels to the metre is the caller's step: the
    // game is as many pixels high as the picture under it.
    final double pixelsHigh = _game.size.y;
    if (pixelsHigh > 0.0) viewfinder.zoom = pixelsHigh * viewfinder.zoom;
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Who leads',
      options: const <String>['flutter3d camera', 'Flame viewfinder'],
      index: () => _leader,
      onChanged: (int i) => _leader = i,
    ),
  ];

  static (String, double, double, double, double) _run() {
    // #region cameras
    final camera = CameraNode(
      name: 'bridged-camera',
      projection: const OrthographicProjection(height: 4.0),
    );
    final viewfinder = Viewfinder();
    final plane = BridgePlane.ground();
    // #endregion cameras

    // #region scene-to-flame
    // The flutter3d camera is authoritative; `advance` copies its position
    // and its orthographic height onto the Flame viewfinder.
    final sceneToFlame = CameraSyncController(
      camera: camera,
      viewfinder: viewfinder,
      plane: plane,
    );
    camera.setPosition(3.0, 0.0, 2.0);
    sceneToFlame.advance(1 / 60);
    final double viewfinderX = viewfinder.position.x;
    final double viewfinderZoom = viewfinder.zoom;
    // #endregion scene-to-flame

    // #region flame-to-scene
    // The Flame viewfinder is authoritative instead; `advance` copies its
    // position and its zoom onto the flutter3d camera's projection.
    final flameToScene = CameraSyncController(
      camera: camera,
      viewfinder: viewfinder,
      plane: plane,
      direction: SyncDirection.flameToScene,
    );
    viewfinder.position = Vector2(1.0, -1.0);
    viewfinder.zoom = 0.5;
    flameToScene.advance(1 / 60);
    final double cameraX = camera.readPosition().x;
    final double orthoHeight =
        (camera.projection as OrthographicProjection).height;
    // #endregion flame-to-scene

    return (
      'flutter3d led: Flame position=($viewfinderX, _), zoom=$viewfinderZoom; '
          'Flame led: flutter3d x=$cameraX, height=$orthoHeight',
      viewfinderX,
      viewfinderZoom,
      cameraX,
      orthoHeight,
    );
  }

  /// The Flame game the page runs, for a test that steps it without a window.
  @visibleForTesting
  TransparentFlameGame get game => _game;

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      _body;

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the marker was not drawn');
    }
    // Compared as numbers, not read back out of `_report`: see
    // `sim_audio_xr/actors.dart` for why.
    if (_viewfinderX != 3.0) {
      throw StateError(
        'the viewfinder should have followed the camera to x=3, got '
        '$_viewfinderX',
      );
    }
    if (_viewfinderZoom != 0.25) {
      throw StateError(
        'zoom = 1 / height should read 0.25 for a height-4 lens, got '
        '$_viewfinderZoom',
      );
    }
    if (_cameraX != 1.0) {
      throw StateError(
        'the flutter3d camera should have followed the viewfinder to x=1, '
        'got $_cameraX',
      );
    }
    if (_orthoHeight != 2.0) {
      throw StateError(
        'height = 1 / zoom should read 2.0 for zoom 0.5, got $_orthoHeight',
      );
    }
  }
}

/// Calls the page's own step once a Flame frame, before the bridge clock.
final class _Drive extends Component {
  _Drive(this._page);

  final FlameCameraBridgeDemo _page;

  @override
  void update(double dt) {
    super.update(dt);
    _page._drive(dt);
  }
}
