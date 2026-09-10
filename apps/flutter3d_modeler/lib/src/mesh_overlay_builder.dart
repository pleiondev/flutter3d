/// Filling a [MeshOverlay] from the mesh being edited and what is selected.
///
/// **The overlay knows how to draw a line and nothing about a mesh.**
/// `MeshOverlay` takes points and colours; deciding which points — every edge
/// once rather than every half-edge twice, the corners of a selected face, a
/// handle per vertex — is a question about topology, and the engine has no
/// business holding the answer for a modeller. So the decision lives in the
/// application and the drawing lives in the package, which is also what lets
/// this file be tested with no device anywhere near it.
///
/// **What it costs is the whole design.** A wireframe is rebuilt on the CPU
/// into one buffer, and on a mesh a person is actually working on that buffer
/// is millions of floats. Doing it once per frame is a frame budget spent on
/// numbers that did not change, so everything here is arranged around two
/// questions: what actually changed since the last frame, and how much of a
/// large mesh is worth drawing at all. [MeshOverlayBuilder] answers the first
/// with versions its caller drives and the second with a budget.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

/// Where the overlay is being looked at from, as [MeshOverlay.lookFrom] wants
/// it.
///
/// **A value, so the builder can compare it with the last one.** The camera is
/// six numbers and a flag, and comparing them costs nothing — which is the
/// reason the camera needs no version from the caller while the mesh does.
/// Keeping the same numbers in a mutable camera object and asking it whether it
/// moved would put that comparison somewhere else and give the builder no way
/// to tell a turn from a move, which is exactly the distinction that decides
/// how much work a frame does.
///
/// The vectors are held rather than copied, so a caller that keeps one of these
/// and writes new numbers into its [eye] has handed the builder a camera that
/// compares equal to itself and a wireframe that stops following the view. Make
/// a new one per frame; they cost three small objects.
final class MeshOverlayView {
  MeshOverlayView({
    required this.eye,
    required this.right,
    required this.up,
    required this.pixel,
    this.perspective = true,
  });

  /// Where the camera is, in the same space the mesh's positions are in.
  final Vector3 eye;

  /// The camera's screen-right and screen-up axes, which is what a vertex
  /// handle is squared up against. A ribbon uses them only as a fallback, and
  /// takes its band from the eye instead.
  final Vector3 right;
  final Vector3 up;

  /// The world size of one logical pixel, as [MeshOverlay.lookFrom] defines it.
  final double pixel;

  final bool perspective;

  /// Whether [other] points the same way. Compared exactly, and on purpose:
  /// these are the numbers the caller handed over rather than the result of an
  /// arithmetic that might land a bit apart twice, so an exact comparison is
  /// false only when the camera really turned.
  bool facesAs(MeshOverlayView other) => right == other.right && up == other.up;

  /// Whether [other] is looking from the same place. Exact for the reason
  /// [facesAs] is exact, and with no tolerance for a second reason: a handle is
  /// sized by its distance to the eye and a ribbon is turned by the direction
  /// to it, so a camera that has moved at all is a camera the handles on screen
  /// were drawn for wrongly.
  bool sitsAt(MeshOverlayView other) => eye == other.eye;
}

/// The colours the overlay is drawn in.
///
/// **Not white, and that is the only interesting thing here.** A wireframe at
/// full brightness competes with the lit surface underneath it, and after an
/// hour a person is reading the wireframe instead of the model; a wireframe
/// darker than the surface disappears into the shadowed side. A middle grey
/// sits on both. The selected colour is warm because everything the renderer
/// puts under it — a lit grey model on a near-black background — is not.
final class MeshOverlayColours {
  MeshOverlayColours({Vector4? wire, Vector4? vertex, Vector4? selected})
    : wire = wire ?? Vector4(0.55, 0.58, 0.60, 1.0),
      vertex = vertex ?? Vector4(0.72, 0.76, 0.78, 1.0),
      selected = selected ?? Vector4(1.0, 0.60, 0.15, 1.0);

