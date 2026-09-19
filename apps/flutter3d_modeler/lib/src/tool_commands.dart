/// Which command a rail button stands for.
///
/// **Pulled out of `main.dart` for the reason `transform_dispatch.dart` was.**
/// `_ranTool` needs a widget to press the button on; the question it asks
/// once pressed — which [ModelCommand] this id becomes, given what is
/// selected and what mesh is being edited — is arithmetic checkable without
/// one.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// The command a rail button stands for, or null when it only arms.
///
/// **One switch in one place, which is what the tool table was built to
/// allow.** A callback on each row of that table would put this decision in
/// as many places as there are tools, and a tool added without one would be a
/// button that silently did nothing.
///
/// [activeObject] is `_history.selection.activeObject`; [editMesh] is the
/// mesh being edited, when what is selected has one — only read for
/// `mesh.extrude` and `mesh.bevel`, and only evaluated then, since a
/// `switch` expression never runs a branch it does not take.
ModelCommand? commandFor(
  String id, {
  required int? activeObject,
  required EditMesh? editMesh,
}) => switch (id) {
  'object.add' => const AddPrimitive(kind: 'box'),
  'object.duplicate' => const DuplicateObjects(),
  'object.delete' => const DeleteObjects(),
  'object.bake' => switch (activeObject) {
    final int selected => BakeToMesh(selected),
    _ => null,
  },
  'object.origin' => switch (activeObject) {
    final int selected => SetOrigin(
      id: selected,
      to: OriginPlacement.boundsBottom,
    ),
    _ => null,
  },
  'object.apply' => switch (activeObject) {
    final int selected => ApplyTransform(selected),
    _ => null,
  },
  'mesh.extrude' => Extrude(stepOf(editMesh)),
  'mesh.loopCut' => const LoopCut(),
  'mesh.bevel' => BevelEdges(stepOf(editMesh) * 0.5),
  // `ux-39`: the game-ready minimum this file's own header used to say
  // was deliberately left out — panels, joining pieces, moving loops.
  'mesh.inset' => InsetFaces(stepOf(editMesh) * 0.5),
  'mesh.bridge' => const BridgeLoops(),
  'mesh.slide' => const SlideEdges(0.25),
  'mesh.triangulate' => const Triangulate(),
  'mesh.separate' => const Separate(),
  'mesh.dissolve' => const DissolveEdges(),
  'mesh.merge' => const MergeByDistance(),
  // `ux-16`.
  'mesh.fillHoles' => const FillHoles(),
  'mesh.normals' => const RecalculateNormals(),
  'mesh.flip' => const RecalculateNormals(flip: true),
  'mesh.delete' => const DeleteElements(),
  // `pro-uv-07`: one command both ways round, which is `MarkSeam.on`'s own
  // doc comment — "a caller choosing between a mark and a clear is choosing
  // this, not two different commands". `uv.unwrap` and `uv.pack` are not
  // here: each reads a margin off the panel, and this function is handed
  // what is selected and nothing else. `uv_wiring.dart` answers both.
  'uv.markSeam' => const MarkSeam(),
  'uv.clearSeam' => const MarkSeam(on: false),
  _ => null,
};

/// How far an extrusion goes when nobody has said.
///
/// A tenth of the model rather than a fixed number of metres: the same button
/// is pressed on a cube of one metre and on a scanned head of two hundred,
/// and a fixed distance is invisible on one and catastrophic on the other.
double stepOf(EditMesh? mesh) {
  if (mesh == null) return 0.1;
  final low = vm.Vector3.all(double.infinity);
  final high = vm.Vector3.all(double.negativeInfinity);
  final at = vm.Vector3.zero();
  var found = false;
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (!mesh.isVertexAlive(vertex)) continue;
    found = true;
    mesh.positionOf(vertex, at);
    vm.Vector3.min(low, at, low);
    vm.Vector3.max(high, at, high);
  }
  if (!found) return 0.1;
  final span = (high - low).length;
  return span == 0.0 ? 0.1 : span * 0.1;
}
