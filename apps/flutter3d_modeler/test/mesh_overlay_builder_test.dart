/// What the modeller draws on top of the mesh, and what it refuses to redraw.
///
///     flutter test test/mesh_overlay_builder_test.dart
///
/// **Counted vertices rather than a picture.** The overlay's own package is
/// where "does a line come out of the rasteriser" is answered; what is in
/// question here is which lines were asked for. A cube with a face selected is
/// twelve lines, four ribbons and two triangles, and every one of those numbers
/// is a decision — an edge drawn once rather than once per half-edge, a shared
/// edge of two selected faces drawn once rather than twice, a face cut into
/// triangles by its own outline rather than fanned from a corner. Where a count
/// would pass for the right number of the wrong things — four ribbons anywhere
/// on the cube are still four ribbons — a position is asserted as well.
///
/// **The two timing tests are the point of the class.** Everything else here
/// would pass just as well against a builder that rebuilds all three batches
/// every frame; those two say what such a builder costs on a mesh somebody is
/// actually working on, and they assert the flags as well as the clock so that
/// they fail for the right reason on a machine of any speed.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/mesh_overlay_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// An overlay with no device behind it.
///
/// The handles are never dereferenced: nothing here encodes a frame, and a
/// pipeline is created on the first `encode` rather than in the constructor.
MeshOverlay _overlay() {
  final overlay = MeshOverlay(
    vertexShader: const ShaderHandle(backend: 0, name: 'DebugLineVertex'),
    fragmentShader: const ShaderHandle(backend: 0, name: 'DebugLineFragment'),
  );
  // The depth bias moves every vertex towards the eye, which would put a
  // fraction of a per cent on every position and area asserted below. Zero
  // here so the geometry tests are exact; the tests that care about the bias
  // put it back.
  overlay.biasPixels = 0;
  return overlay;
}

/// Looking down −Z from five units away, with a pixel about a thousandth of a
/// unit at that distance — a viewport some eight hundred pixels tall.
MeshOverlayView _view({Vector3? eye, Vector3? right, Vector3? up}) =>
    MeshOverlayView(
      eye: eye ?? Vector3(0, 0, 5),
      right: right ?? Vector3(1, 0, 0),
      up: up ?? Vector3(0, 1, 0),
      pixel: 0.0012,
    );

double _floatAt(OverlayBatch batch, int vertex, int field) =>
    batch.vertexBytes.getFloat32(
      (vertex * MeshOverlay.floatsPerVertex + field) * 4,
      Endian.host,
    );

Vector3 _positionAt(OverlayBatch batch, int vertex) => Vector3(
  _floatAt(batch, vertex, 0),
  _floatAt(batch, vertex, 1),
  _floatAt(batch, vertex, 2),
);

Vector4 _colourAt(OverlayBatch batch, int vertex) => Vector4(
  _floatAt(batch, vertex, 3),
  _floatAt(batch, vertex, 4),
  _floatAt(batch, vertex, 5),
  _floatAt(batch, vertex, 6),
);

/// How many vertices of [batch] were written in [colour], ignoring alpha —
/// which the wash rewrites on its way in.
int _countColoured(OverlayBatch batch, Vector4 colour) {
  // Against what the overlay stores rather than against the palette directly:
  // `MeshOverlay.asDrawn` converts a colour a design named into the linear
  // quantity the scene pass wants, because everything written there is encoded
  // again on the way out. Comparing to the palette would be comparing to the
  // number before that conversion, and would count nothing at all.
  final drawn = MeshOverlay.asDrawn(colour);
  var found = 0;
  for (var vertex = 0; vertex < batch.vertexCount; vertex++) {
    final at = _colourAt(batch, vertex);
    if (at.x == drawn.x && at.y == drawn.y && at.z == drawn.z) found++;
  }
  return found;
}

/// The area of every triangle in a fill batch, added up.
///
/// Areas rather than positions, because what a triangulation gets wrong is
/// *coverage*: a wash that fans a concave face out of order covers ground the
/// face does not, and the total area is where that shows up as one number.
double _fillArea(OverlayBatch batch) {
  var area = 0.0;
  for (var triangle = 0; triangle + 2 < batch.vertexCount; triangle += 3) {
    final a = _positionAt(batch, triangle);
    final b = _positionAt(batch, triangle + 1);
    final c = _positionAt(batch, triangle + 2);
    area += (b - a).cross(c - a).length / 2;
  }
  return area;
}