  /// Every edge of the mesh, drawn as a line.
  final Vector4 wire;

  /// An unselected vertex handle, at vertex level.
  final Vector4 vertex;

  /// A selected element, whatever it is drawn as.
  final Vector4 selected;
}

/// Which of the three batches a call to [MeshOverlayBuilder.build] refilled.
///
/// Returned rather than kept private because it is the only way a caller — or a
/// test — can tell a frame that did nothing from a frame that rebuilt a hundred
/// thousand lines. Both take about the same time to *say*, and a regression
/// that rebuilds everything every frame shows up as a profile nobody reads
/// until the mesh is large.
typedef MeshOverlayRebuild = ({bool lines, bool handles, bool fill});

/// Fills the three batches of a [MeshOverlay] from an [EditMesh] and a
/// [Selection].
///
/// **What goes where.** Every edge of the mesh is a line, so the shape reads
/// even where nothing is selected. The selection is drawn at its own level and
/// only there: selected vertices are handles at vertex level, selected edges
/// are ribbons at edge level, and a selected face is a wash with its own edges
/// as ribbons round it. Converting the selection to the other two levels on
/// every build — so that selecting a face also lit its corners — is the obvious
/// alternative, and it is both slower and wrong: [Selection.convertedTo] walks the
/// whole mesh to answer a question about a handful of elements, and lighting up
/// vertices at face level tells a person they have selected something they
/// cannot move.
///
/// **Rebuild only what changed.** The caller passes a version for the mesh and
/// a version for the selection, and the builder compares the camera itself:
///
///   * the lines are the mesh's own positions with the depth nudge on top, so a
///     selection that changed costs nothing at all and the camera reaches them
///     only through that nudge;
///   * the handles are drawn at a size in pixels and turned to face the camera
///     — [MeshOverlay.point] squares its quad against `right` and `up`, and
///     [MeshOverlay.ribbon] takes its width from the distance to the eye and
///     its band from the direction to it — so a camera that turns *or* one that
///     moves invalidates them, and only them;
///   * the wash lies flat on its face, so the camera reaches it through the
///     nudge and nothing else.
///
/// **The camera is compared exactly and the nudge is compared loosely, and
/// those are two different questions.** A handle a frame behind the eye is
/// drawn at the wrong size and, if it is a ribbon, turned towards where the
/// camera used to be until it is edge-on; there is no tolerance there to spend,
/// so any move at all rebuilds the handles. The lines and the wash are the
/// mesh's own geometry and the camera reaches them only through the depth
/// nudge, which is what [biasDrift] is a tolerance for. One test for all three
/// batches goes wrong whichever of the two it is: the exact comparison rebuilds
/// a two-hundred-thousand-edge wireframe for a dolly of a hand's width, which
/// is the cost this class exists to refuse, and the drift test leaves the
/// handles a frame behind the camera on every move and — with
/// [MeshOverlay.biasPixels] turned off, as a caller offsetting depth in the
/// pipeline would have it — leaves them behind for good, because a nudge of
/// length zero cannot drift. The highlight would then keep the width and the
/// twist the camera gave it when it was first built for the rest of the
/// session. That was the shape this had, and it is what the test called `an eye
/// that moves rebuilds the handles with the bias switched off` was written
/// against.
///
/// **Why the mesh has to be told rather than asked.** There is no revision
/// number to read. [EditMesh.undoDepth] is the nearest thing and it is not one:
/// it counts steps on the undo stack, so it goes *down* when somebody presses
/// undo — the mesh changes and the number falls back to one it has already had
/// — it does not move at all for an edit made outside a step, and
/// `clearJournal` puts it back to zero with the mesh untouched. An overlay
/// driven by it would show the mesh from before the undo. Comparing the arrays
/// instead is the walk over the whole mesh that this class exists to avoid, and
/// hashing them is that walk plus arithmetic. So the caller, which is the thing
/// that ran the operation, says when it ran one.
///
/// **Above [edgeBudget] edges the wireframe is thinned.** Two hundred thousand
/// edges on a screen a thousand pixels across is several edges per pixel: the
/// model reads as grey mud, the silhouette is the only thing left of the shape,
/// and it costs a megabyte and a half of vertices to say nothing. So above the
/// budget only some of the edges are drawn, spread evenly through the mesh by a
/// counter rather than chosen at random — the same edges every rebuild, because
/// a wireframe whose edges change between frames of a drag is a wireframe that
/// crawls. The rejected alternative was drawing the selection and its
/// neighbourhood only, which is cheaper still and loses the thing the wireframe
/// is for: a person looks at the far side of the model to decide where to move
/// next, and a wireframe that exists only where they have already clicked
/// cannot be looked at. Thinning keeps the density of the whole model honest
/// everywhere and merely coarser.
///
/// **The selection is never thinned.** The wireframe is context and dropping
/// some of it is a legibility trade; the highlight is the answer to "what have
/// I got", and a highlight that skips every second edge is a lie about the
/// document. Somebody who selects two hundred thousand edges pays for two
/// hundred thousand ribbons.
///
/// **The overlay handed in belongs to the builder.** It clears batches one at a
/// time rather than through [MeshOverlay.clear], so anything else that drew
/// into the same overlay — a grid, a gizmo — would be wiped on some frames and
/// not others. Give those their own overlay.
final class MeshOverlayBuilder {
  MeshOverlayBuilder({
    MeshOverlayColours? colours,
    this.edgeBudget = 100000,
    this.biasDrift = 0.25,
  }) : colours = colours ?? MeshOverlayColours() {
    if (edgeBudget < 1) {
      throw ArgumentError.value(
        edgeBudget,
        'edgeBudget',
        'needs to be at least one element',
      );
    }
  }

