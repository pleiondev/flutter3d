/// An editable mesh: half-edge topology over persistent typed arrays.
///
/// **What this is for, and what it is not.** `flutter3d_geometry` describes a
/// mesh that is finished — vertices in the order a GPU wants them, indices into
/// them, nothing to say which edges met at a corner. That is the right shape
/// for drawing and the wrong one for editing: extruding a face, cutting a loop
/// or dissolving an edge are all questions about what is next to what, and the
/// answer has been thrown away by the time a `MeshData` exists.
///
/// So this package holds the other representation — faces of any valency,
/// half-edges that know their twin, attributes on vertices, corners, edges and
/// faces — and converts in both directions. A modeller edits this and hands the
/// engine the result.
///
/// Plain Dart, deliberately: the document an agent's tool opens, a bench
/// compiles ahead of time, and a test of a loop cut has nothing to draw.
library;

export 'src/edit_mesh.dart';
