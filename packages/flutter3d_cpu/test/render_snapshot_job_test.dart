/// `pro-rn-02`'s own acceptance: "480×360 = golden побайтно (×1); ×2 <1 %
/// пикселей" — a snapshot at SSAA ×1 matches a golden byte for byte, and the
/// same project at SSAA ×2 differs from it by under one percent of pixels.
///
///     dart test test/render_snapshot_job_test.dart
///
/// Here rather than in `flutter3d_model_core`, where `RenderSnapshotJob`
/// lives, for the reason `render_project_test.dart` beside it gives: a real
/// device is a real backend, and the document layer names none.
///
/// **The scene** reuses the shapes, positions, colours and camera pose
/// `packages/flutter3d/test/tiled_projection_stitch_test.dart` established as
/// this repository's deterministic "two cubes off the axis, lit from one side"
/// render-test scene, translated into `ParametricGeometry`/`SurfaceMaterial`
/// terms, since a `RenderSnapshotJob` takes a project.
///
/// **Bloom is off**, the same call that test makes and for the same reason:
/// bloom is a screen-space blur with a fixed pixel radius, so the same bright
/// pixel blurs across a different fraction of the picture at 2× linear
/// resolution than at 1×, and across a tile boundary as though the rest of the
/// frame were not there. Neither is the anti-aliasing or the tiling these
/// tests are about. Shadows stay on, the engine's own default.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

GraphicsDevice _cpuDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// Two cuboids, off the axes, lit by `sceneFromProject`'s key and fill.
ModelProject _project() {
  final withMaterials = ModelProject(
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
  return withMaterials
      .added(
        (int id) => ModelObject(
          id: id,
          name: 'a',
          geometry: ParametricGeometry(
            ParametricCuboid(size: Vector3.all(1.4)),
          ),
          transform: Matrix4.translationValues(0.6, 0.2, 0.0),
          materialSlots: const <int>[0],
        ),
      )
      .added(
        (int id) => ModelObject(
          id: id,
          name: 'b',
          geometry: ParametricGeometry(
            ParametricCuboid(size: Vector3.all(0.9)),
          ),
          transform: Matrix4.translationValues(-0.8, -0.3, 0.5),
          materialSlots: const <int>[1],
        ),
      );
}

RenderPreset _preset({int ssaa = 1, int tilesX = 1, int tilesY = 1}) =>
    RenderPreset(
      width: 480,
      height: 360,
      camera: SnapshotCamera(
        position: Vector3(2.2, 1.4, 3.4),
        target: Vector3.zero(),
        projection: const PerspectiveProjection(fovYRadians: 0.9),
      ),
      ssaa: ssaa,
      tilesX: tilesX,
      tilesY: tilesY,
      // Bloom off — see this file's own library comment for why.
      // Dither off too. A tile's projection differs from the whole frame's in
      // the last bits of a float, far under one step of the output; the
      // dither offset is what carried one pixel of this scene across a
      // rounding edge, and the stitch is about geometry, not about which
      // side of a half the dither lands on.
      settings: const RenderSettings(
        bloom: BloomSettings(enabled: false),
        look: LookSettings(dither: 0),
      ),
    );

RenderSnapshotJob _job(ModelProject project, RenderPreset preset) =>
    RenderSnapshotJob(project, preset, tileDevice: _cpuDevice);

Future<Rgba8Image> _decode(Uint8List png) async =>
    (await decodeImagePure(png))!;

void main() {
  test('SSAA x1 matches a golden byte for byte', () async {
    final png = await _job(_project(), _preset()).run();
    final frame = await _decode(png);
    // Not under `test/goldens`: that directory is this backend's own golden
    // set, which `tool/structure.dart` counts scene by scene, and a snapshot
    // of a project is not one of its scenes.
    final file = File('test/snapshot/render_snapshot_ssaa1.png');
    // Recorded when missing, off CI only, the rule `expectMatchesGolden`
    // keeps: a machine running the suite must not write its own answer.
    if (!file.existsSync() &&
        !const bool.fromEnvironment('CI') &&
        Platform.environment['CI'] == null) {
      file
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(png);
      markTestSkipped('recorded ${file.path}; open it before committing');
      return;
    }
    final golden = await _decode(file.readAsBytesSync());

    expect((frame.width, frame.height), (480, 360));
    expect(frame.pixels, orderedEquals(golden.pixels));
  });

  test('SSAA x2 differs from SSAA x1 by under 1% of pixels', () async {
    final project = _project();

    final ssaa1 = await _decode(await _job(project, _preset()).run());
    final ssaa2 = await _decode(await _job(project, _preset(ssaa: 2)).run());

    expect((ssaa2.width, ssaa2.height), (ssaa1.width, ssaa1.height));
    final difference = compareFrames(ssaa1.pixels, ssaa2.pixels);
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

    final oneTile = await _decode(await _job(project, _preset()).run());
    final fourTiles = await _decode(
      await _job(project, _preset(tilesX: 2, tilesY: 2)).run(),
    );

    expect(fourTiles.pixels, orderedEquals(oneTile.pixels));
  });

  test('chunkCount is tilesX times tilesY', () {
    expect(_job(_project(), _preset(tilesX: 2, tilesY: 3)).chunkCount, 6);
  });

  test('renderTile/finish reach the same PNG as run()', () async {
    final project = _project();
    final preset = _preset();

    final viaRun = await _job(project, preset).run();

    final stepped = _job(project, preset);
    for (var i = 0; i < stepped.chunkCount; i++) {
      await stepped.renderTile(i);
    }

    expect(stepped.finish(), orderedEquals(viaRun));
  });

  test('finish() before any tile refuses rather than crashing', () {
    expect(_job(_project(), _preset()).finish, throwsStateError);
  });
}
