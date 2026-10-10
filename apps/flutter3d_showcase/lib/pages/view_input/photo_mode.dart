/// Photo mode: the world paused, a free camera held inside the level, a
/// filter over the game's own look, and a picture of any size drawn in tiles
/// on the renderer the game already has.
///
/// Saving the picture is `savePhoto` and a `PhotoShelf` in `flutter3d_app`,
/// which write a file; this page keeps the picture in memory and checks it
/// instead.
///
/// Quoted by `photo_mode.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_camera/flutter3d_camera.dart' show PhotoCamera;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

// #region room
/// A room eight metres square and three high, closed on every side, with a
/// pillar and a crate in it. The boxes are kept as well as handed to the
/// collision world, so the check can ask whether a point is inside one
/// without going through the camera it is checking.
({CollisionWorld world, List<Aabb3> solids, Aabb3 bounds}) _room() {
  final world = CollisionWorld();
  final solids = <Aabb3>[];
  void box(Vector3 center, Vector3 size) {
    world.addBox(center, size);
    solids.add(Aabb3.centerAndHalfExtents(center, size / 2.0));
  }

  box(Vector3(0.0, -0.25, 0.0), Vector3(9.0, 0.5, 9.0)); // floor
  box(Vector3(0.0, 3.25, 0.0), Vector3(9.0, 0.5, 9.0)); // ceiling
  box(Vector3(4.25, 1.5, 0.0), Vector3(0.5, 3.0, 9.0));
  box(Vector3(-4.25, 1.5, 0.0), Vector3(0.5, 3.0, 9.0));
  box(Vector3(0.0, 1.5, 4.25), Vector3(9.0, 3.0, 0.5));
  box(Vector3(0.0, 1.5, -4.25), Vector3(9.0, 3.0, 0.5));
  box(Vector3(1.5, 1.5, -1.0), Vector3(1.0, 3.0, 1.0)); // pillar
  box(Vector3(-1.5, 0.4, 1.0), Vector3.all(0.8)); // crate
  world.update();
  return (
    world: world,
    solids: solids,
    bounds: Aabb3.minMax(Vector3(-4.0, 0.0, -4.0), Vector3(4.0, 3.0, 4.0)),
  );
}
// #endregion room

/// What the page measured before its first frame.
final class PhotoReport {
  int moves = 0;
  int escapes = 0;
  double furthest = 0.0;
  double startZ = 0.0;
  int tilesX = 0;
  int tilesY = 0;
  int pixels = 0;
  int awayFromSeams = 0;
  int atSeams = 0;
  int worst = 0;
}

final class PhotoModeDemo extends ShowcaseDemo {
  final PhotoReport report = PhotoReport();

  final ({CollisionWorld world, List<Aabb3> solids, Aabb3 bounds}) _level =
      _room();
  late final Scene _scene;
  late final MeshNode _spinner;
  final CameraNode _lens = CameraNode(
    name: 'photo lens',
    projection: const PerspectiveProjection(fovY: 0.9),
  );

  /// Whether photo mode is on in the viewport.
  bool photoMode = false;
  PhotoCamera? _flying;
  double _clock = 0.0;
  int _filter = 0;

