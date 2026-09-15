/// The modal transform, the gizmo it shares a path with, and `view-26n`'s
/// geometry snap — one controller rather than seven fields scattered through
/// `main.dart`'s `State`, because all seven change together and none of them
/// ever calls `setState` on its own: a drag repaints through the viewport's
/// own listenable, not through a rebuild of the whole shell.
///
/// **Constructor-injected, not a mixin.** `[cubit]`, `[history]` and
/// `[editMesh]` are the three things this needs from the screen and nothing
/// else — no `context`, no `mounted`, no `setState`. `history` and `editMesh`
/// are callbacks rather than values because the document they answer about
/// moves out from under a held reference the moment a project opens; asking
/// fresh each time is what keeps this in step with whichever one is current.
library;

import 'dart:ui' show Offset;

import 'package:flutter/services.dart'
    show HardwareKeyboard, LogicalKeyboardKey;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:vector_math/vector_math.dart' as vm;

import 'element_picking.dart' show PickingView, cursorPickSlack;
import 'geometry_snap.dart';
import 'modeler_cubit.dart';
import 'transform_gizmo.dart';
import 'transform_modal.dart';
import 'ui/tools.dart' show kDragTools;

/// What [ModelerStage.overlayView] hands back — the three numbers a drag's
/// pixel math and a turn's axis both need from whichever camera is current.
typedef OverlayView = ({
  vm.Vector3 eye,
  vm.Vector3 right,
  vm.Vector3 up,
  double pixel,
  bool perspective,
});

class TransformSession {
  TransformSession({
    required this.cubit,
    required this.history,
    required this.editMesh,
  });

  final ModelerCubit cubit;

  /// The current document — a callback, not a held reference, because the
  /// document a call is about moves out from under one the moment a project
  /// opens.
  final ModelHistory Function() history;

  /// The mesh being edited, when what is selected has one — the same
  /// callback reason as [history].
  final EditMesh? Function() editMesh;

  /// Pickers over every other mesh object's geometry — `view-26n`'s own
  /// candidates for a geometry snap — rebuilt only when that object's own
  /// version moves.
  final Map<int, ({int version, MeshPicker picker})> _otherPickers =
      <int, ({int version, MeshPicker picker})>{};

  /// Drops every cached picker in [_otherPickers], so the next geometry
  /// search rebuilds each one from scratch.
  ///
  /// **Called whenever a new document opens**, the same reason
  /// `ElementPickerCache.forget` is — its own doc comment says why: ids
  /// start again in the new project, and a picker keyed by an id and version
  /// that happens to match again would answer about a mesh from the document
  /// that is now gone.
  void forget() => _otherPickers.clear();

  /// Where the selection's own median stood when the current move began, so
  /// `view-26n`'s geometry snap has something to measure a delta from. Null
  /// outside a mesh-mode move.
  vm.Vector3? _snapAnchorStart;

  /// What the drag is about to snap onto, or null. Read by the viewport to
  /// draw the ring and by nothing else — the delta it implies already lives
  /// on the modal itself.
  SnapTarget? _snapTarget;

  /// Read by the viewport to draw the snap ring.
  SnapTarget? get snapTarget => _snapTarget;

  /// The camera and viewport the last drag report was measured against, so a
  /// keyboard-driven change mid-drag (`X`, a typed digit) can re-run the same
  /// geometry search the pointer itself last ran.
  PickingView? _lastPickingView;

  /// The height the picture was laid out at, kept so a key press can measure a
  /// pixel the same way a pointer move does.
  double _lastViewportHeight = 600;

  /// The transform in progress, or null.
  ///
  /// **One object for the pointer and the keyboard both**, because they are the
  /// same transform: a person presses `G`, moves the mouse, presses `X`, types
  /// `5` and presses Enter, and every one of those changes the same thing.
  /// Two paths would answer differently on the frame the constraint arrives.
  TransformModal? _modal;

  /// Whether a transform is currently in progress.
  TransformModal? get modal => _modal;

  /// How much of the transform has been applied to the document already.
  vm.Vector3 _appliedSoFar = vm.Vector3.zero();

