import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// One batch of level geometry and the box it fills.
///
/// A class rather than a record, so a batch can later say more (the cell it
/// belongs to) without breaking a caller.
final class VisibilityBatch {
  /// A batch drawn by [node] inside [bounds].
  const VisibilityBatch({required this.node, required this.bounds});

  /// The node to show or hide.
  final MeshNode node;

  /// The box it fills, in world space.
  final Aabb3 bounds;
}

/// Hides the level's batches a camera cannot see, once a frame.
///
/// The runtime half of [LevelVisibility]: the table says which cells see
/// which, this says which batches touch a visible cell and turns the rest
/// off. Off rather than removed — `visible = false` keeps a node out of the
/// render list and the shadow passes alike, at no cost to the scene graph.
///
/// **Frustum culling still runs after this**, and the two answer different
/// questions: the frustum knows where the camera points, the table knows
/// what the walls hide. A room behind the camera is culled by the first; a
/// room behind a wall in front of the camera is culled by the second, and
/// nothing else would have caught it.
final class VisibilityCuller {
  /// A culler reading [visibility] to show or hide [batches]; nothing is
  /// hidden until the first [apply].
  VisibilityCuller(this.visibility, this.batches);

  /// The baked table: which cells see which.
  final LevelVisibility visibility;

  /// The batches shown and hidden, each by its box.
  final List<VisibilityBatch> batches;

  /// How many batches the last [apply] turned off.
  int get hidden => _hidden;
  int _hidden = 0;

  /// The cell the last [apply] found the eye in, or -1 for none.
  int get cell => _cell;
  int _cell = -1;

  /// Shows the batches [eye] can see and hides the rest.
  ///
  /// An eye in no cell — outside the grid, inside a wall — sees everything,
  /// which is the table's own rule and the safe way round.
  int apply(Vector3 eye) {
    _cell = visibility.cellAt(eye);
    var hidden = 0;
    for (var i = 0; i < batches.length; i++) {
      final batch = batches[i];
      final show = visibility.canSeeFrom(eye, batch.bounds);
      batch.node.isVisible = show;
      if (!show) hidden++;
    }
    return _hidden = hidden;
  }

  /// Shows every batch again, for a camera that is no longer the player's.
  void showAll() {
    for (final batch in batches) {
      batch.node.isVisible = true;
    }
    _hidden = 0;
    _cell = -1;
  }
}
