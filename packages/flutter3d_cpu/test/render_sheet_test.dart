/// `renderSheet` (`flutter3d_model_core`), drawn on a real [CpuDevice] and
/// checked quadrant by quadrant against `renderProject` itself — the half of
/// `mcp-07n`'s own acceptance `flutter3d_model_core` cannot test on its own.
/// See `packages/flutter3d_model_core/lib/src/render_project.dart`'s own doc
/// comment for why the dependency runs this direction.
///
///     dart test test/render_sheet_test.dart
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

GraphicsDevice _cpuDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

ModelProject _cubeProject() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'cube',
    geometry: ParametricGeometry(ParametricCuboid(size: Vector3(2, 2, 2))),
    transform: Matrix4.identity(),
  ),
);

void main() {
  test(
    'a 2x2 sheet, each quarter the same frame render gives for its own view',
    () async {
      final project = _cubeProject();
      // `labels: false`: a labelled quadrant is deliberately *not* what
      // `renderProject` returns, and this is the test that claims it is.
      final sheet = await renderSheet(
        project: project,
        width: 128,
        height: 128,
        labels: false,
        deviceFactory: _cpuDevice,
      );
      final decodedSheet = await decodeImagePure(sheet);
      expect(decodedSheet, isNotNull);
      expect(decodedSheet!.width, 128);
      expect(decodedSheet.height, 128);

      for (var i = 0; i < renderSheetViews.length; i++) {
        final view = renderSheetViews[i];
        final tilePng = await renderProject(
          RenderRequest(project: project, view: view, width: 64, height: 64),
          deviceFactory: _cpuDevice,
        );
        final tile = (await decodeImagePure(tilePng))!;

        final originX = (i % 2) * 64;
        final originY = (i ~/ 2) * 64;
        for (var y = 0; y < 64; y++) {
          for (var x = 0; x < 64; x++) {
            final sheetIndex = ((originY + y) * 128 + (originX + x)) * 4;
            final tileIndex = (y * 64 + x) * 4;
            for (var c = 0; c < 4; c++) {
              expect(
                decodedSheet.pixels[sheetIndex + c],
                tile.pixels[tileIndex + c],
                reason:
                    'quadrant $i ($view) differs from render at '
                    'pixel ($x, $y), channel $c',
              );
            }
          }
        }
      }
    },
  );

  test('each quadrant is labelled with its own view, and only there', () async {
    final project = _cubeProject();
    const int size = 256;
    const int tile = size ~/ 2;
    final plain = (await decodeImagePure(
      await renderSheet(
        project: project,
        width: size,
        height: size,
        labels: false,
        deviceFactory: _cpuDevice,
      ),
    ))!;
    final labelled = (await decodeImagePure(
      await renderSheet(
        project: project,
        width: size,
        height: size,
        deviceFactory: _cpuDevice,
      ),
    ))!;

    // The label box: the bottom-left corner of each quadrant, generously
    // sized. Everything outside every box has to be untouched, or the
    // labels are writing over the picture they annotate.
    const int scale = tile ~/ 64;
    const int boxHeight = (tinyFontHeight + 8) * scale;
    const int boxWidth = tile;
    final changed = List<int>.filled(renderSheetViews.length, 0);
    var changedOutside = 0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final at = (y * size + x) * 4;
        var differs = false;
        for (var c = 0; c < 4; c++) {
          if (plain.pixels[at + c] != labelled.pixels[at + c]) differs = true;
        }
        if (!differs) continue;
        final quadrant = (y ~/ tile) * 2 + (x ~/ tile);
        final withinX = x % tile < boxWidth;
        final withinY = y % tile >= tile - boxHeight;
        if (withinX && withinY) {
          changed[quadrant]++;
        } else {
          changedOutside++;
        }
      }
    }

    expect(
      changedOutside,
      0,
      reason: 'a label wrote outside its own corner of its own quadrant',
    );
    for (var i = 0; i < renderSheetViews.length; i++) {
      expect(
        changed[i],
        greaterThan(0),
        reason: 'quadrant $i (${renderSheetViews[i].name}) has no label',
      );
    }

    // And the marks are the view's own name rather than a generic tag:
    // `front` is five glyphs and `top` is three, so the first quadrant has
    // to carry visibly more ink than the third.
    expect(
      changed[renderSheetViews.indexOf(RenderProjectView.front)],
      greaterThan(changed[renderSheetViews.indexOf(RenderProjectView.top)]),
    );
  });

  test('an odd sheet size loses at most a pixel, not a crash', () async {
    final sheet = await renderSheet(
      project: _cubeProject(),
      width: 65,
      height: 65,
      deviceFactory: _cpuDevice,
    );
    final decoded = await decodeImagePure(sheet);
    expect(decoded, isNotNull);
    expect(decoded!.width, 64);
    expect(decoded.height, 64);
  });

  test('a refusal from a quadrant surfaces as renderSheet\'s own refusal', () {
    expect(
      () => renderSheet(
        project: _cubeProject(),
        width: 3000,
        height: 512,
        deviceFactory: _cpuDevice,
      ),
      throwsA(isA<RenderRefusal>()),
    );
  });
}