  /// A drag with a transform tool armed.
  ///
  /// **The drag is in pixels and the model is in metres**, so the conversion
  /// goes through the same pixel size the overlay uses — which is what makes a
  /// vertex follow the pointer rather than lag behind it or run ahead. Rotation
  /// and scale take the drag as an amount rather than as a direction, because
  /// without an axis to constrain them there is nothing else it could mean;
  /// the axis arrives with the gizmo.
  ///
  /// **`Ctrl` is read here and nowhere earlier.** It is what already asks
  /// [TransformModal] for a fixed grid, and it is what `view-26n`'s geometry
  /// search below asks to run at all — one modifier, so a hand that has
  /// learned "hold this to snap" gets the sharper answer whenever there is one
  /// in reach and the plain grid otherwise, rather than a second key to learn.
  void dragged(Offset delta, double viewportHeight, PickingView view) {
    final state = cubit.state;
    final String? tool = state is ModelerReady ? state.tool : null;
    if (state is! ModelerReady || tool == null) return;
    if (!kDragTools.contains(tool)) return;
    if (history().selection.isEmpty) return;

    _lastViewportHeight = viewportHeight;
    _lastPickingView = view;
    final OverlayView look = state.stage.overlayView(viewportHeight);
    final TransformModal modal = modalFor(tool);
    modal.snapping = HardwareKeyboard.instance.isControlPressed;

    // Pixels into whatever the transform is measured in. A move is metres at
    // the depth the selection is at — a pixel is a different number of metres a
    // metre further away — and a turn and a scale are a hundredth per pixel,
    // which is the sensitivity every modeller settles on.
    if (modal.kind == TransformKind.move) {
      final vm.Vector3 middle = middleOfSelection();
      final double metres =
          look.pixel * (look.perspective ? (middle - look.eye).length : 1.0);
      modal.dragged +=
          look.right * (delta.dx * metres) + look.up * (-delta.dy * metres);
    } else {
      // One number, carried on whichever component the constraint lets
      // through, so `amount` can zero the rest the same way it does for a move.
      final double by = delta.dx * 0.01;
      modal.dragged += switch (modal.axis) {
        TransformAxis.y => vm.Vector3(0, by, 0),
        TransformAxis.z => vm.Vector3(0, 0, by),
        _ => vm.Vector3(by, 0, 0),
      };
    }
    updateGeometrySnap(modal, view);
    applyModal(modal, look);
  }

  /// What `view-26n`'s drag would snap onto right now, or nothing.
  ///
  /// **Searched from where the pointer alone wants the median to go**, via
  /// [TransformModal.pointerAmount] rather than [TransformModal.amount]: the
  /// latter already carries whatever a previous frame's grid- or geometry-snap
  /// left it at, and searching around that answer is a search that cannot
  /// escape a target once found even when the hand keeps moving away from it.
  ///
  /// Scoped to a mesh-mode move — the only shape a byte-for-byte position
  /// match means anything for. An object-mode move (snapping one whole object
  /// onto another) and a target that is a *face* of somebody else's mesh are
  /// both left for later: the first is a different question (which point of
  /// the moving object's own geometry counts), and the second needs a
  /// point-on-a-plane projection this file does not do — `geometry_snap.dart`
  /// says so as well.
  void updateGeometrySnap(TransformModal modal, PickingView view) {
    modal.geometrySnapDelta = null;
    _snapTarget = null;
    if (modal.kind != TransformKind.move || !modal.snapping) return;
    final selection = history().selection;
    if (selection.mode != SelectionMode.mesh) return;
    final vm.Vector3? start = _snapAnchorStart;
    final int? objectId = selection.activeObject;
    if (start == null || objectId == null) return;

    final sources = _otherSnapSources(excluding: objectId);
    if (sources.isEmpty) return;

    final target = findSnapTarget(
      view: view,
      near: start + modal.pointerAmount,
      sources: sources,
      radiusPixels: cursorPickSlack,
    );
    if (target == null) return;
    _snapTarget = target;
    modal.geometrySnapDelta = target.position - start;
  }

  /// Every other mesh object's geometry, ready to be searched — the
  /// [SnapSource] list `findSnapTarget` scans, built fresh from a per-object
  /// picker cache rather than kept as one list across drags, since which
  /// objects even exist can change between one drag and the next.
  List<SnapSource> _otherSnapSources({required int excluding}) {
    final project = history().project;
    final sources = <SnapSource>[];
    for (final ModelObject object in project.objects) {
      if (object.id == excluding) continue;
      final geometry = object.geometry;
      if (geometry is! EditedGeometry) continue;
      final cached = _otherPickers[object.id];
      final MeshPicker picker;
      if (cached != null && cached.version == object.version) {
        picker = cached.picker;
      } else {
        final plan = MeshLayoutPlan()..build(geometry.mesh);
        picker = MeshPicker(geometry.mesh, MeshBvh(geometry.mesh, plan));
        _otherPickers[object.id] = (version: object.version, picker: picker);
      }
      sources.add(
        SnapSource(
          id: object.id,
          picker: picker,
          objectToWorld: worldTransformOf(project, object.id),
        ),
      );
    }
    return sources;
  }

