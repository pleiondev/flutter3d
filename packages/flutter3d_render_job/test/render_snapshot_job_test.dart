/// `pro-rn-02`'s own acceptance: "480×360 = golden побайтно (×1); ×2 <1 %
/// пикселей" — a snapshot at SSAA ×1 matches a golden byte for byte, and the
/// same project at SSAA ×2 differs from it by under one percent of pixels.
///
///     flutter test test/render_snapshot_job_test.dart
///
/// **The scene, and why it is not `fixture_project.dart`'s own
/// `fixtureProject()`.** That fixture already exists in
/// `flutter3d_model_core/test` and is this repository's own reusable
/// `ModelProject`, but it was built for format round-trip tests: its
/// imported object sits at coordinates chosen to catch a byte at the wrong
/// offset, not to look like anything from any camera, and it nests one
/// object under another — a hierarchy `sceneFromProject` does not walk (see
/// that function's own doc comment). Rendering it would test a camera
/// pointed at whatever those numbers happen to project to rather than at a
/// scene built to be looked at.
///
/// So this file builds a small `ModelProject` instead, reusing the exact
/// shapes, positions, colours and camera pose
/// `packages/flutter3d/test/tiled_projection_stitch_test.dart` already
/// established as this repository's own deterministic "two cubes off the
/// axis, lit from one side" render-test scene — translated into
/// `ParametricGeometry`/`SurfaceMaterial` terms rather than built directly
/// against a `Scene`, since a `RenderSnapshotJob` takes a project.
///
/// **Bloom is off, the same call that test makes and for the same reason its
/// own comment gives.** Bloom is a screen-space blur with a fixed pixel
/// radius: it has no idea a frame was supersampled, so the same bright pixel
/// blurs across a different fraction of the picture at 2x linear resolution
/// than at 1x, and blurs across a tile boundary as though the rest of the
/// frame were not there. Neither is the anti-aliasing or the tiling this
/// file's own three tests are about, and leaving bloom on measures that
/// mismatch instead — this package's own `_downsample` doc comment names the
/// same distinction. Shadows stay on — the engine's own default, and
/// already has its own dedicated coverage elsewhere in this workspace — so
/// this scene is the same one a real project would render minus bloom
/// alone, not a stripped-down stand-in built to flatter this number.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart' show compareFrames;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_render_job/flutter3d_render_job.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The project every test below renders — two cuboids, off the axes, lit
/// from `sceneFromProject`'s own default key and fill lights.
ModelProject _project() {
  var project = ModelProject(
    materials: <ProjectMaterial>[
      ProjectMaterial(
        surface: SurfaceMaterial(
          name: 'a',
          baseColor: Vector4(0.8, 0.3, 0.2, 1.0),
        ),
      ),
      ProjectMaterial(
        surface: SurfaceMaterial(
          name: 'b',
          baseColor: Vector4(0.2, 0.4, 0.9, 1.0),
        ),
      ),
    ],
  );
  project = project.added(
    (int id) => ModelObject(
      id: id,
      name: 'a',
      geometry: ParametricGeometry(ParametricCuboid(size: Vector3.all(1.4))),
      transform: Matrix4.translationValues(0.6, 0.2, 0.0),
      materialSlots: const <int>[0],
    ),
  );
  project = project.added(
    (int id) => ModelObject(
      id: id,
      name: 'b',
      geometry: ParametricGeometry(ParametricCuboid(size: Vector3.all(0.9))),
      transform: Matrix4.translationValues(-0.8, -0.3, 0.5),
      materialSlots: const <int>[1],
    ),
  );
  return project;
}

SnapshotCamera get _camera => SnapshotCamera(
  position: Vector3(2.2, 1.4, 3.4),
  target: Vector3.zero(),
  projection: const PerspectiveProjection(fovYRadians: 0.9),
);

/// Bloom off — see this file's own library comment for why.
const RenderSettings _settings = RenderSettings(
  bloom: BloomSettings(enabled: false),
);

RenderPreset _preset({int ssaa = 1, int tilesX = 1, int tilesY = 1}) =>
    RenderPreset(
      width: 480,
      height: 360,
      camera: _camera,
      ssaa: ssaa,
      tilesX: tilesX,
      tilesY: tilesY,
      settings: _settings,
    );

/// [png] decoded back to RGBA, as a `RenderedFrame` `expectMatchesGolden`
/// and `compareFrames` both already know how to read.
Future<RenderedFrame> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (
      pixels: data!.buffer.asUint8List(),
      width: image.width,
      height: image.height,
      drawCalls: 0,
    );
  } finally {
    image.dispose();
  }
}

void main() {
  test('SSAA x1 matches a golden byte for byte', () async {
    final job = RenderSnapshotJob(_project(), _preset());
    final png = await job.run();
    final frame = await _decode(png);
    expect(frame.width, 480);
    expect(frame.height, 360);
    await expectMatchesGolden(frame, 'test/goldens/render_snapshot_ssaa1.png');
  });

  test('SSAA x2 differs from SSAA x1 by under 1% of pixels', () async {
    final project = _project();

    final ssaa1 = await _decode(
      await RenderSnapshotJob(project, _preset()).run(),
    );
    final ssaa2 = await _decode(
      await RenderSnapshotJob(project, _preset(ssaa: 2)).run(),
    );

    expect(ssaa2.width, ssaa1.width);
    expect(ssaa2.height, ssaa1.height);

    final difference = compareFrames(ssaa1.pixels, ssaa2.pixels);
    // ignore: avoid_print — the row's own acceptance number is the point.
    print(
      'SSAA x1 vs x2: $difference '
      '(${difference.percent.toStringAsFixed(4)}% of pixels differ)',
    );
    expect(
      difference.percent,
      lessThan(1.0),
      reason:
          'pro-rn-02: SSAA x2 must differ from SSAA x1 by under 1% of '
          'pixels; $difference',
    );
  });

  test('a 2x2 tile grid stitches to the same frame as one tile', () async {
    final project = _project();

    final oneTile = await _decode(
      await RenderSnapshotJob(project, _preset()).run(),
    );
    final fourTiles = await _decode(
      await RenderSnapshotJob(project, _preset(tilesX: 2, tilesY: 2)).run(),
    );

    expect(fourTiles.pixels, orderedEquals(oneTile.pixels));
  });

  test('chunkCount is tilesX times tilesY', () {
    final job = RenderSnapshotJob(_project(), _preset(tilesX: 2, tilesY: 3));
    expect(job.chunkCount, 6);
  });

  test('renderTile/finish reach the same PNG as run()', () async {
    final project = _project();
    final preset = _preset();

    final viaRun = await RenderSnapshotJob(project, preset).run();

    final stepped = RenderSnapshotJob(project, preset);
    for (var i = 0; i < stepped.chunkCount; i++) {
      await stepped.renderTile(i);
    }
    final viaChunks = stepped.finish();

    expect(viaChunks, orderedEquals(viaRun));
  });

  test('finish() before any tile refuses rather than crashing', () {
    final job = RenderSnapshotJob(_project(), _preset());
    expect(job.finish, throwsStateError);
  });
}