  final MeshOverlayColours colours;

  /// How many edges — and, at vertex level, how many handles — are worth
  /// drawing. Everything above this is thinned down to it.
  final int edgeBudget;

  /// How far the depth bias may go wrong before the lines are rebuilt for it.
  ///
  /// **The one number in here that is a judgement.** [MeshOverlay] nudges every
  /// vertex it is given towards the eye that was set when it was given, which
  /// is what keeps an edge off the surface it belongs to; a camera that has
  /// moved since leaves that nudge pointing somewhere slightly wrong. Rebuilding
  /// the lines for it every time the eye moves at all would mean an orbit
  /// rebuilds the wireframe every frame, which is the cost this class exists to
  /// refuse. Letting it go wrong without limit ends with the nudge pointing
  /// sideways, contributing no depth, and the wireframe fighting the surface.
  /// A quarter of the nudge's own length is a little over fourteen degrees of
  /// drift, at which the nudge still keeps some ninety-seven per cent of its
  /// depth — invisible — and an orbit rebuilds the lines once every dozen or so
  /// frames instead of every one.
  final double biasDrift;

  int _meshVersion = 0;
  int _selectionVersion = 0;
  ElementLevel? _level;
  MeshOverlayView? _view;

  /// A point in the middle of the mesh, and the nudge that was applied there
  /// when the lines were last built. Together they are how [biasDrift] is
  /// measured: the middle is where a mesh's error is typical rather than
  /// extreme, and the nudge carries the eye, the pixel scale and the projection
  /// in one vector, so one comparison covers moving, zooming and switching to
  /// an orthographic camera.
  final Vector3 _pivot = Vector3.zero();
  Vector3? _builtNudge;

  /// Scratch, so a rebuild of a large mesh allocates nothing per edge.
  final Vector3 _from = Vector3.zero();
  final Vector3 _to = Vector3.zero();
  final FaceTriangulator _triangulator = FaceTriangulator();
  List<Vector3> _corners = <Vector3>[];

