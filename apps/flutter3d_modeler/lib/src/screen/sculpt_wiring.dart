/// `_ModelerScreenState`'s own `pro-sc-08` half: the sculpting brush's
/// pointer wiring, its four plain settings, and the Subdivide button — see
/// `sculpt_session.dart` for the transaction/`SculptStroke` half and
/// `ui/sculpt_panel.dart` for the layout.
///
/// **A `part of 'main.dart'`, not a file of its own**, for the reason every
/// file in this directory is: every method here reaches `_cubit`, `_history`,
/// `_state` or `setState` directly.
// ignore_for_file: invalid_use_of_protected_member
part of 'modeler_screen.dart';

extension _SculptWiring on _ModelerScreenState {
  /// `ModelerViewport.onStroke`, wired only while a sculpting brush is armed
  /// — see `ready_parts.dart`'s own `strokeTool`/`onStroke`.
  void _onSculptStroke(StrokeEvent event) {
    final state = _state;
    if (state is! ModelerReady) return;
    final int? objectId = state.selection.activeObject;
    if (objectId == null) return;
    final BrushKind kind = brushKindOf(state.tool);

    switch (event.phase) {
      case StrokePhase.start:
        // `pro-sc-09`: a browser sculpts up to a measured number of
        // triangles, because it builds the surface tree on the one thread
        // that also paints. Said here, at the press, with both numbers in
        // it — `overSculptLimit` is false everywhere but the web, so a
        // desktop build never reaches the sentence. A refused press opens no
        // stroke, and the moves and the release that follow it find none
        // open and do nothing.
        final Geometry? held = state.project[objectId]?.geometry;
        if (held is EditedGeometry &&
            overSculptLimit(state.project.profile, held.triangleCount)) {
          _cubit.say(
            sculptLimitRefusal(state.project.profile, held.triangleCount),
            important: true,
            refusal: true,
          );
          return;
        }
        _sculptSession.pointerDown(
          view: event.view,
          at: event.at,
          objectId: objectId,
          kind: kind,
          radiusPixels: _sculpt.radius,
          // A stylus reports how hard it is pressing and a mouse reports
          // 1.0 — `InputPolicy`'s own rule — so the same field means "how
          // hard this brush pushes at full pressure" on both.
          //
          // The force rides beside the strength rather than multiplied into
          // it, which is where `SculptStroke` has always wanted it: its own
          // `apply` computes `strength * pressure`, so this is the identical
          // arithmetic said in the place that lets a frame's samples share
          // one stroke — `view-21`'s own batching.
          strength: _sculpt.strength,
          pressure: event.force,
          falloff: _sculpt.falloff,
          symmetryX: _sculpt.symmetryX,
          inverted: event.erase,
        );
      case StrokePhase.move:
        _sculptSession.pointerMove(
          view: event.view,
          at: event.at,
          kind: kind,
          radiusPixels: _sculpt.radius,
          strength: _sculpt.strength,
          pressure: event.force,
          falloff: _sculpt.falloff,
          symmetryX: _sculpt.symmetryX,
          inverted: event.erase,
        );
      case StrokePhase.end:
        _sculptSession.pointerUp();
    }
  }

  /// `SculptPalette.onBrush`: arms that brush's own rail tool, the same way
  /// pressing its key already does.
  void _setSculptBrush(BrushKind kind) => _ranTool(sculptToolOf(kind));

  void _setSculptRadius(double to) => setState(() => _sculpt.diameter = to);

  void _setSculptStrength(double to) => setState(() => _sculpt.strength = to);

  void _setSculptFalloff(BrushFalloff to) =>
      setState(() => _sculpt.falloff = to);

  void _setSculptSymmetryX(bool to) => setState(() => _sculpt.symmetryX = to);

  /// The Subdivide button — one `SubdivideMesh`, which is one undo step.
  void _subdivideForSculpt() => _cubit.ran(const SubdivideMesh());

  /// Why Subdivide cannot run right now, or null when it can — the same
  /// three refusals `SubdivideMesh.apply` gives, asked before the press so
  /// the button can be disabled and say which one rather than answering
  /// after the fact.
  String? _subdivideRefusal(ModelerReady state) {
    final int? objectId = state.selection.activeObject;
    if (objectId == null) return 'Select an object to sculpt first';
    final ModelObject? object = state.project[objectId];
    if (object == null) return 'Select an object to sculpt first';
    if (object.geometry is! EditedGeometry) {
      return '"${object.name}" has no mesh yet — bake it to a mesh first';
    }
    if (object.shapeSet.keys.isNotEmpty) {
      return 'A subdivision does not carry shape keys with it';
    }
    if (object.skeletonIndex != null) {
      return 'A subdivision does not carry skin weights with it';
    }
    return null;
  }

  /// How many faces the object being sculpted has, or null when there is no
  /// mesh to count — the number on the card that says whether the next
  /// Subdivide is the one to think about.
  int? _sculptFaceCount(ModelerReady state) {
    final int? objectId = state.selection.activeObject;
    final Geometry? geometry = objectId == null
        ? null
        : state.project[objectId]?.geometry;
    return geometry is EditedGeometry ? geometry.triangleCount : null;
  }
}
