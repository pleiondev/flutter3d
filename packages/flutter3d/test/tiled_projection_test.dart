/// `TiledProjection` — `pro-eng-04`'s own row: one tile of a virtual frame no
/// single render target holds, meant to be stitched back together afterwards.
///
///     flutter test test/tiled_projection_test.dart
///
/// The pixel-level acceptance — four tiles rendered and stitched matching one
/// whole frame byte for byte — is `flutter3d_cpu`'s own
/// `tiled_projection_stitch_test.dart`, since drawing anything needs a real
/// device and this package names no backend. What is checked here is the
/// matrix itself, against [Projection.projectToNdc] — the one honest way to
/// assert what a projection does, per that method's own doc comment.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  const base = PerspectiveProjection(fovYRadians: 1.2);
  const aspect = 480 / 360;

  group('a 2x2 grid', () {
    test('each tile maps its own quarter of NDC space to the whole cube', () {
      // A point at the exact centre of the full frame's own near-ish plane
      // sits on every tile's own shared corner — the point every one of the
      // four tiles has to agree is at its own far edge.
      const depth = -2.0;
      final centre = base.projectToNdc(Vector3(0, 0, depth), aspect: aspect);
      // The whole frame's own centre is (0, 0) in its own NDC, by
      // construction of a projection with no off-axis skew.
      expect(centre.x, closeTo(0.0, 1e-9));
      expect(centre.y, closeTo(0.0, 1e-9));

      for (final (tileX, tileY, wantX, wantY) in <(int, int, double, double)>[
        (0, 0, 1.0, -1.0), // bottom-right corner of the top-left tile
        (1, 0, -1.0, -1.0), // bottom-left corner of the top-right tile
        (0, 1, 1.0, 1.0), // top-right corner of the bottom-left tile
        (1, 1, -1.0, 1.0), // top-left corner of the bottom-right tile
      ]) {
        final tile = TiledProjection(
          base,
          tileX: tileX,
          tileY: tileY,
          tilesX: 2,
          tilesY: 2,
        );
        final ndc = tile.projectToNdc(Vector3(0, 0, depth), aspect: aspect);
        expect(ndc.x, closeTo(wantX, 1e-9), reason: 'tile ($tileX, $tileY) x');
        expect(ndc.y, closeTo(wantY, 1e-9), reason: 'tile ($tileX, $tileY) y');
      }
    });

    test('a point inside one tile alone stays off the other three', () {
      // Off-centre so the point sits well inside the *bottom-left* quarter
      // of the full frame's own NDC (x negative, and y negative — NDC y is
      // never flipped in this file, so negative is the bottom), not on a
      // boundary any tile could claim by rounding. Bottom-left is tile
      // (tileX: 0, tileY: 1): `tileY` counts down the way an image's own
      // rows do, so row 1 of 2 is the bottom one.
      final world = Vector3(-0.6, -0.6, -3.0);
      final fullFrame = base.projectToNdc(world, aspect: aspect);
      expect(fullFrame.x, lessThan(-0.1));
      expect(fullFrame.y, lessThan(-0.1));

      for (final (tileX, tileY) in <(int, int)>[
        (0, 0),
        (1, 0),
        (0, 1),
        (1, 1),
      ]) {
        final tile = TiledProjection(
          base,
          tileX: tileX,
          tileY: tileY,
          tilesX: 2,
          tilesY: 2,
        );
        final ndc = tile.projectToNdc(world, aspect: aspect);
        final inside = ndc.x.abs() <= 1.0 && ndc.y.abs() <= 1.0;
        expect(
          inside,
          tileX == 0 && tileY == 1,
          reason:
              'tile ($tileX, $tileY): a point in the bottom-left quarter of '
              'the full frame should read inside only tile (0, 1), and this '
              'one came back at $ndc',
        );
      }
    });
  });

  group('delegation to base', () {
    test('near, far and field of view all come from base', () {
      const wide = PerspectiveProjection(
        fovYRadians: 1.5,
        near: 0.2,
        far: 500.0,
      );
      final tile = TiledProjection(
        wide,
        tileX: 0,
        tileY: 0,
        tilesX: 3,
        tilesY: 2,
      );
      expect(tile.near, 0.2);
      expect(tile.far, 500.0);
      expect(tile.verticalFieldOfView, 1.5);
    });
  });

  group('with no tiling at all', () {
    test('a 1x1 grid is the same projection as base', () {
      final tile = TiledProjection(
        base,
        tileX: 0,
        tileY: 0,
        tilesX: 1,
        tilesY: 1,
      );
      final baseNdc = base.projectToNdc(
        Vector3(0.3, -0.2, -3.0),
        aspect: aspect,
      );
      final tileNdc = tile.projectToNdc(
        Vector3(0.3, -0.2, -3.0),
        aspect: aspect,
      );
      expect(tileNdc.x, closeTo(baseNdc.x, 1e-9));
      expect(tileNdc.y, closeTo(baseNdc.y, 1e-9));
      expect(tileNdc.z, closeTo(baseNdc.z, 1e-9));
    });
  });
}