  /// Refills whichever of the three batches is out of date, and says which.
  ///
  /// [meshVersion] and [selectionVersion] are the caller's own counters: any two
  /// numbers that differ when the thing they name differs. The mesh's version
  /// has to change for an edit *and* for an undo or a redo, which is the case a
  /// counter that only counts edits gets wrong.
  MeshOverlayRebuild build(
    MeshOverlay overlay, {
    required EditMesh mesh,
    required Selection selection,
    required int meshVersion,
    required int selectionVersion,
    required MeshOverlayView view,
  }) {
    // Set before anything is measured: the drift below asks the overlay what a
    // nudge would be *now*, and the answer is the camera it is holding.
    overlay.lookFrom(
      eye: view.eye,
      right: view.right,
      up: view.up,
      pixel: view.pixel,
      perspective: view.perspective,
    );

    final last = _view;
    final first = last == null;
    final meshChanged = first || meshVersion != _meshVersion;
    final selectionChanged =
        first ||
        selectionVersion != _selectionVersion ||
        selection.level != _level;
    final turned = first || !view.facesAs(last);
    final moved = first || !view.sitsAt(last);
    final biasStale = first || _biasDrifted(overlay, view.eye);

    final rebuildLines = meshChanged || biasStale;
    final rebuildFill = meshChanged || selectionChanged || biasStale;
    final rebuildHandles = rebuildFill || turned || moved;

    if (rebuildLines) {
      overlay.lines.clear();
      _centreOf(mesh, _pivot);
      _emitLines(overlay, mesh);
      _builtNudge = _nudgeAt(overlay, _pivot, view.eye);
    }
    if (rebuildHandles) {
      overlay.handles.clear();
      _emitHandles(overlay, mesh, selection);
    }
    if (rebuildFill) {
      overlay.fill.clear();
      _emitFill(overlay, mesh, selection);
    }

    _meshVersion = meshVersion;
    _selectionVersion = selectionVersion;
    _level = selection.level;
    _view = view;
    return (lines: rebuildLines, handles: rebuildHandles, fill: rebuildFill);
  }

  /// Whether the depth bias baked into the lines has gone further wrong than
  /// [biasDrift] allows.
  ///
  /// **This repeats [MeshOverlay]'s own arithmetic, and there is no way round
  /// it.** The nudge is applied inside the overlay, per vertex, and nothing
  /// comes back out; measuring the drift means working out what the overlay
  /// would do now and comparing it with what it did then.
  /// [MeshOverlay.worldSize] and [MeshOverlay.biasPixels] are public, so the two
  /// agree by construction as long as the overlay keeps nudging along the line
  /// to the eye — and if it ever stops, this is the second place to change.
  bool _biasDrifted(MeshOverlay overlay, Vector3 eye) {
    final was = _builtNudge!;
    final now = _nudgeAt(overlay, _pivot, eye);
    final length = was.length;
    // A mesh with nothing in it, an eye exactly on the pivot, or a caller that
    // has turned [MeshOverlay.biasPixels] off in favour of a depth offset in
    // the pipeline: there is no nudge to be wrong, so no camera can spoil the
    // lines, and the answer stays false for as long as the bias is off. That is
    // right for the lines and it used to be a hole for the handles, which were
    // rebuilt off the back of this test and so froze at the camera they were
    // first drawn for; they are rebuilt off the eye itself now.
    if (length == 0) return now.length != 0;
    return (now - was).length > biasDrift * length;
  }

  Vector3 _nudgeAt(MeshOverlay overlay, Vector3 at, Vector3 eye) {
    final away = eye - at;
    final distance = away.length;
    if (distance == 0) return Vector3.zero();
    return away * (overlay.worldSize(overlay.biasPixels, at) / distance);
  }

