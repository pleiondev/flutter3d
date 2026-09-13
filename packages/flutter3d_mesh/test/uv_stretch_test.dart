/// `stretchOf` — Sander's own L2 metric, `pro-uv-04`'s worked examples: an
/// isometry reads 1.0, and halving a mapping's own scale reads a known
/// number.
///
///     dart test test/uv_stretch_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';

void _project(EditMesh mesh, List<int> island, UvProjection mode) {
  mesh.beginStep();
  projectUv(mesh, island, mode);
  mesh.endStep();
}

/// Scales every corner UV of [face] by [factor] about the origin — enough to
/// turn an isometric mapping into a known amount of stretch without
/// building a second projection just to get one.
void _scaleUv(EditMesh mesh, int face, double factor) {
  mesh.beginStep();
  mesh.forEachHalfEdge(face, (int half) {
    mesh.setUv(half, mesh.uvOf(half)..scale(factor));
  });
  mesh.endStep();
}

void main() {
  test('a box-projected cube face is a perfect isometry — 1.0', () {
    // `box` mode reads an axis-aligned face's own world edge lengths
    // straight into UV space (`pro-uv-03`'s own acceptance), which is
    // exactly what a stretch of 1.0 means.
    final mesh = EditMesh.cuboid();
    _project(mesh, <int>[0], UvProjection.box);
    expect(stretchOf(mesh, <int>[0]), closeTo(1.0, 1e-9));
  });

  test('every face of the cube agrees, projected independently', () {
    final mesh = EditMesh.cuboid();
    for (var face = 0; face < 6; face++) {
      _project(mesh, <int>[face], UvProjection.box);
    }
    expect(stretchOf(mesh, <int>[0, 1, 2, 3, 4, 5]), closeTo(1.0, 1e-9));
  });

  test('halving the UV scale reads 2.0 — the row\'s own "known number"', () {
    // Mutation: use `ss.length2 + st.length2` without the `/ 2` before the
    // square root, i.e. `sqrt(a + c)` instead of `sqrt((a + c) / 2)` — the
    // isometry test above would then read `sqrt(2)` instead of `1.0` and
    // still be "a number", so it is this test, with an independently known
    // second value, that actually pins the formula rather than just its
    // scale.
    final mesh = EditMesh.cuboid();
    _project(mesh, <int>[0], UvProjection.box);
    _scaleUv(mesh, 0, 0.5);
    expect(stretchOf(mesh, <int>[0]), closeTo(2.0, 1e-9));
  });

  test('doubling the UV scale reads 0.5, the other side of one', () {
    final mesh = EditMesh.cuboid();
    _project(mesh, <int>[0], UvProjection.box);
    _scaleUv(mesh, 0, 2.0);
    expect(stretchOf(mesh, <int>[0]), closeTo(0.5, 1e-9));
  });

  test('area-weighted: a small stretched face barely moves a big island\'s '
      'own answer', () {
    // Two faces of very different UV-space size, both starting isometric —
    // stretching the tiny one hard should barely move the island's own
    // area-weighted answer, because Sander's own metric weights by
    // *world*-space area and both faces are the same world size here (a
    // unit cube's own faces): weight comes from `area3d`, not from how
    // large a face's UV footprint happens to be. Mutation: weight by UV
    // area instead of world area — this test does not distinguish those two
    // for a cube (they are proportional here), so it is not that mutation's
    // catch; it is here to pin the aggregation formula itself, which the
    // single-face tests above cannot.
    final mesh = EditMesh.cuboid();
    _project(mesh, <int>[0], UvProjection.box);
    _project(mesh, <int>[1], UvProjection.box);
    _scaleUv(mesh, 1, 0.5);

    // Two faces, world areas 1 and 1, stretch-squared 1 and 4: RMS over
    // (1*1 + 4*1)/(1+1) = 2.5, sqrt ≈ 1.5811.
    expect(stretchOf(mesh, <int>[0, 1]), closeTo(1.5811388300841898, 1e-9));
  });

  test('a UV-degenerate face contributes nothing rather than dividing by '
      'zero', () {
    final mesh = EditMesh.cuboid();
    _project(mesh, <int>[0], UvProjection.box);
    // Collapse every corner of face 0 onto one UV point: no plane, nothing
    // to measure.
    final onePoint = mesh.uvOf(mesh.halfEdgeOf(0));
    mesh.beginStep();
    mesh.forEachHalfEdge(0, (int half) => mesh.setUv(half, onePoint));
    mesh.endStep();

    expect(stretchOf(mesh, <int>[0]), 0.0);
  });
}
