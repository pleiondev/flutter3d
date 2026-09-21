/// Rendering a scene as a grid of tiles, one at a time, for a picture larger
/// than any single render target. Every tile is drawn into its own cell of
/// this page's frame, so the whole picture can be seen put back together.
///
/// Quoted by `tiled_render.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class TiledRenderDemo extends ShowcaseDemo {
  int tilesAcross = 3;
  double gap = 0.0;

  // #region base
  final Projection _base = const PerspectiveProjection(fovYRadians: 0.9);
  // #endregion base

  static const int _largestGrid = 4;

  /// One camera per tile, kept apart from the viewport's own: each carries a
  /// different crop of the same view.
  final List<CameraNode> _cameras = <CameraNode>[];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.0
      ..pitch = 0.3
      ..yaw = 0.0;
  }

  @override
  Scene build(DemoContext context) {
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.25
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );

    // Enough that no tile is empty: a corner of the frame with nothing in it
    // would say nothing about whether the pieces fit.
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          context.device,
          const PlaneShape(width: 16.0, depth: 10.0).build(),
        ),
        Material(name: 'floor', baseColor: Vector4(0.4, 0.45, 0.42, 1.0)),
        name: 'floor',
      )..setPosition(0.0, -0.6, 0.0),
    );
    final DeviceMesh ball = DeviceMesh.upload(
      context.device,
      SphereShape(segments: 32, rings: 16).build(),
    );
    final DeviceMesh box = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3.all(1.2)).build(),
    );
    final DeviceMesh ring = DeviceMesh.upload(
      context.device,
      TorusShape(radius: 0.7, tubeRadius: 0.25).build(),
    );
    Material colour(String name, double r, double g, double b) =>
        Material(name: name, baseColor: Vector4(r, g, b, 1.0), roughness: 0.6);
    scene
      ..add(
        MeshNode(ball, colour('ball', 0.9, 0.4, 0.3), name: 'ball')
          ..setPosition(-2.6, 0.0, 0.0),
      )
      ..add(
        MeshNode(box, colour('box', 0.3, 0.6, 0.9), name: 'box')
          ..setPosition(0.0, 0.0, 0.0),
      )
      ..add(
        MeshNode(ring, colour('ring', 0.4, 0.8, 0.5), name: 'ring')
          ..setPosition(2.6, 0.0, 0.0),
      );

    for (var i = 0; i < _largestGrid * _largestGrid; i++) {
      final CameraNode camera = CameraNode(name: 'tile $i');
      _cameras.add(camera);
      scene.add(camera);
    }
    return scene;
  }

  // #region tile
  @override
  List<RenderView> views(DemoContext context) {
    final int n = tilesAcross;
    final double cell = 1.0 / n;
    final double inset = cell * gap / 2;
    // Cells that tile exactly leave a hairline wherever a cell edge falls
    // between two pixels, which reads as the pieces not fitting. Reaching a
    // hair over the neighbour's edge (its own tile is drawn after and takes
    // the pixels back) closes it; pulled apart, there is nothing to close.
    final double reach = gap == 0.0 ? 0.002 : 0.0;
    final Vector3 eye = context.camera.readPosition();
    final Quaternion facing = context.camera.readRotation();
    return <RenderView>[
      for (var row = 0; row < n; row++)
        for (var column = 0; column < n; column++)
          RenderView(
            // The same eye every tile looks from: what differs is which
            // square of the picture it keeps.
            camera: _cameras[row * n + column]
              ..setPositionFrom(eye)
              ..setRotation(facing)
              ..projection = TiledProjection(
                _base,
                tileX: column,
                tileY: row,
                tilesX: n,
                tilesY: n,
              ),
            viewportFraction: ViewportRect(
              column * cell + inset,
              row * cell + inset,
              math.min(cell - 2 * inset + reach, 1.0 - column * cell - inset),
              math.min(cell - 2 * inset + reach, 1.0 - row * cell - inset),
            ),
          ),
    ];
  }
  // #endregion tile

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Grid',
      options: const <String>['1x1', '2x2', '3x3', '4x4'],
      index: () => tilesAcross - 1,
      onChanged: (int i) => tilesAcross = i + 1,
    ),
    SliderControl(
      'Pull apart',
      min: 0,
      max: 0.4,
      value: () => gap,
      onChanged: (double v) => gap = v,
      format: (double v) => v.toStringAsFixed(2),
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < tilesAcross * tilesAcross) {
      throw StateError('every tile of the grid should have drawn something');
    }
    // A 1x1 grid has exactly one tile, and that tile is the whole frustum:
    // the crop this projection applies must be the identity in that case,
    // whatever grid is currently on screen.
    const double aspect = 320 / 180;
    final Matrix4 whole = _base.toMatrix(aspect);
    final Matrix4 singleTile = TiledProjection(
      _base,
      tileX: 0,
      tileY: 0,
      tilesX: 1,
      tilesY: 1,
    ).toMatrix(aspect);
    for (var i = 0; i < 16; i++) {
      if ((whole.storage[i] - singleTile.storage[i]).abs() > 1e-9) {
        throw StateError('a single tile did not reproduce the whole frustum');
      }
    }
  }
}