  /// What the viewport reports when the pointer goes up: the transform is
  /// accepted, which is what letting go of a drag means.
  void endDrag() => commit();

  /// A key arrived while a transform is going on.
  ///
  /// Returns whether it was taken. The keys are the ones every modeller has:
  /// `X`/`Y`/`Z` constrain, digits and a point and a minus type a number,
  /// backspace takes one off, Enter accepts and Escape throws it away.
  bool modalKey(LogicalKeyboardKey key, String? character) {
    final TransformModal? modal = _modal;
    if (modal == null) return false;
    if (key == LogicalKeyboardKey.escape) {
      cancel();
      return true;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      commit();
      return true;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (!modal.type('backspace')) return false;
      reapply(modal);
      return true;
    }
    final TransformAxis? pressed = switch (key) {
      LogicalKeyboardKey.keyX => TransformAxis.x,
      LogicalKeyboardKey.keyY => TransformAxis.y,
      LogicalKeyboardKey.keyZ => TransformAxis.z,
      _ => null,
    };
    if (pressed != null) {
      modal.axis = modal.axis.pressed(pressed);
      reapply(modal);
      return true;
    }
    if (character != null && modal.type(character)) {
      reapply(modal);
      return true;
    }
    return false;
  }

  /// Re-runs the transform at whatever it is now, after a key changed it.
  void reapply(TransformModal modal) {
    final state = cubit.state;
    if (state is! ModelerReady) return;
    final PickingView? view = _lastPickingView;
    if (view != null) updateGeometrySnap(modal, view);
    applyModal(modal, state.stage.overlayView(_lastViewportHeight));
  }

  /// Starts one if there is not one already, opening the transaction it will
  /// be committed or thrown away as.
  TransformModal modalFor(String tool) {
    final TransformModal? going = _modal;
    if (going != null) return going;
    history().beginTransaction();
    final TransformKind kind = switch (tool) {
      'mesh.rotate' || 'object.rotate' => TransformKind.rotate,
      'mesh.scale' || 'object.scale' => TransformKind.scale,
      _ => TransformKind.move,
    };
    // The one snapshot `view-26n`'s geometry snap measures its delta from —
    // taken here, once, rather than read fresh off the mesh on every report:
    // by the second report the mesh already carries part of the drag, and a
    // delta measured against a moving start would not be the delta a byte-
    // for-byte match needs.
    _snapAnchorStart =
        kind == TransformKind.move &&
            history().selection.mode == SelectionMode.mesh
        ? middleOfSelection()
        : null;
    return _modal = TransformModal(kind);
  }

  /// A gizmo arm was grabbed: the same transform `G` starts, with the axis it
  /// was grabbed by already set.
  ///
  /// **One path, not two.** The alternative — a gizmo that computes its own
  /// delta and runs its own command — would be a second answer to what a move
  /// is, and the two would part company at the first snap, the first pivot
  /// setting and the first refusal. Here the arm only says which axis; the drag
  /// after it is the drag `G X` already had, and it ends in the same one step
  /// of history.
  void grabbedGizmo(GizmoAxis axis) {
    if (cubit.state is! ModelerReady) return;
    final String tool = switch (gizmoKind) {
      TransformKind.rotate => 'object.rotate',
      TransformKind.scale => 'object.scale',
      TransformKind.move => 'object.move',
    };
    final modal = modalFor(tool);
    modal.axis = switch (axis) {
      GizmoAxis.x => TransformAxis.x,
      GizmoAxis.y => TransformAxis.y,
      GizmoAxis.z => TransformAxis.z,
    };
    cubit.say(modal.says);
  }

  /// Which gizmo the armed tool asks for.
  TransformKind get gizmoKind => switch ((cubit.state as ModelerReady).tool) {
    'mesh.rotate' || 'object.rotate' => TransformKind.rotate,
    'mesh.scale' || 'object.scale' => TransformKind.scale,
    _ => TransformKind.move,
  };

  /// Where the gizmo stands, or null when nothing is selected.
  ///
  /// Null rather than the origin: a gizmo at the world centre with nothing
  /// selected is a control that does nothing, drawn where a person will aim at
  /// it.
  vm.Vector3? get gizmoPivot =>
      history().selection.isEmpty ? null : middleOfSelection();

