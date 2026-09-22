/// The picker over the mesh currently being edited, rebuilt only when its
/// version moves.
///
/// **A cache, not a recomputed getter**, for the reason `view-26n`'s
/// `MeshBvh` exists at all: building one is a real cost, and a picker read on
/// every frame a mesh is merely being looked at — not edited — would pay that
/// cost for nothing.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

/// Holds one [MeshPicker], built fresh whenever the version it was built
/// against stops matching the one asked for.
class ElementPickerCache {
  MeshPicker? _picker;
  int _pickerVersion = -1;

  /// The picker over [mesh] at [version] — the cached one if [version]
  /// still matches, a freshly built one otherwise.
  MeshPicker pickerFor(EditMesh mesh, int version) {
    if (_picker == null || _pickerVersion != version) {
      final plan = MeshLayoutPlan()..build(mesh);
      _picker = MeshPicker(mesh, MeshBvh(mesh, plan));
      _pickerVersion = version;
    }
    return _picker!;
  }

  /// Drops the cached picker, so the next [pickerFor] rebuilds from scratch
  /// regardless of what version it is asked for.
  void forget() {
    _picker = null;
    _pickerVersion = -1;
  }
}