  /// The middle of the box the live vertices sit in, written into [out].
  ///
  /// The centre of the bounds rather than the average of the positions: an
  /// average is dragged about by wherever the mesh happens to have most of its
  /// vertices — a sphere with a dense pole is not centred on its pole — and
  /// what this is for is "roughly where the model is, from the camera's point
  /// of view".
  void _centreOf(EditMesh mesh, Vector3 out) {
    final positions = mesh.positions;
    var lowX = double.infinity, lowY = double.infinity, lowZ = double.infinity;
    var highX = -double.infinity,
        highY = -double.infinity,
        highZ = -double.infinity;
    for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
      // A tombstone keeps whatever position it had; taking it into the bounds
      // would put the pivot somewhere the model no longer is.
      if (!mesh.isVertexAlive(vertex)) continue;
      final at = vertex * 3;
      final x = positions[at], y = positions[at + 1], z = positions[at + 2];
      if (x < lowX) lowX = x;
      if (y < lowY) lowY = y;
      if (z < lowZ) lowZ = z;
      if (x > highX) highX = x;
      if (y > highY) highY = y;
      if (z > highZ) highZ = z;
    }
    if (lowX > highX) {
      out.setZero();
      return;
    }
    out.setValues((lowX + highX) / 2, (lowY + highY) / 2, (lowZ + highZ) / 2);
  }

  /// Every edge once, thinned to [edgeBudget].
  ///
  /// The walk is over faces because that is the only way into the half-edges,
  /// and an edge is drawn by the one of its two half-edges [EditMesh.edgeOf]
  /// picked — which is what stops a closed mesh drawing its whole wireframe
  /// twice, at double the cost and with every line blended over itself.
  ///
  /// **It passes the mesh twice, and in a class about not walking the mesh that
  /// is worth saying out loud.** [EditMesh.edgeCount] is a walk of its own
  /// rather than a stored number, and the thinning has to know the total before
  /// it can decide about the first edge, so counting on the way past is not
  /// available. It is a constant factor inside a pass that is already the size
  /// of the mesh, and the thing bought with it is that the budget is met
  /// exactly rather than approached.
  void _emitLines(MeshOverlay overlay, EditMesh mesh) {
    final thinning = _Thinning(mesh.edgeCount, edgeBudget);
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      mesh.forEachHalfEdge(face, (int half) {
        if (mesh.edgeOf(half) != half) return;
        if (!thinning.take()) return;
        mesh.positionOf(mesh.originOf(half), _from);
        mesh.positionOf(mesh.originOf(mesh.nextOf(half)), _to);
        overlay.edge(_from, _to, colours.wire);
      });
    }
  }

  /// The selection, drawn at its own level.
  void _emitHandles(MeshOverlay overlay, EditMesh mesh, Selection selection) {
    switch (selection.level) {
      case ElementLevel.vertex:
        // Every vertex, not only the selected ones: vertex level is where a
        // person grabs a corner, and a corner they cannot see is a corner they
        // cannot aim at. That is also what makes this the expensive level and
        // the reason the budget applies here too.
        final thinning = _Thinning(mesh.vertexCount, edgeBudget);
        for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
          if (!mesh.isVertexAlive(vertex)) continue;
          final picked = selection.contains(vertex);
          // Asked whatever the answer is, so the counter stays in step with the
          // vertices rather than with the unselected ones.
          final kept = thinning.take();
          if (!picked && !kept) continue;
          mesh.positionOf(vertex, _from);
          overlay.point(_from, picked ? colours.selected : colours.vertex);
        }
      case ElementLevel.edge:
        for (final half in selection.ids) {
          if (!_edgeIsAlive(mesh, half)) continue;
          mesh.positionOf(mesh.originOf(half), _from);
          mesh.positionOf(mesh.originOf(mesh.nextOf(half)), _to);
          overlay.ribbon(_from, _to, colours.selected);
        }
      case ElementLevel.face:
        // Every edge of every selected face, each drawn once: two selected
        // faces share an edge, and drawing it twice is a ribbon at double
        // opacity along one arbitrary seam of the region.
        final drawn = <int>{};
        for (final face in selection.ids) {
          if (!_faceIsAlive(mesh, face)) continue;
          mesh.forEachHalfEdge(face, (int half) {
            if (!drawn.add(mesh.edgeOf(half))) return;
            mesh.positionOf(mesh.originOf(half), _from);
            mesh.positionOf(mesh.originOf(mesh.nextOf(half)), _to);
            overlay.ribbon(_from, _to, colours.selected);
          });
        }
    }
  }

  /// A wash over each selected face, and nothing at the other two levels.
  void _emitFill(MeshOverlay overlay, EditMesh mesh, Selection selection) {
    if (selection.level != ElementLevel.face) return;
    for (final face in selection.ids) {
      if (!_faceIsAlive(mesh, face)) continue;
      final outline = _outlineOf(mesh, face);
      // Through the mesh package's own triangulator rather than a fan from the
      // first corner. A fan covers the notch of a concave face, so the wash
      // would claim a piece of the model that is not part of the face — and the
      // person would be looking at a highlight that disagrees with what a
      // raycast, an area and an exporter all say the face is.
      _triangulator.triangulate(outline, (int a, int b, int c) {
        overlay.wash(outline[a], outline[b], outline[c], colours.selected);
      });
    }
  }

  /// The corners of [face], in a list reused between faces of the same size.
  ///
  /// A fresh list per face is an allocation per selected face per rebuild,
  /// which on a selection somebody is dragging a box over is thousands a frame.
  /// A mesh of mixed valencies still reallocates when the size changes; a mesh
  /// of quads, which is what a modeller mostly holds, allocates once.
  List<Vector3> _outlineOf(EditMesh mesh, int face) {
    final valency = mesh.valencyOf(face);
    if (_corners.length != valency) {
      _corners = List<Vector3>.generate(valency, (_) => Vector3.zero());
    }
    var at = 0;
    mesh.forEachVertex(face, (int vertex) {
      mesh.positionOf(vertex, _corners[at]);
      at++;
    });
    return _corners;
  }

  /// Whether a face named by a selection is still there.
  ///
  /// **A selection outlives the elements it names.** Deleting a face leaves the
  /// number in whatever selection was made before it, and an overlay that
  /// walked a dead face's loop would read a tombstone's half-edges — which are
  /// still whatever they were, so the wash would be drawn over a face that is
  /// not in the model any more.
  bool _faceIsAlive(EditMesh mesh, int face) =>
      face >= 0 && face < mesh.faceSlotCount && mesh.isFaceAlive(face);

  /// Whether an edge named by a selection is still there. An edge is a
  /// half-edge, and a half-edge dies with its face.
  bool _edgeIsAlive(EditMesh mesh, int half) {
    if (half < 0 || half >= mesh.halfEdgeSlotCount) return false;
    final face = mesh.faceOf(half);
    return face != EditMesh.none && mesh.isFaceAlive(face);
  }
}

/// Keeps a budget's worth of a larger number of elements, spread evenly.
///
/// **A running counter rather than "every n-th".** A stride has to be a whole
/// number, so two hundred thousand edges into a budget of a hundred thousand
/// rounds to every third edge and throws away a third of the budget; the
/// counter keeps exactly the budget. It is also, unlike a random sample, the
/// same set every time it is run over the same mesh — which is what stops the
/// wireframe crawling while somebody drags.
final class _Thinning {
  _Thinning(this.total, this.budget);

  final int total;
  final int budget;
  int _credit = 0;

  bool take() {
    // A short circuit and nothing else: with a budget at least the size of the
    // total the counter below keeps everything anyway, so no test can tell this
    // line from its absence. It is here because a mesh under the budget is the
    // ordinary case, and this saves it an add, a compare and a subtract per
    // edge.
    if (total <= budget) return true;
    _credit += budget;
    if (_credit < total) return false;
    _credit -= total;
    return true;
  }
}
