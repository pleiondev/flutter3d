/// Rendering a scene as a grid of tiles, one at a time, for a picture larger
/// than any single render target.
///
/// Quoted by `tiled_render.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class TiledRenderDemo extends ShowcaseDemo {
  int tilesAcross = 2;
  int tileX = 0;
  int tileY = 0;

  // #region base
  final Projection _base = const PerspectiveProjection(fovYRadians: 0.9);
  // #endregion base

  @override
  Scene build(DemoContext context) {
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.75, 0.6, 0.5, 1.0),
      roughness: 0.75,
    );
    final MeshNode ball = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 32, rings: 16).build(),
      ),
      stone,
      name: 'ball',
    );

    _applyTile(context);

    return Scene()
      ..add(ball)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.2)),
      );
  }

  // #region tile
  void _applyTile(DemoContext context) {
    context.camera.projection = TiledProjection(
      _base,
      tileX: tileX,
      tileY: tileY,
      tilesX: tilesAcross,
      tilesY: tilesAcross,
    );
  }
  // #endregion tile

  @override
  void update(DemoContext context, double dt) => _applyTile(context);

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Grid',
      options: const <String>['1x1', '2x2', '3x3'],
      index: () => tilesAcross - 1,
      onChanged: (int i) {
        tilesAcross = i + 1;
        tileX = tileX.clamp(0, tilesAcross - 1);
        tileY = tileY.clamp(0, tilesAcross - 1);
      },
    ),
    SliderControl(
      'Tile column',
      min: 0,
      max: (tilesAcross - 1).toDouble(),
      divisions: tilesAcross > 1 ? tilesAcross - 1 : null,
      value: () => tileX.toDouble(),
      onChanged: (double v) => tileX = v.round(),
      format: (double v) => '${v.round()}',
    ),
    SliderControl(
      'Tile row',
      min: 0,
      max: (tilesAcross - 1).toDouble(),
      divisions: tilesAcross > 1 ? tilesAcross - 1 : null,
      value: () => tileY.toDouble(),
      onChanged: (double v) => tileY = v.round(),
      format: (double v) => '${v.round()}',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // A 1x1 grid has exactly one tile, and that tile is the whole frustum:
    // the crop this projection applies must be the identity in that case,
    // whatever tile of a larger grid is currently on screen.
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
