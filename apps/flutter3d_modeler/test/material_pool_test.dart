/// `MaterialPool`'s own texture cache, keyed by what an image contains
/// rather than where it sits in the table — `mat-07`'s own acceptance: a
/// hundred edits to one material's roughness upload one image, not a
/// hundred, and two table rows that happen to hold the same bytes share one
/// texture rather than paying for it twice.
///
///     flutter test test/material_pool_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/material_pool.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tiny, real PNG — not a hand-rolled fixture — so the pool decodes it the
/// way it would decode anything a project actually holds.
Uint8List _solidColorPng(int r, int g, int b) => encodePng(
  Uint8List.fromList(<int>[
    r,
    g,
    b,
    255,
    r,
    g,
    b,
    255,
    r,
    g,
    b,
    255,
    r,
    g,
    b,
    255,
  ]),
  2,
  2,
);

ProjectMaterial _paintedWith(
  int imageIndex, {
  int version = 1,
  double roughness = 0.5,
}) => ProjectMaterial(
  surface: SurfaceMaterial(
    roughness: roughness,
    baseColorTexture: TextureBinding(imageIndex: imageIndex),
  ),
  version: version,
);

void main() {
  test(
    'two table rows with the same bytes share one uploaded texture',
    () async {
      final red = _solidColorPng(255, 0, 0);
      final blue = _solidColorPng(0, 0, 255);
      // Fresh Uint8List instances holding the same bytes as `red`, not the same
      // reference — this is the case a table-index key would still fail, and a
      // key on identity rather than content would too.
      final redAgain = Uint8List.fromList(red);

      final project = ModelProject(
        images: <EncodedImage>[
          EncodedImage(bytes: red),
          EncodedImage(bytes: redAgain),
          EncodedImage(bytes: blue),
        ],
        materials: <ProjectMaterial>[
          _paintedWith(0),
          _paintedWith(1),
          _paintedWith(2),
        ],
      );

      final device = FakeBackend();
      final pool = MaterialPool(device: device);
      final built = await pool.refresh(project);

      expect(built, 3, reason: 'every material was new and had to be built');
      expect(
        device.uploadedTextures.length,
        2,
        reason:
            'three images, two distinct byte contents — the repeated red '
            'should not decode or upload a second time',
      );
    },
  );

  test('an unchanged project rebuilds nothing on a second refresh', () async {
    final png = _solidColorPng(10, 20, 30);
    final project = ModelProject(
      images: <EncodedImage>[EncodedImage(bytes: png)],
      materials: <ProjectMaterial>[_paintedWith(0)],
    );

    final device = FakeBackend();
    final pool = MaterialPool(device: device);
    await pool.refresh(project);
    final builtAgain = await pool.refresh(project);

    expect(builtAgain, 0);
    expect(device.uploadedTextures.length, 1);
  });

  test('a hundred roughness edits upload their shared image once', () async {
    final png = _solidColorPng(200, 200, 200);
    final device = FakeBackend();
    final pool = MaterialPool(device: device);

    var project = ModelProject(
      images: <EncodedImage>[EncodedImage(bytes: png)],
      materials: <ProjectMaterial>[_paintedWith(0)],
    );
    await pool.refresh(project);
    expect(device.uploadedTextures.length, 1);

    for (var edit = 0; edit < 100; edit++) {
      project = ModelProject(
        images: project.images,
        materials: <ProjectMaterial>[
          _paintedWith(0, version: edit + 2, roughness: edit / 100),
        ],
      );
      await pool.refresh(project);
    }

    expect(
      device.uploadedTextures.length,
      1,
      reason:
          'a hundred edits to the same material\'s roughness rebuild the '
          'material a hundred times, but its texture is the one image it '
          'always pointed at',
    );
  });
}