  /// Accepts the transform. The transaction closes and its one step stays.
  void commit() {
    if (_modal == null) return;
    _modal = null;
    _snapAnchorStart = null;
    _snapTarget = null;
    _lastPickingView = null;
    history().endTransaction();
    cubit.say(null);
  }

  /// Throws it away.
  ///
  /// **Undone rather than reversed.** The opposite of a scale by 0.3 is a scale
  /// by ten thirds, and the two do not compose back to the identity in floating
  /// point — so Escape closes the transaction, takes its one step back and
  /// drops it, which puts the document back by pointer.
  ///
  /// That is exactly as true with `view-26n`'s geometry snap engaged as
  /// without it: the snap only ever changed what [TransformModal.amount]
  /// answered, never how the answer got applied, so the transaction it
  /// leaves behind is one step regardless and undoing it puts every snapped
  /// vertex back precisely where it started.
  void cancel() {
    if (_modal == null) return;
    _modal = null;
    _snapAnchorStart = null;
    _snapTarget = null;
    _lastPickingView = null;
    final doc = history();
    doc.endTransaction();
    if (doc.undo()) {
      doc.dropRedo();
      cubit.documentMoved();
    }
    cubit.say('cancelled');
  }

  /// Applies whatever the transform is at now, replacing what it applied last.
  ///
  /// Inside the open transaction, so a hundred of these are one step. Each one
  /// runs the *difference* from the last, because a command moves by an amount
  /// rather than to a place.
  void applyModal(TransformModal modal, OverlayView look) {
    final vm.Vector3 want = modal.amount;
    final vm.Vector3 step = want - _appliedSoFar;
    _appliedSoFar = vm.Vector3.copy(want);
    if (step.length2 == 0) {
      cubit.say(modal.says);
      return;
    }

    final bool mesh = history().selection.mode == SelectionMode.mesh;
    final double scalar = step.x + step.y + step.z;
    // **The pivot is the command's, not this file's.** `TransformElements`
    // takes the median of the selected vertices itself and sandwiches the
    // matrix in it, so wrapping the matrix here as well turned and scaled about
    // twice the median — a mesh-mode turn swung the geometry off into space,
    // and nothing on either side of the seam caught it because the command's
    // own pivot had no test. What is handed over is the bare rotation or the
    // bare scale.
    final ModelCommand command = switch (modal.kind) {
      TransformKind.move =>
        mesh ? TransformElements(vm.Matrix4.translation(step)) : MoveBy(step),
      TransformKind.rotate =>
        mesh
            ? TransformElements(
                vm.Matrix4.compose(
                  vm.Vector3.zero(),
                  vm.Quaternion.axisAngle(axisOf(modal, look), scalar),
                  vm.Vector3.all(1),
                ),
                what: 'turn',
              )
            : RotateBy(axis: axisOf(modal, look), radians: scalar),
      TransformKind.scale =>
        mesh
            ? TransformElements(
                vm.Matrix4.diagonal3(vm.Vector3.all(1 + scalar)),
                what: 'scale',
              )
            : ScaleBy(1 + scalar),
    };
    cubit.ran(command, said: modal.says);
  }

  /// The axis a turn goes about: the constrained one, or the view direction.
  vm.Vector3 axisOf(TransformModal modal, OverlayView look) =>
      switch (modal.axis) {
        TransformAxis.x => vm.Vector3(1, 0, 0),
        TransformAxis.y => vm.Vector3(0, 1, 0),
        TransformAxis.z => vm.Vector3(0, 0, 1),
        // Unconstrained, a turn goes about the axis the camera is looking down,
        // so a horizontal drag turns the model the way the hand went whatever
        // angle it is being seen from.
        _ => (look.eye - middleOfSelection()).normalized(),
      };

  /// The middle of what is selected, in world units.
  vm.Vector3 middleOfSelection() {
    final selection = history().selection;
    if (selection.mode == SelectionMode.mesh) {
      final EditMesh? mesh = editMesh();
      if (mesh == null) return vm.Vector3.zero();
      return medianOf(mesh, selection.asMeshSelection);
    }
    final middle = vm.Vector3.zero();
    var counted = 0;
    for (final int id in selection.objects) {
      final object = history().project[id];
      if (object == null) continue;
      middle.add(object.transform.getTranslation());
      counted++;
    }
    return counted == 0 ? middle : (middle..scale(1 / counted));
  }
}
