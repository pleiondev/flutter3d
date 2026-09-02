import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// One batch of level geometry and the box it fills.
typedef VisibilityBatch = ({MeshNode node, Aabb3 bounds});

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
  VisibilityCuller(this.visibility, this.batches);

  final LevelVisibility visibility;
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
      batch.node.visible = show;
      if (!show) hidden++;
    }
    return _hidden = hidden;
  }

  /// Shows every batch again, for a camera that is no longer the player's.
  void showAll() {
    for (final batch in batches) {
      batch.node.visible = true;
    }
    _hidden = 0;
    _cell = -1;
  }
}
