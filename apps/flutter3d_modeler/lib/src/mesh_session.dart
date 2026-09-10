/// One mesh, being edited: what is selected, what an operation does to it, and
/// how far back it can be undone.
///
/// **This is not `ModelProject`, and it is not trying to be.** The plan's
/// document holds objects, materials, skeletons, a profile and a history of
/// commands with the words to describe each one; it is `doc-03` through
/// `doc-07` and it is the step this application is waiting on. What this holds
/// is the one mesh a new project starts as, so that the rail is a set of
/// buttons that do something rather than a set of buttons that will. When the
/// document arrives, everything here becomes a command against it and this file
/// goes away.
///
/// **Undo comes free and is worth having early.** `EditMesh` is journalled: an
/// edit between `beginStep` and `endStep` is one entry, and `undo` puts the
/// arrays back. So every operation here opens a step, and ⌘Z works from the
/// first build — which matters more than it sounds, because a modelling tool
/// people cannot undo in is a modelling tool people will not press anything in.
///
/// **What is refused is said, not swallowed.** Every operation returns the
/// sentence `OpResult` refused with, and the status line shows it. A modeller
/// that answers "extrude with nothing selected" with a silent no-op is a
/// modeller people think is broken.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

/// The tools of the mesh mode that change geometry, by [ModelerTool.id].
///
/// Kept as a set rather than checked with a `switch` at the call site so that
/// the rail can ask whether a tool is armed-and-waiting or acts-at-once, and so
/// that a tool added to the table without a case here is a name in one place
/// that answers `false` rather than a silent no-op.
const Set<String> kImmediateTools = <String>{
  'mesh.extrude',
  'mesh.loopCut',
  'mesh.duplicate',
  'mesh.split',
  'mesh.delete',
};

/// The transform tools, which need a drag before they mean anything.
const Set<String> kDragTools = <String>{
  'mesh.move',
  'mesh.rotate',
  'mesh.scale',
  'object.move',
  'object.rotate',
  'object.scale',
};

/// A mesh with a selection over it and a history behind it.
final class MeshSession {
  MeshSession(this.mesh) : _selection = Selection.empty(ElementLevel.vertex) {
    _rebuild();
  }

  final EditMesh mesh;

  /// What is selected, and the level it is selected at.
  Selection get selection => _selection;
  Selection _selection;

  ElementLevel get level => _selection.level;

  /// Counters the viewport's overlay builder watches. Any two numbers that
  /// differ when the thing they name differs; these count changes.
  int get meshVersion => _meshVersion;
  int _meshVersion = 1;

  int get selectionVersion => _selectionVersion;
  int _selectionVersion = 1;

  /// What a click is tested against. Rebuilt whenever the topology moves,
  /// because a tree built against a mesh that has since been cut answers with
  /// faces that are no longer there.
  MeshPicker get picker => _picker;
  late MeshPicker _picker;

  final MeshLayoutPlan _plan = MeshLayoutPlan();

  /// How far an extrusion goes, and how far a nudge moves, when nobody has said.
  ///
  /// A tenth of the model rather than a fixed number of metres: the same button
  /// is pressed on a cube of one metre and on a scanned head of two hundred,
  /// and a fixed distance is invisible on one and catastrophic on the other.
  double get step => _step;
  double _step = 0.1;

  void _rebuild() {
    _plan.build(mesh);
    _picker = MeshPicker(mesh, MeshBvh(mesh, _plan));
    _step = _spanOf() * 0.1;
  }

