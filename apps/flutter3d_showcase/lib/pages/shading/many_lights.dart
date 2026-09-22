/// Thirty-two lights on one draw: eight in the shader's own slots and
/// twenty-four more through the light list, with `lightFadeBand` softening
/// the edge between them. Tiled rather than one giant plane, so which
/// torches reach a given tile is a real question — see `#region floor`.
///
/// Quoted by `many_lights.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ManyLightsDemo extends ShowcaseDemo {
  double fadeBand = 0.5;

  /// Eight direct slots plus the twenty-four-light tail is thirty-two; eight
  /// more than that is what a floor this crowded actually has to drop.
  static const int _torchCount = 40;

  /// The floor as a grid of tiles rather than one plane — see `#region
  /// floor` for why.
  static const int _tilesPerSide = 5;
  static const double _floorSize = 20.0;
  static const double _tileSize = _floorSize / _tilesPerSide;

  /// Wide enough that every tile, edge or centre, has more than the
  /// thirty-two the list can carry within reach — the case the fade band
  /// needs, and past a torch's own visible glow long before its falloff
  /// actually reaches this far.
  static const double _torchRange = 12.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 12.0
      ..pitch = 0.7;
  }

  @override
  Scene build(DemoContext context) {
    final Scene scene = Scene();

    // #region floor
    // A grid of tiles, not one plane. A single 20x20 draw's own bounding
    // sphere (radius about 14) reaches every torch on the ring below, six
    // units out — every one of them lands *inside* it, and `_relevanceIn`
    // scores a light inside an object's sphere at that object's ceiling
    // regardless of exactly where inside it sits. Selection then cannot
    // tell one torch from another, and `lightFadeBand` has nothing to
    // soften: every candidate ties, so the torch that finally overflows the
    // list is exactly as strong as the thirty-two that did not. Twenty-five
    // four-by-four tiles each carry a bounding sphere small enough, next to
    // a torch's own wide range, that how far a tile sits from the ring is a
    // real question with a real answer — the tile at the very centre is
    // furthest from every torch at once, and is where the band has
    // something to soften.
    final DeviceMesh tile = DeviceMesh.upload(
      context.device,
      PlaneShape(width: _tileSize, depth: _tileSize).build(),
    );
    final Material floorMaterial = Material(
      baseColor: Vector4(0.5, 0.5, 0.55, 1.0),
      roughness: 0.85,
      doubleSided: true,
    );
    for (var row = 0; row < _tilesPerSide; row++) {
      for (var col = 0; col < _tilesPerSide; col++) {
        final double x = (col - (_tilesPerSide - 1) / 2) * _tileSize;
        final double z = (row - (_tilesPerSide - 1) / 2) * _tileSize;
        scene.add(
          MeshNode(tile, floorMaterial, name: 'floor $row,$col')
            ..setPosition(x, 0.0, z),
        );
      }
    }
    // #endregion floor

    // #region torches
    for (var i = 0; i < _torchCount; i++) {
      final double angle = i / _torchCount * 2.0 * math.pi;
      scene.add(
        LightNode(
          name: 'torch $i',
          type: LightType.point,
          intensity: 2.5,
          range: _torchRange,
        )..setPosition(math.cos(angle) * 6.0, 0.6, math.sin(angle) * 6.0),
      );
    }
    // #endregion torches

    return scene;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    lightFadeBand: fadeBand,
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Fade band',
      min: 0,
      max: 1,
      value: () => fadeBand,
      onChanged: (double v) => fadeBand = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (scene.lights.length != _torchCount) {
      throw StateError(
        'expected $_torchCount torches, found '
        '${scene.lights.length}',
      );
    }
    final int expectedDropped = math.max(
      _torchCount - LightBuffer.maxLights - LightBuffer.maxExtraLights,
      0,
    );
    if (expectedDropped == 0) {
      throw StateError(
        'this scene needs more torches than the cap to prove '
        'anything is actually dropped',
      );
    }
    if (frame.lightsDropped != expectedDropped) {
      throw StateError(
        'expected $expectedDropped lights past the eight slots and the '
        'twenty-four-light tail, the frame reports ${frame.lightsDropped}',
      );
    }
    final int tileCount = _tilesPerSide * _tilesPerSide;
    if (scene.meshes.length != tileCount) {
      throw StateError(
        'expected $tileCount floor tiles, found ${scene.meshes.length} — a '
        'floor back to one plane gives every torch the same bounding-sphere '
        'ceiling and the fade band nothing to soften',
      );
    }
    if (frame.drawCalls < tileCount) {
      throw StateError('fewer than $tileCount tiles were drawn');
    }
    // #endregion check
  }
}