  static const RenderSettings _noBloom = RenderSettings(
    bloom: BloomSettings(enabled: false),
  );
  static Vector4 get _clear => Vector4(0.05, 0.05, 0.07, 1.0);

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 11.0
      ..pitch = 0.6
      ..yaw = 0.5;
    context.orbit.target.setValues(0.0, 1.0, 0.0);
  }

  @override
  Future<void> prepare(DemoContext context) async {
    _scene = _build(context);
    _wander();
    await _capture(context.renderer);
  }

  Scene _build(DemoContext context) {
    _spinner = blockNode(
      context,
      'crate',
      Vector3.all(0.8),
      Vector4(0.8, 0.3, 0.2, 1),
      at: Vector3(-1.5, 0.4, 1.0),
    );
    return sceneOf(<SceneNode>[
      floorNode(context, width: 8.0, depth: 8.0),
      blockNode(
        context,
        'pillar',
        Vector3(1.0, 3.0, 1.0),
        Vector4(0.7, 0.62, 0.5, 1),
        at: Vector3(1.5, 1.5, -1.0),
      ),
      _spinner,
      // The walls are drawn low so the orbit camera can see in; the
      // collision world has them full height, with a ceiling.
      for (final (double x, double z, double w, double d)
          in <(double, double, double, double)>[
            (4.1, 0.0, 0.2, 8.4),
            (-4.1, 0.0, 0.2, 8.4),
            (0.0, 4.1, 8.4, 0.2),
            (0.0, -4.1, 8.4, 0.2),
          ])
        blockNode(
          context,
          'wall',
          Vector3(w, 0.4, d),
          Vector4(0.55, 0.57, 0.6, 1),
          at: Vector3(x, 0.2, z),
        ),
      _lens,
    ]);
  }

  /// Six hundred random flights from a start whose game camera was left
  /// outside the room, and how many ended inside a solid or out of bounds.
  void _wander() {
    // #region fly
    final camera = PhotoCamera(
      world: _level.world,
      bounds: _level.bounds,
      reach: 5.0,
    );
    // The game's camera is behind the far wall; the player is inside.
    camera.begin(
      eye: Vector3(0.3, 1.5, 9.0),
      target: Vector3(0.0, 1.0, 0.0),
      anchor: Vector3(0.0, 1.2, 2.0),
    );
    report.startZ = camera.eye.z;
    final dice = GameRandom(5);
    for (var i = 0; i < 600; i++) {
      camera
        ..look((dice.nextDouble() - 0.5) * 0.6, (dice.nextDouble() - 0.5) * 0.3)
        ..fly(
          Vector3(
            dice.nextDouble() * 6.0 - 3.0,
            dice.nextDouble() * 6.0 - 3.0,
            dice.nextDouble() * 6.0 - 3.0,
          ),
          0.25,
        );
      final Vector3 eye = camera.eye;
      if (!_level.bounds.containsVector3(eye) ||
          _level.solids.any((Aabb3 box) => box.containsVector3(eye))) {
        report.escapes++;
      }
      report.moves += 1;
      report.furthest = math.max(
        report.furthest,
        eye.distanceTo(camera.anchor),
      );
    }
    // #endregion fly
  }

  /// A picture twice the test viewport, in four tiles, against the same
  /// picture drawn as one frame.
  Future<void> _capture(Renderer renderer) async {
    _lens
      ..setPosition(0.3, 1.5, 3.2)
      ..lookAt(Vector3(0.0, 1.0, 0.0));
    const int width = 640;
    const int height = 360;
    // #region capture
    final picture = Uint8List(width * height * 4);
    final PhotoCaptureReport made = await capturePhoto(
      renderer: renderer,
      scene: _scene,
      camera: _lens,
      width: width,
      height: height,
      settings: _noBloom,
      clearColorSrgb: _clear,
      tileWidth: 320,
      tileHeight: 180,
      margin: 16,
      // A row of tiles at a time: a PNG writer would take it from here.
      onRows: (Uint8List rgba, int top, int rows) =>
          picture.setRange(top * width * 4, (top + rows) * width * 4, rgba),
    );
    // #endregion capture
    // #region whole
    // The reference: the same picture as one frame, with the settings the
    // capture says it drew its tiles with.
    final FrameResult whole = renderer.render(
      width: width,
      height: height,
      scene: _scene,
      views: <RenderView>[RenderView(camera: _lens, clearColorSrgb: _clear)],
      settings: photoSettings(_noBloom, PhotoFilter.none, made.exposure).tile,
    );
    final ByteBuffer read = (await renderer.device.readback(
      whole.frame,
    )).buffer;
    // #endregion whole
    report
      ..tilesX = made.tilesX
      ..tilesY = made.tilesY;
    final Uint8List reference = read.asUint8List();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var d = 0;
        for (var c = 0; c < 3; c++) {
          final int i = (y * width + x) * 4 + c;
          d = math.max(d, (picture[i] - reference[i]).abs());
        }
        report.pixels += 1;
        report.worst = math.max(report.worst, d);
        if (d <= 2) continue;
        if ((x - 320).abs() <= 2 || (y - 180).abs() <= 2) {
          report.atSeams++;
        } else {
          report.awayFromSeams++;
        }
      }
    }
  }

  @override
  Scene build(DemoContext context) => _scene;

  @override
  void update(DemoContext context, double dt) {
    // #region pause
    // Photo mode pauses the world whatever the pointer and the pad say,
    // since both are flying the camera.
    final bool paused = shouldPause(
      ready: true,
      menuOpen: false,
      pointerIsTheGate: false,
      pointerHeld: false,
      padConnected: false,
      photoMode: photoMode,
    );
    if (!paused) {
      _clock += dt;
      _spinner.setRotation(Quaternion.axisAngle(Vector3(0, 1, 0), _clock));
    }
    // #endregion pause
    final PhotoCamera? camera = _flying;
    if (!photoMode || camera == null) return;
    // A slow loop that keeps pushing into the walls, to show it stopping.
    camera
      ..look(0.25 * dt, 0.0)
      ..fly(Vector3(0.0, 0.3 * math.sin(_clock * 0.5), 1.0), dt);
    context.camera
      ..setPositionFrom(camera.eye)
      ..lookAt(camera.target, up: camera.up);
  }

  void _enter(DemoContext context, bool on) {
    photoMode = on;
    if (!on) {
      _flying = null;
      context.orbit.apply();
      return;
    }
    // Started from wherever the orbit camera is, which is outside the room:
    // the sweep out from the anchor stops it at the wall.
    _flying =
        PhotoCamera(world: _level.world, bounds: _level.bounds, reach: 5.0)
          ..begin(
            eye: context.camera.readWorldPosition(),
            target: context.orbit.target,
            anchor: Vector3(0.0, 1.2, 0.0),
          );
  }

  @override
  RenderSettings settings(DemoContext context) => photoMode
      ? RenderSettings(
          look: PhotoFilter.all[_filter].applyTo(const LookSettings()),
        )
      : const RenderSettings();

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Photo mode',
      value: () => photoMode,
      onChanged: (bool v) => _enter(context, v),
    ),
    ChoiceControl(
      'Filter',
      options: <String>[for (final PhotoFilter f in PhotoFilter.all) f.name],
      index: () => _filter,
      onChanged: (int i) => _filter = i,
    ),
  ];

  /// The page's claim, as the first thing that is not so, or null.
  @visibleForTesting
  String? wrong() {
    // #region check
    if (report.moves != 600 || report.escapes != 0) {
      return '${report.escapes} of ${report.moves} flights left the room';
    }
    if (report.furthest > 5.0 + 1e-3) {
      return 'the camera got ${report.furthest} m from the player on a 5 m '
          'tether';
    }
    // Begun from behind the wall at z = 4.25: the start is in front of it.
    if (report.startZ > 4.0) return 'the photo began at z ${report.startZ}';
    if (report.tilesX != 2 || report.tilesY != 2) {
      return 'the capture drew ${report.tilesX} by ${report.tilesY} tiles';
    }
    // Every pixel more than two steps off the single frame has to sit on a
    // seam between tiles; away from the seams the picture is the frame.
    if (report.pixels != 640 * 360 || report.awayFromSeams != 0) {
      return '${report.awayFromSeams} pixels away from the seams differ';
    }
    // #endregion check
    return null;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
    final String? problem = wrong();
    if (problem != null) throw StateError(problem);
  }
}