  double _spanOf() {
    final low = Vector3.all(double.infinity);
    final high = Vector3.all(double.negativeInfinity);
    final at = Vector3.zero();
    var found = false;
    for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
      if (!mesh.isVertexAlive(vertex)) continue;
      found = true;
      mesh.positionOf(vertex, at);
      Vector3.min(low, at, low);
      Vector3.max(high, at, high);
    }
    // A mesh with nothing in it, or with every vertex in one place. Neither has
    // a span, and a step of zero makes every operation a no-op that reports
    // success — which is worse than a step that is merely wrong.
    if (!found) return 1.0;
    final span = (high - low).length;
    return span == 0.0 ? 1.0 : span;
  }

  /// The geometry to upload. Rebuilt from the plan the picker is built against,
  /// so the triangle a click answers with is a triangle that was drawn.
  MeshData toMeshData() => _plan.toMeshData(mesh);

  /// Replaces the selection.
  ///
  /// [extend] adds to what is there when the level agrees, and replaces when it
  /// does not: shift-clicking a face while vertices are selected is a person
  /// changing their mind about the level, not asking for a selection that is
  /// two things at once.
  void select(Selection picked, {bool extend = false}) {
    // `toggle` rather than `union`, because shift on something already
    // selected is how a person takes one element back out of forty — and a
    // modifier that only ever adds wastes the one gesture that can undo a
    // mis-click.
    _selection = extend && picked.level == _selection.level
        ? _selection.toggle(picked)
        : picked;
    _selectionVersion++;
  }

  /// Switches the level, carrying the selection across.
  ///
  /// Through `convertedTo` rather than cleared, because a person who has
  /// selected a face and presses 1 wants its vertices, not an empty viewport —
  /// which is the whole reason `Selection` knows how to convert.
  void setLevel(ElementLevel to) {
    if (to == _selection.level) return;
    _selection = _selection.convertedTo(mesh, to);
    _selectionVersion++;
  }

  /// Runs the tool [id] against the selection.
  ///
  /// Returns null when it worked and the sentence to show when it did not.
  /// Throws for an id this does not know, because that is a tool table and a
  /// switch that have drifted apart and is a fault rather than a refusal.
  String? run(String id) {
    if (!kImmediateTools.contains(id)) {
      throw ArgumentError('$id is not an operation this session performs');
    }
    mesh.beginStep();
    final OpResult result = switch (id) {
      'mesh.extrude' => extrudeFaces(mesh, _selection, distance: _step),
      'mesh.loopCut' => loopCut(mesh, _selection),
      'mesh.duplicate' => duplicateSelection(mesh, _selection),
      'mesh.split' => splitSelection(mesh, _selection),
      'mesh.delete' => deleteSelection(mesh, _selection),
      _ => throw StateError('unreachable: $id'),
    };
    return _after(result);
  }

  /// Moves, turns or scales the selection by [by], about its own middle.
  ///
  /// One entry point for the three transform tools, because what separates them
  /// is the matrix the viewport builds out of a drag and nothing else — and a
  /// session with three nearly identical methods is a session where two of them
  /// are wrong in ways the third is not.
  String? transformBy(Matrix4 by) {
    mesh.beginStep();
    return _after(transformSelection(mesh, _selection, by: by));
  }

  /// Closes the step, keeps the selection the operation left, and rebuilds
  /// whatever the operation invalidated.
  String? _after(OpResult result) {
    if (!result.ok) {
      // **The `if` is the whole of it, and getting it wrong is worse than not
      // having it.** `endStep` discards a step that wrote nothing and says so,
      // so an unconditional `undo` here would take back the *previous* edit —
      // press extrude with nothing selected and the loop cut before it
      // silently comes out. What is left is the other case: an operation that
      // wrote something and then refused, which several of them do, and whose
      // half-made geometry has to go.
      if (mesh.endStep()) mesh.undo();
      return result.reason;
    }
    mesh.endStep();
    _selection = result.selection;
    _selectionVersion++;
    _meshVersion++;
    if (result.topologyChanged) {
      _rebuild();
    } else {
      _picker.bvh.refit(mesh);
    }
    return null;
  }

  /// One step back. False when there is nothing to go back to.
  bool undo() => _stepped(mesh.undo());

  /// One step forward.
  bool redo() => _stepped(mesh.redo());

  bool _stepped(bool moved) {
    if (!moved) return false;
    // Everything, because an undo can put back a topology as easily as a
    // position and the journal does not say which. Rebuilding is a pass over
    // the mesh; getting it wrong is a picker answering with faces that are not
    // there.
    _rebuild();
    _meshVersion++;
    // The selection may name elements the undone step created. Converting it to
    // its own level drops whatever is no longer alive, which is the cheapest
    // honest answer — the plan's history carries the selection with each step,
    // and that is `doc-04`.
    _selection = _selection.convertedTo(mesh, _selection.level);
    _selectionVersion++;
    return true;
  }
}