/// A quad with a dent in it, and with the dent's corner *last* — so that a
/// triangulation fanning from the first corner picks the diagonal that lies
/// outside the outline. Wound counter-clockwise seen from +Z, where the camera
/// is.
EditMesh _dentedQuad() => EditMesh.fromFaces(
  <Vector3>[
    Vector3(0, 2, 0),
    Vector3(0, 0, 0),
    Vector3(2, 0, 0),
    Vector3(1, 0.5, 0),
  ],
  <List<int>>[
    <int>[0, 1, 2, 3],
  ],
);

void main() {
  group('a cube with a face selected', () {
    test('is twelve lines, four ribbons and two triangles', () {
      final mesh = EditMesh.cuboid();
      final overlay = _overlay();

      MeshOverlayBuilder().build(
        overlay,
        mesh: mesh,
        selection: Selection.of(ElementLevel.face, <int>[0]),
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(),
      );

      // Twelve edges, two vertices each. Mutation: drop the
      // `mesh.edgeOf(half) != half` test in `_emitLines` and this is 48 — every
      // edge drawn once from each side, twice the buffer and twice the upload
      // for a wireframe that looks identical until somebody profiles it.
      expect(overlay.lines.vertexCount, 24);
      // Four edges of the selected face, six vertices per ribbon quad.
      // Mutation: draw the selection at every level rather than at its own —
      // convert it to vertices as well — and this is 48, with a handle on every
      // corner of a face nobody can drag a corner of.
      expect(overlay.handles.vertexCount, 24);
      // A quad is two triangles. Mutation: wash nothing at face level — return
      // from `_emitFill` before its loop — and this is zero, which is a
      // selected face a person cannot see is selected.
      expect(overlay.fill.vertexCount, 6);
    });

    test('draws the edge two selected faces share once', () {
      final mesh = EditMesh.cuboid();
      final overlay = _overlay();
      // Faces 0 and 2 of the cuboid share an edge; if the pair ever stops
      // sharing one this test is asserting nothing, so it checks.
      final shared = <int>{};
      for (final face in <int>[0, 2]) {
        mesh.forEachHalfEdge(face, (int half) => shared.add(mesh.edgeOf(half)));
      }
      expect(shared.length, 7, reason: 'two quads sharing one edge');

      MeshOverlayBuilder().build(
        overlay,
        mesh: mesh,
        selection: Selection.of(ElementLevel.face, <int>[0, 2]),
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(),
      );

      // Mutation: drop the `drawn` set in `_emitHandles` and this is 48 — the
      // shared edge gets two ribbons in the same place, which on a translucent
      // pass reads as one seam of the selection being brighter than the rest.
      expect(overlay.handles.vertexCount, 42);
      expect(overlay.fill.vertexCount, 12);
    });

    test('puts its ribbons down the selected face and nowhere else', () {
      final mesh = EditMesh.cuboid();
      final overlay = _overlay();

      MeshOverlayBuilder().build(
        overlay,
        mesh: mesh,
        selection: Selection.of(ElementLevel.face, <int>[0]),
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(),
      );

      // A ribbon is two triangles over a parallelogram, so its six vertices
      // average to the middle of the edge it was drawn along whatever width and
      // orientation the camera gave it. Face 0 of the cuboid is the +Z quad,
      // and these are its four edge middles.
      final wanted = <Vector3>[
        Vector3(0, -0.5, 0.5),
        Vector3(0.5, 0, 0.5),
        Vector3(0, 0.5, 0.5),
        Vector3(-0.5, 0, 0.5),
      ];
      final found = <Vector3>[];
      for (var ribbon = 0; ribbon * 6 < overlay.handles.vertexCount; ribbon++) {
        final middle = Vector3.zero();
        for (var corner = 0; corner < 6; corner++) {
          middle.add(_positionAt(overlay.handles, ribbon * 6 + corner));
        }
        found.add(middle * (1 / 6));
      }

      // The counts above would pass for four ribbons drawn anywhere on the
      // cube, so this asks where they went. Mutation: take the quad's diagonals
      // rather than its edges — `_to` from
      // `originOf(nextOf(nextOf(half)))` in the face branch of `_emitHandles` —
      // and there are still four ribbons of six vertices each, but every one of
      // them runs through the middle of the face, so a person who selected a
      // quad is shown a cross.
      for (final at in wanted) {
        expect(
          found.any((Vector3 middle) => (middle - at).length < 1e-5),
          isTrue,
          reason: 'a ribbon down the edge whose middle is $at, in $found',
        );
      }
    });

    test('washes a dented face by its outline, not by a fan', () {
      final mesh = _dentedQuad();
      final overlay = _overlay();

      MeshOverlayBuilder().build(
        overlay,
        mesh: mesh,
        selection: Selection.of(ElementLevel.face, <int>[0]),
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(),
      );

      expect(overlay.fill.vertexCount, 6);
      // The outline encloses 1.5 square units. Mutation: fan the face from its
      // first corner — `emit(0, i, i + 1)` in place of the triangulator — and
      // this is 2.5: one of the two triangles lands outside the face
      // altogether, so the highlight claims a piece of the model that is not
      // selected and the person moves the wrong thing.
      expect(_fillArea(overlay.fill), closeTo(1.5, 1e-5));
    });
  });

  group('the level decides what the selection is drawn as', () {
    test('vertex level puts a handle on every vertex, selected or not', () {
      final mesh = EditMesh.cuboid();
      final overlay = _overlay();
      final colours = MeshOverlayColours();

      MeshOverlayBuilder(colours: colours).build(
        overlay,
        mesh: mesh,
        selection: Selection.of(ElementLevel.vertex, <int>[1, 3]),
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(),
      );

      // Eight corners, six vertices per quad. Mutation: draw only the selected
      // vertices and this is 12 — a vertex level where the corners a person has
      // not clicked yet are invisible, which is a level nobody can start
      // selecting in.
      expect(overlay.handles.vertexCount, 48);
      // Mutation: hand every handle the same colour and this is 48 — the two
      // selected corners stop being distinguishable from the six others, which
      // is the whole information the level carries.
      expect(_countColoured(overlay.handles, colours.selected), 12);
      expect(_countColoured(overlay.handles, colours.vertex), 36);
      // Nothing is a face here, so nothing is washed.
      expect(overlay.fill.vertexCount, 0);
    });

    test('edge level is ribbons and no fill', () {
      final mesh = EditMesh.cuboid();
      final overlay = _overlay();
      final edges = <int>[];
      mesh.forEachHalfEdge(0, (int half) => edges.add(mesh.edgeOf(half)));

      MeshOverlayBuilder().build(
        overlay,
        mesh: mesh,
        selection: Selection.of(ElementLevel.edge, edges.take(3)),
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(),
      );

      // Three ribbons. Mutation: convert an edge selection up to faces as well
      // and the fill below stops being empty — three edges of a face are not a
      // selected face, and washing one says a person has selected something
      // they have not.
      expect(overlay.handles.vertexCount, 18);
      expect(overlay.fill.vertexCount, 0);
    });

    test('a face that was deleted under the selection draws nothing', () {
      final mesh = EditMesh.cuboid();
      final overlay = _overlay();
      final selection = Selection.of(ElementLevel.face, <int>[0, 2]);
      mesh
        ..beginStep()
        ..deleteFace(0)
        // A vertex whose way into the mesh was a half-edge of the face that has
        // just died needs another one, and the mesh asks its caller to say so
        // once rather than looking per face.
        ..repairVertexLinks()
        ..endStep();

      MeshOverlayBuilder().build(
        overlay,
        mesh: mesh,
        selection: selection,
        meshVersion: 2,
        selectionVersion: 1,
        view: _view(),
      );

      // One live face of the two the selection names. Mutation: drop the
      // `_faceIsAlive` guard in `_emitFill` and this is 12 — a tombstone keeps
      // its half-edges and its corners, so the wash is drawn over a face that
      // is no longer in the model and the person is looking at something they
      // deleted.
      expect(overlay.fill.vertexCount, 6);
      // Four ribbons, not eight, for the same reason.
      expect(overlay.handles.vertexCount, 24);
    });
  });

  group('nothing is rebuilt that did not change', () {
    test('the same frame twice rebuilds nothing at all', () {
      final mesh = EditMesh.cuboid();
      final overlay = _overlay();
      final builder = MeshOverlayBuilder();
      final selection = Selection.of(ElementLevel.face, <int>[0]);

      final first = builder.build(
        overlay,
        mesh: mesh,
        selection: selection,
        meshVersion: 7,
        selectionVersion: 3,
        view: _view(),
      );
      expect(first, (lines: true, handles: true, fill: true));

      // The mesh moves without saying so. Nothing about this is legal — it is
      // what a caller that forgot to bump its version does — and it is the only
      // way a test can *see* that the second build re-emitted nothing rather
      // than re-emitting the same numbers.
      mesh
        ..beginStep()
        ..moveVertex(0, Vector3(9, 9, 9))
        ..endStep();

      final again = builder.build(
        overlay,
        mesh: mesh,
        selection: selection,
        meshVersion: 7,
        selectionVersion: 3,
        view: _view(),
      );

      // Mutation: leave the version comparisons out — rebuild unconditionally —
      // and this record is (true, true, true), which is where that mutation is
      // caught and where the test stops: a failing `expect` throws, so the loop
      // below never runs. A modeller that rebuilds a two-hundred-thousand-edge
      // wireframe on a frame where nothing happened has spent its whole budget
      // on it.
      expect(again, (lines: false, handles: false, fill: false));
      // The loop is the other half of the claim, and it runs on the way past
      // rather than in answer to a mutation: it is what makes `lines: false`
      // mean the batch was left alone rather than refilled with the same
      // numbers, since a refill would have brought the corner moved to (9, 9, 9)
      // along with it.
      for (var vertex = 0; vertex < overlay.lines.vertexCount; vertex++) {
        expect(_positionAt(overlay.lines, vertex).x.abs(), lessThan(1));
      }
    });

    test('a selection that changed leaves the lines alone', () {
      final mesh = EditMesh.cuboid();
      final overlay = _overlay();
      final builder = MeshOverlayBuilder();

      builder.build(
        overlay,
        mesh: mesh,
        selection: Selection.of(ElementLevel.face, <int>[0]),
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(),
      );
      final rebuilt = builder.build(
        overlay,
        mesh: mesh,
        selection: Selection.of(ElementLevel.face, <int>[0, 2]),
        meshVersion: 1,
        selectionVersion: 2,
        view: _view(),
      );

      // Mutation: fold `selectionChanged` into `rebuildLines` and this is true.
      // The lines are the same lines whatever is selected, and rebuilding them
      // is the cost of a click paid over the whole mesh — which is what makes
      // a box-select, one selection change per frame, drop frames.
      expect(rebuilt, (lines: false, handles: true, fill: true));
      expect(overlay.lines.vertexCount, 24);
      expect(overlay.handles.vertexCount, 42);
    });

    test('a camera that turns in place rebuilds the handles and only those', () {
      final mesh = EditMesh.cuboid();
      final overlay = _overlay();
      final builder = MeshOverlayBuilder();
      final selection = Selection.of(ElementLevel.vertex, <int>[0]);

      builder.build(
        overlay,
        mesh: mesh,
        selection: selection,
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(),
      );
      final before = _positionAt(overlay.handles, 0);

      // The same eye, rolled 90 degrees: right and up swap places, which is
      // what a handle is squared up against and nothing else in here is.
      final rebuilt = builder.build(
        overlay,
        mesh: mesh,
        selection: selection,
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(right: Vector3(0, 1, 0), up: Vector3(-1, 0, 0)),
      );

      // Mutation: fold `turned` into `rebuildLines` and this is `lines: true` —
      // every frame of an orbit rebuilds the wireframe for a camera basis the
      // wireframe does not read. Leaving `turned` out of `rebuildHandles`
      // instead lands on the same line as `handles: false`, and lands there
      // first: this is the first `expect` in the test, and a failing one throws
      // before anything below it is read.
      expect(rebuilt, (lines: false, handles: true, fill: false));
      // Which leaves this line the case the flags cannot state — a rebuild
      // reported and not done. Run with `turned` out of `rebuildHandles` and
      // the returned flag masked back to a constant true, the record above
      // passes and this fails: a vertex handle is a quad squared up against
      // `right` and `up`, so a roll of ninety degrees has to move its first
      // corner, and at ninety degrees of drift the old quad is edge-on and the
      // vertex has disappeared.
      expect(_positionAt(overlay.handles, 0), isNot(before));
    });

    test('an eye that moves rebuilds the handles with the bias switched off', () {
      final mesh = EditMesh.cuboid();
      // `_overlay` turns the depth bias off, which is also what a caller that
      // offsets depth in the pipeline instead has done — and with no nudge
      // there is nothing for the drift test to measure, so it can say nothing
      // about the camera at all. This is the case that needs the eye compared
      // on its own.
      final overlay = _overlay();
      final builder = MeshOverlayBuilder();
      final edges = <int>[];
      mesh.forEachHalfEdge(0, (int half) => edges.add(mesh.edgeOf(half)));
      final selection = Selection.of(ElementLevel.edge, edges.take(1));

      builder.build(
        overlay,
        mesh: mesh,
        selection: selection,
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(),
      );
      final before = _positionAt(overlay.handles, 0);

      // Straight in from five units to just over half a one, with the basis
      // untouched: a dolly, which turns nothing.
      final rebuilt = builder.build(
        overlay,
        mesh: mesh,
        selection: selection,
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(eye: Vector3(0, 0, 0.6)),
      );

      // Mutation: leave `moved` out of `rebuildHandles` and this is
      // `handles: false` — with the bias off nothing else in the builder
      // notices a camera that moved, so the ribbon keeps the width and the
      // twist the far camera gave it for as long as the session lasts.
      expect(rebuilt, (lines: false, handles: true, fill: false));
      // And the corner really moved, so `handles: true` is not a flag raised
      // over a batch refilled with the same numbers: a ribbon is as wide as the
      // eye is far and lies across the direction to it, and this eye is under a
      // ninth of the distance from that edge that the first one was.
      expect(_positionAt(overlay.handles, 0), isNot(before));
    });

    test('an eye that moves far enough to spoil the bias rebuilds the lines', () {
      final mesh = EditMesh.cuboid();
      // The bias is what this is about, so it is left at its default here.
      final overlay = MeshOverlay(
        vertexShader: const ShaderHandle(backend: 0, name: 'DebugLineVertex'),
        fragmentShader: const ShaderHandle(
          backend: 0,
          name: 'DebugLineFragment',
        ),
      );
      final builder = MeshOverlayBuilder();
      final selection = Selection.of(ElementLevel.face, <int>[0]);

      builder.build(
        overlay,
        mesh: mesh,
        selection: selection,
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(),
      );

      // A degree or so of orbit. Mutation: rebuild whenever the eye is not
      // exactly where it was — drop `biasDrift` and compare eyes — and this is
      // true, which means every frame of every orbit rebuilds the wireframe and
      // the budget below buys nothing.
      final nudged = builder.build(
        overlay,
        mesh: mesh,
        selection: selection,
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(eye: Vector3(0.1, 0, 5)),
      );
      expect(nudged.lines, isFalse);

      // Round to the far side. Mutation: never test the drift — `biasStale` is
      // only ever true on the first build — and this is false: the wireframe
      // keeps a nudge pointing away from where the camera now is, so it is
      // pushed *into* the surface, fails the depth test and the model loses its
      // edges from behind.
      final orbited = builder.build(
        overlay,
        mesh: mesh,
        selection: selection,
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(eye: Vector3(5, 0, 0)),
      );
      expect(orbited.lines, isTrue);
    });
  });

  group('a mesh with more edges than are worth drawing', () {
    late EditMesh large;

    setUpAll(() {
      // Two hundred thousand edges, which is a mesh somebody would open rather
      // than a number invented for the test: a plane cut into a hundred
      // thousand quads.
      large = const ParametricPlane(
        widthSegments: 316,
        depthSegments: 316,
      ).toEditMesh();
      expect(large.edgeCount, greaterThan(200000));
    });

    test('the wireframe is thinned to the budget', () {
      final overlay = _overlay();

      MeshOverlayBuilder().build(
        overlay,
        mesh: large,
        selection: Selection.of(ElementLevel.face, <int>[0]),
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(eye: Vector3(0, 3, 0), up: Vector3(0, 0, -1)),
      );

      // Exactly the budget, two vertices each. Mutation: return true from
      // `_Thinning.take` unconditionally and this is 400 688 — five megabytes
      // of line vertices rebuilt and uploaded for a wireframe that at this
      // density is a grey wash with a silhouette.
      expect(overlay.lines.vertexCount, 200000);
    });

    test(
      'a smaller budget keeps a smaller share, and a cube keeps all of it',
      () {
        final cube = EditMesh.cuboid();
        final overlay = _overlay();
        final builder = MeshOverlayBuilder(edgeBudget: 5);

        builder.build(
          overlay,
          mesh: cube,
          selection: Selection.empty(ElementLevel.face),
          meshVersion: 1,
          selectionVersion: 1,
          view: _view(),
        );
        // Five of twelve, which is the budget exactly. Mutation: compute a
        // whole-number stride — `(total + budget - 1) ~/ budget`, then keep
        // every n-th — and this is 8: twelve edges into a budget of five rounds
        // to every third edge, so a fifth of what the machine was willing to
        // draw is thrown away, and the larger the mesh the worse the rounding.
        expect(overlay.lines.vertexCount, 10);

        final whole = _overlay();
        MeshOverlayBuilder().build(
          whole,
          mesh: cube,
          selection: Selection.empty(ElementLevel.face),
          meshVersion: 1,
          selectionVersion: 1,
          view: _view(),
        );
        // A cube against the default budget keeps all twelve. No mutation is
        // named for this one, and that is the honest answer rather than a
        // missing one: dropping the `total <= budget` short circuit in
        // `_Thinning` changes nothing, because the counter keeps every element
        // when the budget is at least the total — it was run, the suite stayed
        // green, and the line is a saved add per edge rather than a rule. What
        // this assertion is here for is the other direction, that the thinning
        // above did not follow the mesh home to a cube.
        expect(whole.lines.vertexCount, 24);
      },
    );

    test('changing the selection costs a selection, not a mesh', () {
      final overlay = _overlay();
      final builder = MeshOverlayBuilder();
      final view = _view(eye: Vector3(0, 3, 0), up: Vector3(0, 0, -1));

      final clock = Stopwatch()..start();
      builder.build(
        overlay,
        mesh: large,
        selection: Selection.of(ElementLevel.face, <int>[0]),
        meshVersion: 1,
        selectionVersion: 1,
        view: view,
      );
      final whole = clock.elapsedMicroseconds;

      clock.reset();
      final rebuilt = builder.build(
        overlay,
        mesh: large,
        selection: Selection.of(ElementLevel.face, <int>[1, 2, 3]),
        meshVersion: 1,
        selectionVersion: 2,
        view: view,
      );
      final change = clock.elapsedMicroseconds;

      expect(rebuilt, (lines: false, handles: true, fill: true));
      // The acceptance number: a click on a two-hundred-thousand-edge mesh
      // inside a frame, which is what a person dragging a selection box feels,
      // because they change the selection once per frame. This is three faces
      // of work and lands in tens of microseconds, so the twenty milliseconds
      // is loose enough for a loaded machine.
      expect(change, lessThan(20000));
      // A bound in microseconds is only ever as strict as the machine is slow,
      // so here is one that is not: a quarter of what the first build of the
      // same frame cost, measured on the same machine in the same run. What it
      // is for is the case no flag can state — a builder that reports
      // `lines: false` and rebuilds them anyway, which the record above would
      // wave through. Run that way, `selectionChanged` folded into
      // `rebuildLines` with the returned flag masked back to false, the second
      // build took 78.9, 123.0 and 28.7 ms over three runs against this bound
      // at 29.4, 18.8 and 26.6. The twenty above caught it as well on that run,
      // which is the accident rather than the rule — those are the numbers of a
      // machine with five other things on it, and a figure in microseconds
      // holds or fails according to what else is running, while a ratio against
      // the first build of the same frame is taken in the same conditions and
      // means the same thing on any machine.
      expect(change, lessThan(whole ~/ 4));
    });

    test('turning the camera costs nothing on a large mesh', () {
      final overlay = _overlay();
      final builder = MeshOverlayBuilder();
      final selection = Selection.of(ElementLevel.face, <int>[0]);
      final eye = Vector3(0, 3, 0);

      final clock = Stopwatch()..start();
      builder.build(
        overlay,
        mesh: large,
        selection: selection,
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(eye: eye, up: Vector3(0, 0, -1)),
      );
      final whole = clock.elapsedMicroseconds;

      clock.reset();
      final rebuilt = builder.build(
        overlay,
        mesh: large,
        selection: selection,
        meshVersion: 1,
        selectionVersion: 1,
        view: _view(eye: eye, right: Vector3(0, 0, 1), up: Vector3(1, 0, 0)),
      );
      final turn = clock.elapsedMicroseconds;

      // Mutation: rebuild the lines on a turn as well and this is the first
      // build again — a hundred thousand lines re-emitted for a camera the
      // lines do not read, once per frame for as long as somebody holds the
      // mouse down.
      expect(rebuilt, (lines: false, handles: true, fill: false));
      expect(turn, lessThan(20000));
      expect(turn, lessThan(whole ~/ 4));
    });
  });
}
