/// A sheet pinned along its top edge, stepped live: a ball swings through it
/// and a gust of wind comes and goes, and the sheet drapes, is pushed, and
/// swings back under gravity.
///
/// Quoted by `xpbd_cloth.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class XpbdClothDemo extends ShowcaseDemo {
  double wind = 1.5;
  bool swingBall = true;

  late final ClothMesh _cloth;
  late final ClothObstacle _obstacle;
  late final MeshNode _sheet;
  late final MeshNode _ball;
  late final DeviceMesh Function() _upload;
  double _clock = 0.0;

  static const int _cols = 16;
  static const int _rows = 16;
  static const double _spacing = 0.09;
  static const double _hangs = 1.7;
  static const double _ballRadius = 0.2;
  static const double _step = 1 / 60;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.0
      ..pitch = 0.15
      ..yaw = 0.7;
    context.orbit.target.setValues(0.68, 1.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region cloth
    // Row zero is pinned, which is what stops the sheet falling forever:
    // everything else hangs from it.
    _cloth = ClothMesh.grid(
      cols: _cols,
      rows: _rows,
      spacing: _spacing,
      height: _hangs,
    );
    _obstacle = ClothObstacle(
      CollisionSphere(_ballRadius),
      Vector3(0.68, 1.0, 0.6),
    );
    // #endregion cloth

    _upload = () => DeviceMesh.upload(context.device, _mesh());
    _sheet = MeshNode(
      _upload(),
      Material(
        name: 'cloth',
        baseColor: Vector4(0.8, 0.3, 0.35, 1.0),
        roughness: 0.8,
        doubleSided: true,
      ),
      name: 'cloth',
    );
    _ball = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 24, rings: 12, radius: _ballRadius).build(),
      ),
      Material(name: 'ball', baseColor: Vector4(0.4, 0.5, 0.7, 1.0)),
      name: 'ball',
    )..setPositionFrom(_obstacle.position);

    return Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3
      ..add(_sheet)
      ..add(_ball)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.5, -0.6)),
      );
  }

  /// A mesh from the particle positions and the triangles `ClothMesh.grid`
  /// laid out for them, with a normal at each particle from the triangles
  /// that meet there. Nothing here draws a `ClothMesh` for you; that is the
  /// same gap the heightfield page's own terrain fills.
  MeshData _mesh() {
    final Float64List p = _cloth.positions;
    final List<Vector3> normals = List<Vector3>.generate(
      _cloth.particleCount,
      (int _) => Vector3.zero(),
    );
    Vector3 at(int i) => Vector3(p[3 * i], p[3 * i + 1], p[3 * i + 2]);
    for (var i = 0; i + 2 < _cloth.triangles.length; i += 3) {
      final int a = _cloth.triangles[i];
      final int b = _cloth.triangles[i + 1];
      final int c = _cloth.triangles[i + 2];
      final Vector3 face = (at(b) - at(a)).cross(at(c) - at(a));
      normals[a].add(face);
      normals[b].add(face);
      normals[c].add(face);
    }
    final MeshBuilder builder = MeshBuilder(VertexLayout.standard);
    for (var i = 0; i < _cloth.particleCount; i++) {
      builder.addVertex(
        position: at(i),
        normal: normals[i].length2 == 0.0
            ? Vector3(0.0, 0.0, 1.0)
            : (normals[i]..normalize()),
      );
    }
    for (var i = 0; i + 2 < _cloth.triangles.length; i += 3) {
      builder.addTriangle(
        _cloth.triangles[i],
        _cloth.triangles[i + 1],
        _cloth.triangles[i + 2],
      );
    }
    return builder.build();
  }

  @override
  void update(DemoContext context, double dt) {
    _clock += _step;
    if (swingBall) {
      // Through the sheet and out the other side, and around again.
      _obstacle.position.setValues(
        0.68 + 0.3 * math.sin(_clock * 0.9),
        1.0 + 0.15 * math.sin(_clock * 1.3),
        0.55 * math.sin(_clock * 1.1),
      );
    }

    // #region live
    // A gust that rises and falls, blowing the sheet towards the viewer.
    final double gust = wind * (0.5 + 0.5 * math.sin(_clock * 0.7));
    stepCloth(
      _cloth,
      // Drag 4, not 0.3: until 0.7.4 the wind was added as a velocity, which
      // made 0.3 several hundred times stronger than its value.
      ClothSettings(wind: WindSettings(velocityZ: gust, drag: 4.0)),
      _step,
      obstacles: <ClothObstacle>[_obstacle],
    );
    // #endregion live

    _ball.setPositionFrom(_obstacle.position);
    _sheet.mesh = _upload();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Wind',
      min: 0,
      max: 6,
      value: () => wind,
      onChanged: (double v) => wind = v,
      format: (double v) => v.toStringAsFixed(1),
    ),
    ToggleControl(
      'Swing the ball',
      value: () => swingBall,
      onChanged: (bool v) => swingBall = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // The pinned row never moves: its inverse mass is zero, so no force and
    // no correction ever reaches it.
    if (_cloth.positions[1] != _hangs) {
      throw StateError('the pinned row should not have moved');
    }
    // Left alone with the ball out of the way, the free edge has to sag
    // well below the row it hangs from.
    _obstacle.position.setValues(5.0, 5.0, 5.0);
    for (var i = 0; i < 300; i++) {
      stepCloth(_cloth, const ClothSettings(), _step);
    }
    final int lastRow = (_rows - 1) * _cols;
    for (var col = 0; col < _cols; col++) {
      final double y = _cloth.positions[3 * (lastRow + col) + 1];
      if (y > _hangs - 0.5 * (_rows - 1) * _spacing) {
        throw StateError('the free edge should have hung below its start');
      }
    }
    // And a ball pushed into the sheet must never end up inside it.
    _obstacle.position.setValues(0.68, 1.0, 0.0);
    for (var i = 0; i < 120; i++) {
      stepCloth(
        _cloth,
        const ClothSettings(),
        _step,
        obstacles: <ClothObstacle>[_obstacle],
      );
    }
    for (var i = 0; i < _cloth.particleCount; i++) {
      final Vector3 at = Vector3(
        _cloth.positions[3 * i],
        _cloth.positions[3 * i + 1],
        _cloth.positions[3 * i + 2],
      );
      if (at.distanceTo(_obstacle.position) < _ballRadius - 0.03) {
        throw StateError('a particle passed through the ball');
      }
    }
    // #endregion check
    if (frame.drawCalls < 2) {
      throw StateError('the cloth and the ball did not both reach the frame');
    }
  }
}
