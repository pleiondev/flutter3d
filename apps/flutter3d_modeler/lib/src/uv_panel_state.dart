/// What the UV mode remembers between builds — `pro-uv-07`'s own wiring
/// half, the same move [RetopoPanelState] and its two neighbours make in
/// `pro_panel_state.dart` and for the same reason: an `extension` on the
/// screen's state cannot declare a field, so what `uv_wiring.dart` holds has
/// to live in an object the class body owns.
///
/// None of it is on `ModelHistory`. The method, the margin and which island
/// is lit are what a panel is showing, not what the document says, so undo
/// has nowhere to put any of them back to — what undo takes back is the
/// `UnwrapCommand` they were read into.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'uv_seam_overlay.dart';
import 'uv_unwrap_layout.dart';

/// Every method this build can unwrap with. One today; a list so that the
/// panel's own segmented button is fed from here rather than from a literal
/// at the call site — `UvUnwrapPanel.methods`' own doc comment says why.
const List<UnwrapMethod> kUnwrapMethods = <UnwrapMethod>[UnwrapMethod.lscm];

/// What one mesh's unwrap looks like, read once per version of the mesh.
typedef UvReading = ({
  /// The islands, as `UvLayoutView` and `UvUnwrapPanel` both draw them.
  /// Empty for a mesh with no UV layer, or with one that covers nothing:
  /// `EditMesh.uvOf` answers zero for every corner of either, and a list of
  /// islands all collapsed onto the origin would say the mesh is unwrapped
  /// when it is not.
  List<UvIslandData> islands,

  /// One half-edge per seam — [uvSeamEdges]' own answer, kept so the
  /// viewport draws the seams every frame without walking the mesh for them
  /// every frame.
  List<int> seams,

  /// How much of the unit square the islands cover, from nought to one —
  /// screen 06's own status line.
  double fill,
});

/// The reading for a mesh with nothing to read.
const UvReading kNoUvReading = (
  islands: <UvIslandData>[],
  seams: <int>[],
  fill: 0,
);

/// `pro-uv-07`: the panel's three settings, the lit island, and the last
/// reading of the mesh.
final class UvPanelState {
  UnwrapMethod method = UnwrapMethod.lscm;

  /// [UnwrapCommand.margin]'s own default, so a person who never touches the
  /// field gets what an agent calling `unwrap` with no arguments gets.
  double margin = 0.01;

  /// [UnwrapCommand.autoPack]'s own default, for the same reason.
  bool autoPack = true;

  /// Which island is lit, in the layout and in the list alike. One field, so
  /// the two cannot disagree — `UvScreen.onIslandSelected`'s own rule,
  /// carried one level up.
  int? selectedIsland;

  EditMesh? _readFrom;
  int? _readAtVersion;
  UvReading _reading = kNoUvReading;

  /// [mesh]'s islands, seams and fill, recomputed only when [version] — the
  /// owning object's own `ModelObject.version` — has moved or the mesh is a
  /// different one.
  ///
  /// **Cached, because the screen rebuilds on every tick.** `splitIslands`
  /// and `stretchOf` each walk the whole mesh; sixty walks a second of a
  /// fifty-thousand-face model to draw a picture that changed when a command
  /// landed is the cost `MeshOverlayBuilder` already exists to avoid for the
  /// wireframe, avoided the same way here.
  ///
  /// A reading taken for a different mesh or version also drops
  /// [selectedIsland]: island ids are positions in `splitIslands`' own list,
  /// and a seam marked since then renumbers them.
  UvReading readingOf(EditMesh? mesh, int version) {
    if (mesh == null) {
      _readFrom = null;
      _readAtVersion = null;
      selectedIsland = null;
      return _reading = kNoUvReading;
    }
    if (identical(mesh, _readFrom) && version == _readAtVersion) {
      return _reading;
    }
    _readFrom = mesh;
    _readAtVersion = version;
    selectedIsland = null;
    final List<UvIslandData> read =
        mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0)
        ? buildUvIslandData(mesh, splitIslands(mesh))
        : const <UvIslandData>[];
    final double fill = uvFillOf(read);
    return _reading = (
      // **Covering nothing is having no unwrap, layer or no layer.** Undoing
      // an unwrap puts every corner's UV back to zero and leaves the layer
      // the unwrap created standing — the mesh journal rolls back values,
      // not which attributes exist — so "has a UV layer" says yes about a
      // mesh that is exactly as unwrapped as it was before anybody pressed
      // the button. `uv_mode_test.dart` is what found it: the island list
      // survived an undo.
      //
      // A millionth of the square rather than exactly nought: `lscm` lays a
      // closed, uncut surface out along a line, and a line solved in floats
      // is a sliver a few ulps wide.
      islands: fill > 1e-6 ? read : const <UvIslandData>[],
      seams: uvSeamEdges(mesh),
      fill: fill,
    );
  }
}
