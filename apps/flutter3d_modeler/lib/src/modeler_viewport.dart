/// The picture, and the pointer that turns it.
///
/// **Not `SceneSurface`, and the difference is one word.** That widget takes a
/// single `RenderView`; a modeller draws a list of them — the viewport now, a
/// material preview beside it later, three of them side by side when LODs are
/// being compared. Widening the session's surface is a change to a published
/// package for a feature that does not exist yet, so this draws the list
/// directly the way `SceneSurface` draws the one, and the two converge when
/// there is a second view to converge over.
///
/// Everything the render loop owns is here rather than in a state object: the
/// camera moves sixty times a second, and a widget rebuilt on every frame is a
/// widget whose subtree is rebuilt on every frame.
///
/// **What the rules are, and where they are not.** Which button orbits, what a
/// pen may do, how two fingers split into a pinch and a pan — none of that is
/// here. It is in `orbit_gestures.dart`, where it is arithmetic over plain
/// numbers and a test can drive a two-finger pinch without a screen. What this
/// widget does is the part that genuinely needs Flutter: turn a `PointerEvent`
/// into that vocabulary, and apply the answer to the camera.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart' show presentFrame;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

import 'element_picking.dart';
import 'gizmo_handles.dart';
import 'ground_grid.dart';
import 'input_policy.dart';
import 'mesh_overlay_builder.dart';
import 'object_picking.dart';
import 'orbit_gestures.dart';
import 'selection_box.dart';
import 'selection_rules.dart' show ElementPickIntent;
import 'settings.dart' show NavigationScheme;
import 'shape_points_overlay.dart';
import 'staging.dart';
import 'transform_gizmo.dart';
import 'transform_modal.dart';
import 'ui/transform_readout.dart';

/// Where a [StrokeEvent] sits in the pointer's own lifetime.
enum StrokePhase {
  /// The pointer went down — the first sample of a new drag.
  start,

  /// The pointer moved while still down — every sample after the first.
  move,

  /// The pointer came up (or was cancelled). The last event of the drag.
  end,
}

/// One pointer event `InputPolicy` has routed to
/// [ModelerViewport.onStroke] rather than to the camera — `S5`'s own
/// `ModelerViewport.onStroke(StrokeEvent{phase, at, view, kind, force})`.
final class StrokeEvent {
  const StrokeEvent({
    required this.phase,
    required this.at,
    required this.view,
    required this.kind,
    required this.force,
  });

  final StrokePhase phase;

  /// Where the pointer is, in the same logical pixels every other viewport
  /// callback reports it in.
  final Offset at;

  /// Built from the camera and the size this widget was laid out at, the
  /// same as [ModelerViewport.onElementPick]'s own — a caller casts its own
  /// ray through it rather than this widget knowing what a brush hits.
  final PickingView view;

  final PointerKind kind;

  /// 0 at no pressure, 1 at the device's own maximum, already resolved by
  /// `InputPolicy.classify` — a mouse always reports 1.0, and [phase]
  /// [StrokePhase.end] always reports 0.0, there being no pressure left on a
  /// pointer that has come up.
  final double force;
}

/// Draws [stage] through [renderer], and orbits it under the pointer.
class ModelerViewport extends StatefulWidget {
  const ModelerViewport({
    super.key,
    required this.renderer,
    required this.stage,
    required this.onFrame,
    this.onRendered,
    this.onViewportMetrics,
    this.onPick,
    this.onElementPick,
    this.onElementHover,
    this.onLookingChanged,
    this.hovered,
    this.brushRadius,
    this.brushInverting = false,
    this.onDragTool,
    this.onDragDone,
    this.onBox,
    this.lassoSelect = false,
    this.strokeTool,
    this.onStroke,
    this.editMesh,
    this.settings = const RenderSettings(),
    this.grid = const GroundGrid(),
    this.elements,
    this.meshVersion = 0,
    this.elementsVersion = 0,
    this.gizmoPivot,
    this.navigation = NavigationScheme.middleMouseOrbit,
    this.gizmoKind = TransformKind.move,
    this.onGizmoDrag,
    this.snapHighlight,
    this.toolFollowsPointer = false,
    this.onToolConfirm,
    this.onToolCancel,
    this.transformReadout,
    this.transformHints,
    this.transformAxis,
    this.onContextMenu,
    this.shapeMarkers = const <ShapeMarker>[],
    this.shapeMarkerColour,
    this.shapeMarkerActiveColour,
    this.overlay = true,
  });

  final Renderer renderer;
  final ModelerStage stage;

  /// Whether this viewport builds the mesh-overlay furniture at all — the
  /// floor grid, the wireframe, the gizmo, the shape markers — every one of
  /// which costs a `MeshOverlay` (a GPU-backed renderer contributor) even
  /// while it draws nothing, because [_buildOverlay] allocates all four the
  /// first frame regardless of whether [grid]/[editMesh]/[gizmoPivot]/
  /// [shapeMarkers] ever give any of them something to draw.
  ///
  /// `S7`'s own row: a read-only preview viewport — screen 14's own source
  /// rig, sitting beside the live target one — draws none of that
  /// interactive chrome and has no [onPick]/[gizmoPivot]/[editMesh] of its
  /// own to hand any of it, so paying for four idle overlays per extra
  /// viewport on screen is a cost with nothing behind it. `false` skips
  /// [_buildOverlay] entirely; every other caller leaves this at its
  /// default and keeps exactly the behaviour it always had.
  final bool overlay;

  /// What the renderer is asked for, which is where a display mode's wireframe
  /// arrives from.
  final RenderSettings settings;

  /// What is selected inside the mesh, and two counters that change when the
  /// mesh or the selection does.
  ///
  /// Counters rather than the values themselves, because an `EditMesh` of two
  /// hundred thousand edges cannot be compared to its previous self once a
  /// frame — which is the comparison a widget would otherwise have to make to
  /// know whether to rebuild the wireframe.
  /// Null is nothing selected, which is not the same as an empty selection at
  /// some level: `Selection.empty` has to be told which level it is empty at,
  /// and a widget's default argument has to be a constant. The state below
  /// picks the level a viewport comes up in.
  final Selection? elements;
  final int meshVersion;
  final int elementsVersion;

  /// Where the gizmo stands, or null when nothing is selected and it is not
  /// drawn at all. The middle of the selection, decided by the caller: the
  /// viewport does not know what a pivot means — `doc-33n` gives that three
  /// answers — and a second opinion here would be a third.
  final Vector3? gizmoPivot;

  /// Which gizmo: arrows, rings or boxes. The same three `TransformModal` has,
  /// because dragging an arm is one way into the same transform `G` starts.
  final TransformKind gizmoKind;

  /// Which navigation scheme the camera answers to — `ux-04`'s own setting.
  ///
  /// Defaults to the one this viewport has always had, so a caller that has
  /// no settings store behind it (a preview viewport, a test) keeps the old
  /// behaviour rather than getting a scheme nobody chose.
  final NavigationScheme navigation;

  /// A drag began on an arm. The axis is the one the ray hit; the caller opens
  /// the transform with it already constrained.
  final void Function(GizmoAxis axis)? onGizmoDrag;

  /// `ux-11`: whether a transform is running with no button held.
  ///
  /// Under "modal on press" the key starts the transform and the pointer
  /// takes it from there, so a plain hover is the drag, the left button
  /// accepts and the right one throws it away — three meanings this widget
  /// otherwise gives to entirely different things, which is why it is a flag
  /// rather than something inferred.
  final bool toolFollowsPointer;

  /// Called when the left button accepts a pointer-driven transform.
  final VoidCallback? onToolConfirm;

  /// Called when the right button, or a cancelled pointer, throws one away.
  final VoidCallback? onToolCancel;

  /// The label carried beside the pointer while a transform is going on —
  /// `ux-11`'s own "Move · X · 0.35 m" — and the keys named under it. Null
  /// for both draws nothing.
  final String? transformReadout;
  final String? transformHints;

  /// Which world axis the transform in progress is confined to, drawn as a
  /// line through the pivot so the constraint is visible in the scene rather
  /// than only in the label.
  final TransformAxis? transformAxis;

  /// A right-click on the picture that did not travel, in global coordinates
  /// — `ux-25`'s own menu of the same tools the palette lists.
  ///
  /// **Not offered while the right button is the camera's.** Under the
  /// left-drag scheme that button holds free-look open (`ux-04`), and a menu
  /// that opened every time somebody finished looking around would be a menu
  /// nobody asked for; the viewport simply does not report one there.
  final void Function(Offset at)? onContextMenu;

  /// The floor, or null for none.
  ///
  /// Null rather than a `showGrid` flag, because the two questions a viewport
  /// asks are "is there a floor" and "what does it look like", and one nullable
  /// value answers both. A material preview wants none of it.
  final GroundGrid? grid;

  /// Called immediately before each frame, after the camera has been placed —
  /// where a caller advances anything drawn but not simulated.
  final VoidCallback onFrame;

  /// The frame just drawn — `S9`'s own row, widened from the `cpuMicros`
  /// alone this used to report: screen 19's metrics card wants
  /// `FrameResult.drawCalls`/`.triangles` beside the timing, and a second
  /// callback carrying those would be a second frame nobody asked the
  /// renderer to draw twice for. `.cpuMicros` is still every other caller's
  /// whole reason for reading this — reported rather than measured by the
  /// caller, because the number worth having is the renderer's own: timing
  /// `build` measures Flutter's layout as well and cannot tell the two apart.
  final void Function(FrameResult frame)? onRendered;

  /// The render target size this frame asked for, in device pixels, and the
  /// pixel ratio it came from.
  ///
  /// Reported every frame rather than read once, because both can change
  /// under this widget without it being rebuilt with a new key — a window
  /// resized, or dragged to a screen of a different pixel ratio. What to do
  /// about that is the caller's own call: it owns the device this draws
  /// through and knows whether that device even has a fixed-size surface to
  /// go stale.
  final void Function(int width, int height, double devicePixelRatio)?
  onViewportMetrics;

  /// What a click landed on, once the frame that answers it has been drawn.
  ///
  /// A [PickResult] rather than a position, because the half of picking that
  /// needs a GPU is the half this widget is for; the caller gets the answer and
  /// decides what it means for the selection. `extend` is shift, which is the
  /// modifier `applyPick` reads.
  final void Function(PickResult pick, {required bool extend})? onPick;

  /// What a click landed on inside the mesh, when the viewport is picking
  /// elements rather than objects.
  ///
  /// Given a [PickingView] built from the camera and the size this widget was
  /// laid out at, because those are the two things only the widget knows.
  /// Present is what puts the viewport in element mode: a caller in object mode
  /// leaves it null and gets [onPick] instead, which is one decision in one
  /// place rather than a mode flag both sides have to agree about.
  /// `extend` became an [ElementPickIntent] with `ux-28`: alt asks for the
  /// loop through the edge under the pointer and control on top of it for the
  /// ring across, so the answer a click wants is no longer a yes-or-no.
  final void Function(
    PickingView view,
    Offset at,
    PointerDeviceKind pointer, {
    required ElementPickIntent intent,
  })?
  onElementPick;

  /// Where the pointer is resting, for the caller to say what is under it —
  /// `ux-28`'s own highlight.
  ///
  /// **Reported rather than answered here, the same bargain [onElementPick]
  /// strikes.** The mesh and its picker belong to the screen; this widget
  /// knows the camera and the size, which is what a [PickingView] is. Null
  /// when the pointer has left the picture, so the highlight goes out rather
  /// than sticking where it was last seen.
  final void Function(PickingView view, Offset? at, PointerDeviceKind pointer)?
  onElementHover;

  /// What to draw as under the pointer, in the same colours the selection is
  /// drawn in but dimmer — `ux-28`. Null, or empty, draws nothing.
  final Selection? hovered;

  /// A free-look has started or ended — `ux-26`'s own mouse hints, which say
  /// so while it is held. Called on the edge only, never per frame.
  final ValueChanged<bool>? onLookingChanged;

  /// How wide the weight brush is, in logical pixels — `ux-24`. Null draws
  /// no circle, which is every mode but the weights sub-mode with a brush
  /// armed.
  ///
  /// **A circle at the pointer, because the radius is the whole gesture.**
  /// A brush whose reach is a number in a panel is one people paint with
  /// blind: the only way to find out what forty-eight pixels covers on this
  /// model at this zoom is to paint and undo.
  final double? brushRadius;

  /// Whether the brush would take weight away rather than add it — Control,
  /// the same modifier `weight_paint_session.dart` reads. Drawn as a
  /// different colour, so the circle says which way the stroke will go
  /// before it goes.
  final bool brushInverting;

  /// A left-button drag with a tool armed, in logical pixels, with the height
  /// the picture was laid out at so a caller can turn it into world units, and
  /// a [PickingView] built from the camera and the size this widget was laid
  /// out at — `view-26n`'s own geometry snap needs to project a world point
  /// back to screen and cast a ray through it, which needs the aspect ratio
  /// only this widget has, the same reason [onElementPick] and [onBox] already
  /// carry one.
  ///
  /// The camera never sees these: `OrbitGestures` leaves the left button to the
  /// tools, which is the rule that lets a drag mean "move this vertex" without
  /// the model swinging away underneath it.
  /// The pointer's own position comes with the delta because `ux-11`'s turn
  /// is the angle the hand swept around the pivot, and an angle cannot be
  /// read out of a delta alone.
  final void Function(
    Offset delta,
    double viewportHeight,
    PickingView view,
    Offset at,
  )?
  onDragTool;

  /// A rectangle was dragged with no tool armed, and let go.
  ///
  /// Given the box and a [PickingView] built from the camera and the size this
  /// widget was laid out at, because those are the two things only the widget
  /// knows. What the box catches and what that does to the selection is the
  /// caller's — `applyBox` holds the rules and they have to agree with the ones
  /// a click follows.
  final void Function(SelectionBox box, PickingView view)? onBox;

  /// Whether a drag draws a freehand loop rather than a rectangle — `ux-28`.
  ///
  /// The tool decides, not a modifier: the two modifiers a drag has are
  /// already spent on add and subtract, and the third is the camera's under
  /// the scheme half the field uses. So the lasso is a button beside Select
  /// on the rail, which also gives it a key and a place in the palette, and
  /// makes it reachable on a tablet with no modifiers at all.
  final bool lassoSelect;

  /// Which continuous-stroke tool [onStroke] answers for, or null for none.
  ///
  /// Read by `InputPolicy.classify` on every primary-button press before the
  /// gizmo, drag and box branches below even look at it — S5's own "earlier,
  /// more specific branch": a stylus or a mouse pressed with this non-null
  /// becomes a [StrokeEvent] instead of a tool drag or a selection box, and a
  /// finger stays with the camera exactly as it already does everywhere else,
  /// `input_policy.dart`'s own rule.
  final ToolCategory? strokeTool;

  /// A continuous-stroke tool's own pointer, once [strokeTool] is set and
  /// `InputPolicy` has routed it here rather than to the camera.
  ///
  /// [StrokeEvent.view] and [StrokeEvent.at] are built the same way
  /// [onElementPick]'s own are — from the camera and the size this widget
  /// was laid out at — so a caller can cast its own ray without this widget
  /// knowing what a brush hits.
  final void Function(StrokeEvent event)? onStroke;

  /// The pointer that was dragging has gone up. What the caller does with it is
  /// close the transaction the first move opened, so the whole drag is one step
  /// of history rather than sixty.
  final VoidCallback? onDragDone;

  /// The mesh whose wireframe is drawn, or null for none.
  ///
  /// Handed in rather than taken from the stage, because which mesh is being
  /// edited is a question about the selection and the selection belongs to the
  /// document — see `mesh_commands.dart`. The stage draws whatever the project
  /// says; this is the one the *overlay* is about.
  final EditMesh? editMesh;

  /// Where `view-26n`'s geometry snap would land the drag, or null when
  /// nothing is in reach right now.
  ///
  /// **Drawn in Flutter, the way [SelectionBox] is, and for the same reason:**
  /// the mark is a screen-space ring round wherever the target projects to,
  /// with no position of its own in the world once the frame that drew it is
  /// gone, so putting it in the mesh overlay would mean unprojecting it back
  /// out on every frame to draw a shape that was never anywhere but the glass.
  final Vector3? snapHighlight;

  /// `S6`'s own row: the morphs sub-mode's own shape markers — one per shape
  /// key, in world space, with whichever one `MorphsPanel` is showing
  /// flagged [ShapeMarker.active]. Empty for every mode but the morphs
  /// sub-mode, which draws nothing here at all — the honest "no live
  /// deformation" this pass leaves for `SceneSync`'s own morph pipeline to
  /// build later.
  final List<ShapeMarker> shapeMarkers;

  /// The colours [shapeMarkers] draw in — an ordinary shape and the active
  /// one. Null falls back to [MeshOverlayColours]'s own ordinary/selected
  /// vertex tones, which is the only case a caller with nothing more
  /// specific to say (a test, chiefly) ever reaches; `ready_parts.dart`
  /// always hands over the real ones, converted from `ui/theme.dart`'s own
  /// `kModelerScheme`.
  final Vector4? shapeMarkerColour;
  final Vector4? shapeMarkerActiveColour;

  @override
  State<ModelerViewport> createState() => _ModelerViewportState();
}

class _ModelerViewportState extends State<ModelerViewport> {
  /// The rules, kept per widget.
  ///
  /// Per widget rather than static, which is what this replaced: two viewports
  /// on screen shared one map of pointer positions, so a drag in the second one
  /// continued the first one's delta and the model jumped.
  final OrbitGestures _gestures = OrbitGestures();

  /// Brings the classifier to what the widget was last built with — `ux-04`.
  ///
  /// Two mutable fields rather than a rebuilt `OrbitGestures`, because it
  /// holds the live pointers: replacing it mid-drag would drop the pair a
  /// two-finger gesture is measured against and fling the model.
  void _syncGestureRules() {
    _gestures
      ..scheme = widget.navigation
      // A tool has the primary drag whenever one is wired: `onDragTool` is
      // non-null exactly while a transform is armed or a box can be dragged,
      // which is the same question `_move` already asks it.
      ..toolArmed = widget.onDragTool != null || widget.strokeTool != null;
  }

  /// `ux-04`'s own second camera, over the same orbit state.
  ///
  /// Made against whichever orbit the stage is carrying now: opening a
  /// document builds a new one, and a free-look still pointed at the old one
  /// would move a camera nothing is drawing through.
  FreeLook get _look {
    final FreeLook? made = _freeLook;
    if (made != null && identical(made.orbit, widget.stage.orbit)) return made;
    return _freeLook = FreeLook(widget.stage.orbit);
  }

  FreeLook? _freeLook;

  /// The frame the walk in progress was last stepped at, so a step is worth
  /// the time that actually passed. Null while nothing is walking.
  Duration? _lookStarted;

  /// Held while free-look is, so the walk keys reach the camera instead of
  /// arming the tools they are bound to — `W` is "move" on one preset and
  /// "walk forward" here, and the one that wins has to be the one the right
  /// button is currently holding open.
  final FocusNode _lookFocus = FocusNode(debugLabel: 'free look');

  /// The keys a walk consumes. Anything else typed during a free-look — a
  /// save, an undo — goes up to the application as usual.
  ///
  /// `final` rather than `const`: a `LogicalKeyboardKey` has an identity of
  /// its own rather than a primitive equality, which a constant set is not
  /// allowed to hold.
  static final Set<LogicalKeyboardKey> _walkKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.keyE,
  };

  /// The size of the picture as of the last frame, so a pan moves the model by
  /// as much as the hand moved and a pick knows what fraction of the frame the
  /// pointer is at. Assigned during layout rather than through `setState`: it
  /// is read by the next pointer event, not by the next build.
  Size _viewport = Size.zero;

  /// Where each pointer went down and with which button, and whether it has
  /// travelled since.
  ///
  /// A click is a press and a release in the same place, and the camera does
  /// not care about the difference — but the selection does, and a drag that
  /// ends anywhere near where it began would otherwise also select whatever is
  /// under it, which is how an orbit deselects the thing being orbited.
  ///
  /// The button is kept from the press because a release does not carry one:
  /// `PointerUpEvent.buttons` is zero by the time it arrives, every button
  /// having been let go.
  final Map<int, ({Offset at, GestureButton button})> _pressed =
      <int, ({Offset at, GestureButton button})>{};
  final Set<int> _travelled = <int>{};

  /// Pointers `InputPolicy` has routed to [ModelerViewport.onStroke] rather
  /// than to the camera — never in [_pressed], since a stroke pointer is
  /// never a candidate for the box or the drag branches below.
  final Set<int> _stroking = <int>{};

  /// The [PickingView] the stroke in progress was last reported with, kept
  /// so the pointer-up event can carry one too without laying a fresh ray
  /// through whatever [_viewport] happens to be at that exact frame —
  /// [StrokeEvent.view] is never null, and this is what keeps it that way.
  PickingView? _strokeView;

  /// How far a pointer may move and still be a click, in logical pixels.
  ///
  /// Flutter's own `kTouchSlop` is eighteen, which is tuned for a finger
  /// deciding between a tap and a scroll on a list. A modeller clicking a
  /// vertex with a mouse is aiming, and eighteen pixels away from where the
  /// button went down is a different vertex.
  static const double _slop = 4.0;

  /// The two overlays this viewport draws its own furniture into: the floor's,
  /// and the mesh's.
  ///
  /// Per viewport rather than per application, both of them: the geometry in
  /// an overlay is built for a particular camera — a vertex handle is sized in
  /// world units for the distance it is at — so two viewports sharing one would
  /// each overwrite the other's idea of how big a pixel is.
  ///
  /// **Two rather than one, because the two are rebuilt on different
  /// questions.** The floor is rebuilt every frame — it is sized against the
  /// camera and nothing else. The mesh's wireframe is rebuilt when the mesh
  /// changes or the selection does, which on a two hundred thousand edge model
  /// is the difference between twenty milliseconds a frame and none; that is
  /// `MeshOverlayBuilder`'s whole reason for existing, and it decides for
  /// itself which of the three batches to refill. Sharing one overlay would
  /// mean the floor's `clear` throwing away a wireframe the builder had
  /// decided not to rebuild.
  ///
  /// Registered floor first: two contributors claiming the same order keep the
  /// order they were added in, so the mesh is drawn over the floor rather than
  /// under it.
  MeshOverlay? _ground;
  MeshOverlay? _mesh;

  /// Registered third and therefore drawn third: a gizmo under the wireframe
  /// would be a gizmo somebody cannot see on the model they are editing, which
  /// is the only model they ever use it on.
  MeshOverlay? _gizmo;

  /// Registered fourth and therefore drawn fourth: `S6`'s own shape markers
  /// sit on top of the gizmo rather than under it, the same "last drawn wins"
  /// order the gizmo itself already gets over the wireframe.
  MeshOverlay? _shapePoints;

  /// The arm the pointer is on, from the last move. Null when it is on none.
  ///
  /// Kept rather than recomputed in `build`, because the answer comes from a
  /// ray against the handles and the handles come from the camera — so asking
  /// it during a rebuild would be asking it against whatever the camera was
  /// when the rebuild happened rather than when the pointer moved.
  GizmoAxis? _hotAxis;

  /// The handles the last frame drew, kept for the hit test.
  ///
  /// The same list both halves use, which is `gizmo_handles.dart`'s own rule:
  /// a hit test written against handles the drawing did not use is a gizmo
  /// that lights one arm and drags another.
  List<GizmoHandle> _handles = const <GizmoHandle>[];

  MeshOverlay _newOverlay(Renderer renderer) => renderer.addContributor(
    MeshOverlay(
      vertexShader: renderer.debugLineVertexShader,
      fragmentShader: renderer.debugLineFragmentShader,
    ),
  );

  /// The wireframe, rebuilt only when it has to be.
  final MeshOverlayBuilder _builder = MeshOverlayBuilder();

  /// What a viewport with no selection hands the builder. Vertex level, which
  /// is the level a mesh mode opens in.
  static final Selection _nothingSelected = Selection.empty(
    ElementLevel.vertex,
  );

  @override
  void dispose() {
    for (final MeshOverlay? overlay in <MeshOverlay?>[
      _ground,
      _mesh,
      _gizmo,
      _shapePoints,
    ]) {
      if (overlay != null) widget.renderer.removeContributor(overlay);
    }
    _lookFocus.dispose();
    super.dispose();
  }

  /// Fills the overlay for the frame about to be drawn.
  ///
  /// Rebuilt every frame rather than when something changes, and that is not
  /// the extravagance it looks like: everything in it is sized against the
  /// camera, so the one thing that would have to invalidate it is the camera
  /// moving, which is the thing that happens sixty times a second. The grid of
  /// a default floor is under seven hundred lines.
  void _buildOverlay(Renderer renderer) {
    final camera = widget.stage.overlayView(_viewport.height);
    // One view value for the frame, rather than each half asking the camera
    // again: two answers taken a moment apart are a gizmo drawn at one size
    // and hit-tested at another.
    final look = MeshOverlayView(
      eye: camera.eye,
      right: camera.right,
      up: camera.up,
      pixel: camera.pixel,
      perspective: camera.perspective,
    );

    final ground = _ground ??= _newOverlay(renderer);
    ground
      ..clear()
      ..lookFrom(
        eye: look.eye,
        right: look.right,
        up: look.up,
        pixel: look.pixel,
        perspective: look.perspective,
      );
    widget.grid?.writeInto(
      ground,
      eye: look.eye,
      fadeRadius: widget.stage.groundFadeRadius,
    );

    // Registered second and therefore drawn second — see the field's comment.
    final mesh = _mesh ??= _newOverlay(renderer);
    final EditMesh? edit = widget.editMesh ?? widget.stage.editMesh;
    if (edit == null) {
      mesh.clear();
    } else {
      _buildWireframe(mesh, edit, look);
    }

    _buildGizmo(renderer, look);
    _buildShapePoints(renderer, look);
  }

  /// The gizmo, when there is a selection to put one on.
  ///
  /// **Built after the wireframe rather than instead of it**, which is the bug
  /// the restructuring above avoids: the wireframe used to return early when
  /// nothing was editable, and a gizmo written before that line would vanish
  /// the moment somebody selected an imported mesh — which has no half-edges
  /// and is exactly a thing people move.
  void _buildGizmo(Renderer renderer, MeshOverlayView look) {
    final gizmo = _gizmo ??= _newOverlay(renderer);
    gizmo
      ..clear()
      ..lookFrom(
        eye: look.eye,
        right: look.right,
        up: look.up,
        pixel: look.pixel,
        perspective: look.perspective,
      );

    final Vector3? pivot = widget.gizmoPivot;
    if (pivot == null) {
      _handles = const <GizmoHandle>[];
      return;
    }

    _handles = gizmoHandles(
      pivot,
      GizmoView(
        eye: look.eye,
        pixel: look.pixel,
        perspective: look.perspective,
      ),
      // `ux-03`: the shapes follow the gizmo. Rings are grabbed as rings and a
      // scale gets its middle box; before this every kind reused the move
      // gizmo's three axis boxes, so a press on a ring hit nothing.
      kind: switch (widget.gizmoKind) {
        TransformKind.move => GizmoKindForHit.move,
        TransformKind.rotate => GizmoKindForHit.rotate,
        TransformKind.scale => GizmoKindForHit.scale,
      },
    );
    // `ux-03`: twice. A ghost through whatever is in front of it, then the
    // handle itself where it is really visible — see
    // `MeshOverlay.linesThrough`. Drawn inside an opaque body with only the
    // depth-tested pass, the arrows were simply not there, which is what the
    // live run found in the default display mode.
    const GizmoDrawing drawing = GizmoDrawing();
    gizmo.throughGeometry(
      () => drawing.writeInto(
        gizmo,
        pivot: pivot,
        handles: _handles,
        kind: widget.gizmoKind,
        hot: _hotAxis,
      ),
    );
    drawing.writeInto(
      gizmo,
      pivot: pivot,
      handles: _handles,
      kind: widget.gizmoKind,
      hot: _hotAxis,
    );
    _buildConstraintAxis(gizmo, pivot, look);
  }

  /// `ux-11`'s own axis line: the constraint, drawn across the scene through
  /// the pivot rather than only named in the label.
  ///
  /// **Through whatever is in front of it**, the same reason the gizmo is
  /// drawn twice: a line confined to the depth-tested pass disappears inside
  /// the very model it is constraining, which is where somebody is looking.
  void _buildConstraintAxis(
    MeshOverlay gizmo,
    Vector3 pivot,
    MeshOverlayView look,
  ) {
    final Vector3? along = switch (widget.transformAxis) {
      TransformAxis.x => Vector3(1, 0, 0),
      TransformAxis.y => Vector3(0, 1, 0),
      TransformAxis.z => Vector3(0, 0, 1),
      // A plane constraint has two axes and no line worth drawing, and `free`
      // has none at all.
      _ => null,
    };
    if (along == null) return;
    final int tint = switch (widget.transformAxis) {
      TransformAxis.x => kGizmoTintX,
      TransformAxis.y => kGizmoTintY,
      _ => kGizmoTintZ,
    };
    final Vector4 colour = Vector4(
      ((tint >> 16) & 0xFF) / 255.0,
      ((tint >> 8) & 0xFF) / 255.0,
      (tint & 0xFF) / 255.0,
      1.0,
    );
    // Long enough to leave the picture at whatever the camera is framing, and
    // no longer: a fixed kilometre would be a line of a few pixels' worth of
    // depth precision on a model a centimetre across.
    final double reach = look.perspective
        ? (look.eye - pivot).length * 40.0
        : 1000.0;
    final Vector3 far = along.scaled(reach);
    gizmo.throughGeometry(() => gizmo.edge(pivot - far, pivot + far, colour));
    gizmo.edge(pivot - far, pivot + far, colour);
  }

  /// [MeshOverlayColours]'s own ordinary/selected vertex tones — what
  /// [_buildShapePoints] draws with whenever [ModelerViewport.shapeMarkerColour]/
  /// [ModelerViewport.shapeMarkerActiveColour] are left null.
  static final MeshOverlayColours _fallbackShapeColours = MeshOverlayColours();

  /// `S6`'s own row: one point per [ModelerViewport.shapeMarkers], or
  /// nothing at all outside the morphs sub-mode — `widget.shapeMarkers` is
  /// empty in every other mode, so this clears whatever the overlay drew
  /// last rather than leaving a marker from a sub-mode the panel has since
  /// left.
  void _buildShapePoints(Renderer renderer, MeshOverlayView look) {
    final List<ShapeMarker> markers = widget.shapeMarkers;
    if (markers.isEmpty) {
      _shapePoints?.clear();
      return;
    }
    final MeshOverlay shapePoints = _shapePoints ??= _newOverlay(renderer);
    shapePoints
      ..clear()
      ..lookFrom(
        eye: look.eye,
        right: look.right,
        up: look.up,
        pixel: look.pixel,
        perspective: look.perspective,
      );
    emitShapePointsOverlay(
      shapePoints,
      markers,
      primary: widget.shapeMarkerColour ?? _fallbackShapeColours.vertex,
      active: widget.shapeMarkerActiveColour ?? _fallbackShapeColours.selected,
    );
  }

  void _buildWireframe(MeshOverlay mesh, EditMesh edit, MeshOverlayView look) {
    _builder.build(
      mesh,
      mesh: edit,
      selection: widget.elements ?? _nothingSelected,
      hovered: widget.hovered,
      meshVersion: widget.meshVersion,
      selectionVersion: widget.elementsVersion,
      view: look,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Focus(
      // `ux-04`: only ever focused by a press that starts a free-look, and
      // only ever swallows the walk keys while one is held — see [_lookKey].
      focusNode: _lookFocus,
      onKeyEvent: _lookKey,
      // `ux-28`: a `Listener` is never told that a pointer left, so the exit
      // that puts the hover highlight out comes from a region round the same
      // area. Not opaque: the `Listener` below is what answers for hits, and
      // a second opaque layer over the picture would be a second answer.
      child: MouseRegion(
        opaque: false,
        onExit: _hoverLeft,
        child: Listener(
        // On the picture and nothing else. A `Listener` up at the scaffold would
        // orbit the camera when somebody drags a value in the properties panel,
        // which is the first bug every viewport in every tool has had.
        //
        // **Opaque, rather than deferring to whatever the backend presented.**
        // The child is `presentFrame`'s own widget, and a backend with no image
        // to show yet — the first frame, a device composited elsewhere, a test
        // — hands back something that hit-tests as nothing, so the viewport
        // silently stopped answering the mouse at all. Its own area is its own
        // to answer for; what is drawn in it does not decide that.
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        // The lit arm follows a pointer that is not pressed. A hover rather than
        // a move, so that dragging the camera across the gizmo does not light
        // arms behind it.
        onPointerHover: _hover,
        onPointerCancel: (PointerCancelEvent event) => _up(event),
        onPointerSignal: _signal,
        onPointerPanZoomStart: (PointerPanZoomStartEvent event) =>
            _gestures.pinchStart(),
        onPointerPanZoomUpdate: _panZoom,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            _viewport = constraints.biggest;
            // `ux-04`: before anything else this frame, so a scheme changed in
            // Settings and a tool armed a moment ago are both true of the very
            // next press rather than of the one after it.
            _syncGestureRules();
            // `ux-04`: the walk keys are read per frame, and this is the frame.
            _walkWhileLooking();
            widget.onFrame();
            // Near and far from where the camera ended up, every frame: a fixed
            // range spends its precision on empty space when the model is small
            // and clips it when the model is large, and a modeller meets both
            // inside one session.
            widget.stage.orbit.syncProjectionDepth(widget.stage.camera);
            // After the projection and before the render: the overlay is sized
            // against the camera as it will be for this frame, not as it was for
            // the last one, and a grid a frame behind is a grid that swims under
            // a model while somebody orbits. Skipped entirely for a viewport
            // that asked for none of it — see [ModelerViewport.overlay].
            if (widget.overlay) _buildOverlay(widget.renderer);
            // Clamped because a zero-sized viewport is a real state — a panel
            // animating open, a window dragged to nothing — and a render
            // target of no pixels is not.
            final int width = (constraints.maxWidth * dpr).round().clamp(
              1,
              8192,
            );
            final int height = (constraints.maxHeight * dpr).round().clamp(
              1,
              8192,
            );
            widget.onViewportMetrics?.call(width, height, dpr);
            final frame = widget.renderer.render(
              width: width,
              height: height,
              scene: widget.stage.scene,
              views: widget.stage.views(),
              settings: widget.settings,
            );
            widget.onRendered?.call(frame);
            // From the device rather than painted from an image, for the
            // reason `SceneSurface` gives: a backend whose frame is composited
            // elsewhere has no image to paint, and presentFrame is the one
            // answer every backend can give.
            final Widget picture = presentFrame(
              widget.renderer.device,
              frame.frame,
            );
            final SelectionBox? box = _box;
            final bool showBox = box != null && box.isBox;
            // Re-projected every frame rather than cached: the target does not
            // move, but the camera can — an orbit mid-drag has to carry the
            // ring with it the same way it carries the gizmo.
            final Vector3? snapAt = widget.snapHighlight;
            final Offset? snapScreen = snapAt == null || _viewport.isEmpty
                ? null
                : PickingView(
                    camera: widget.stage.camera,
                    size: _viewport,
                  ).project(snapAt);
            // Drawn in Flutter rather than into the overlay, and that is the one
            // thing in this viewport that belongs on top of the picture rather
            // than in it: a selection rectangle — and `view-26n`'s own snap
            // target — are screen-space things with no position in the world,
            // and putting either in the overlay would mean unprojecting it back
            // out every frame to draw a shape that was never anywhere but the
            // glass.
            // `ux-11`'s own carried label is the third of these, and the
            // one that has to follow the pointer rather than sit in a corner:
            // a readout in the status line is a readout nobody looking at
            // what they are dragging ever sees.
            final String? readout = widget.transformReadout;
            final Offset? labelAt = _pointerAt;
            final bool showReadout = readout != null && labelAt != null;
            // `ux-24`: the brush's own reach, where the pointer is.
            final bool showBrush =
                widget.brushRadius != null && _pointerAt != null;
            if (!showBox &&
                snapScreen == null &&
                !showReadout &&
                !showBrush) {
              return picture;
            }
            return Stack(
              children: <Widget>[
                Positioned.fill(child: picture),
                if (showBrush)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _BrushPainter(
                          at: _pointerAt!,
                          radius: widget.brushRadius!,
                          inverting: widget.brushInverting,
                        ),
                      ),
                    ),
                  ),
                if (showBox)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _BoxPainter(box)),
                    ),
                  ),
                if (snapScreen != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _SnapPainter(snapScreen)),
                    ),
                  ),
                if (showReadout)
                  TransformReadout(
                    readout: readout,
                    hints: widget.transformHints,
                    at: labelAt,
                    within: _viewport,
                  ),
              ],
            );
          },
        ),
        ),
      ),
    );
  }

  /// The rectangle being dragged, or null.
  SelectionBox? _box;

  /// What [ModelerViewport.onLookingChanged] was last told — `ux-26`.
  bool _toldLooking = false;

  /// Where the pointer was last seen, so `ux-11`'s own readout can be carried
  /// beside it. Null until something moves over the picture.
  Offset? _pointerAt;

  void _down(PointerDownEvent event) {
    final GestureButton button = _buttonOf(event.buttons);

    // `ux-11`: while a pointer-driven transform is going on the buttons mean
    // accept and throw away, and nothing else — not a pick, not a box, not a
    // camera move.
    if (widget.toolFollowsPointer) {
      if (button == GestureButton.secondary) {
        widget.onToolCancel?.call();
      } else {
        widget.onToolConfirm?.call();
      }
      return;
    }

    // The gizmo gets the press before the camera does, and only the primary
    // button. Otherwise the arm a person aimed at orbits the view instead of
    // moving the object — and they aimed at a thirteen-pixel square, so the
    // aim was deliberate.
    final onGizmoDrag = widget.onGizmoDrag;
    if (onGizmoDrag != null && button == GestureButton.primary) {
      final GizmoAxis? axis = _gizmoUnder(event.localPosition);
      if (axis != null) {
        onGizmoDrag(axis);
        // `ux-03`: the press is registered before this returns, and used to
        // not be. `_move` reads `_pressed` to decide whether a drag has
        // started and `_up` reads it to fire `onDragDone`; without an entry
        // here the arm a person grabbed armed a transform that then saw no
        // movement at all — the live run got "You · move" on the history with
        // a zero delta, and the selection dropped, because `_up` fell through
        // to `_pick`. The camera still never sees this press:
        // `_gestures.pointerDown` below is what would tell it, and this
        // returns before reaching it.
        _pressed[event.pointer] = (at: event.localPosition, button: button);
        _travelled.remove(event.pointer);
        return;
      }
    }

    // A continuous-stroke tool's own press — earlier and more specific than
    // the box/drag branch below, and the only branch that ever consults
    // `InputPolicy`: touch and the trackpad fall straight through to the
    // camera below unchanged, exactly as they already do for every tool that
    // never sets `strokeTool` at all.
    final ToolCategory? strokeTool = widget.strokeTool;
    final onStroke = widget.onStroke;
    if (strokeTool != null &&
        onStroke != null &&
        button == GestureButton.primary &&
        !_viewport.isEmpty) {
      final InputIntent intent = const InputPolicy().classify(
        kind: _kindOf(event.kind),
        tool: strokeTool,
        pressure: event.pressure,
        inverted: event.kind == PointerDeviceKind.invertedStylus,
      );
      if (intent is ToolStroke) {
        _stroking.add(event.pointer);
        final PickingView view = _strokeView = PickingView(
          camera: widget.stage.camera,
          size: _viewport,
        );
        onStroke(
          StrokeEvent(
            phase: StrokePhase.start,
            at: event.localPosition,
            view: view,
            kind: _kindOf(event.kind),
            force: intent.force,
          ),
        );
        return;
      }
    }

    _pressed[event.pointer] = (at: event.localPosition, button: button);
    _travelled.remove(event.pointer);
    _gestures.pointerDown(
      event.pointer,
      kind: _kindOf(event.kind),
      at: _pointOf(event.localPosition),
      button: button,
      modifiers: _modifiers(),
    );
    // `ux-04`: free-look claims the keyboard for as long as it is held, so
    // that W walks forward instead of arming the move tool. Asked for here
    // rather than in `_walk` because focus is granted a frame later than it
    // is requested, and the first frame of a walk is the one somebody feels.
    if (_gestures.isLooking) {
      _lookStarted = null;
      _lookFocus.requestFocus();
    }
  }

  void _move(PointerMoveEvent event) {
    if (_stroking.contains(event.pointer)) {
      final onStroke = widget.onStroke;
      if (onStroke != null && !_viewport.isEmpty) {
        final PickingView view = _strokeView = PickingView(
          camera: widget.stage.camera,
          size: _viewport,
        );
        onStroke(
          StrokeEvent(
            phase: StrokePhase.move,
            at: event.localPosition,
            view: view,
            kind: _kindOf(event.kind),
            force: InputPolicy.normalizePressure(event.pressure),
          ),
        );
      }
      return;
    }

    final start = _pressed[event.pointer];
    if (start != null && (event.localPosition - start.at).distance > _slop) {
      _travelled.add(event.pointer);
    }
    // `ux-11`: the readout follows a button drag as well as a hover, and this
    // is the only place a pressed pointer reports where it is. No `setState`:
    // the frame this label is drawn on is scheduled by the transform landing
    // in the document, and a second rebuild per pointer event would be one
    // per pointer event more than the picture needs.
    if (widget.transformReadout != null) _pointerAt = event.localPosition;
    // `ux-24`: and while a stroke is actually going on, which is a move
    // rather than a hover. `setState` here for the same reason the hover
    // does it — the circle is drawn in Flutter.
    if (widget.brushRadius != null) {
      setState(() => _pointerAt = event.localPosition);
    }
    // A box, when the left button is dragging and no tool wants the drag. It
    // begins on the first move rather than on the press, because a press that
    // never moves is a click and a box that existed from the press would have
    // to be told apart from one by its size anyway.
    final onBox = widget.onBox;
    if (onBox != null &&
        widget.onDragTool == null &&
        start != null &&
        start.button == GestureButton.primary &&
        _travelled.contains(event.pointer)) {
      final SelectionBox box = _box ??= SelectionBox(
        from: start.at,
        pointer: event.kind,
        lasso: widget.lassoSelect,
      );
      box
        ..dragTo(event.localPosition)
        ..mode = _boxMode();
      setState(() {});
      return;
    }

    final onDrag = widget.onDragTool;
    if (onDrag != null &&
        start != null &&
        start.button == GestureButton.primary &&
        _travelled.contains(event.pointer) &&
        !_viewport.isEmpty) {
      // The tool takes the drag and the camera does not see it. Reported as a
      // delta rather than a position because that is what a transform is, and
      // because a tool that had to remember where the drag began would be a
      // second copy of what this map already holds.
      onDrag(
        event.delta,
        _viewport.height,
        PickingView(camera: widget.stage.camera, size: _viewport),
        event.localPosition,
      );
      return;
    }
    _apply(_gestures.pointerMove(event.pointer, _pointOf(event.localPosition)));
  }

  /// Lights the arm under the pointer, or unlights them all.
  ///
  /// `setState` only when the answer changed: a hover fires on every pixel of
  /// travel, and rebuilding the viewport sixty times a second for a value that
  /// is the same sixty times is the shape of a stutter nobody can find.
  void _hover(PointerHoverEvent event) {
    // `ux-11`: a transform started from the keyboard is driven by a pointer
    // with nothing held, so the hover *is* the drag. Reported before anything
    // else here, because a gizmo arm lighting up under a transform already in
    // progress would be an invitation to start a second one.
    if (widget.toolFollowsPointer) {
      setState(() => _pointerAt = event.localPosition);
      if (_viewport.isEmpty) return;
      widget.onDragTool?.call(
        event.delta,
        _viewport.height,
        PickingView(camera: widget.stage.camera, size: _viewport),
        event.localPosition,
      );
      return;
    }
    // `ux-24`: the brush circle follows the pointer, so where the pointer is
    // has to be known on every hover rather than only while something is
    // being dragged. `setState` because the circle is drawn in Flutter and
    // nothing else this frame is going to schedule a repaint of it.
    if (widget.brushRadius != null) {
      setState(() => _pointerAt = event.localPosition);
    }
    // `ux-28`: what is under the pointer, for the caller to light up. After
    // the gizmo, because a viewport with a gizmo in it has both and the
    // element under an arm is not the thing a hand is reaching for.
    if (widget.onElementHover case final void Function(
      PickingView,
      Offset?,
      PointerDeviceKind,
    ) told when !_viewport.isEmpty) {
      told(
        PickingView(camera: widget.stage.camera, size: _viewport),
        event.localPosition,
        event.kind,
      );
    }
    if (widget.gizmoPivot == null) return;
    final GizmoAxis? axis = _gizmoUnder(event.localPosition);
    if (axis == _hotAxis) return;
    setState(() => _hotAxis = axis);
  }

  /// The pointer left the picture: nothing is under it any more — `ux-28`.
  ///
  /// Without this the highlight stays on whatever the pointer passed over on
  /// its way out, which reads as a selection that is not one for as long as
  /// the person is looking somewhere else.
  void _hoverLeft(PointerExitEvent event) {
    if (_viewport.isEmpty) return;
    widget.onElementHover?.call(
      PickingView(camera: widget.stage.camera, size: _viewport),
      null,
      event.kind,
    );
  }

  /// The gizmo arm a click at [at] is on, or null.
  ///
  /// Against the handles the last frame drew, which is the rule
  /// `gizmo_handles.dart` states: a hit test written against handles the
  /// drawing did not use is a gizmo that lights one arm and drags another.
  GizmoAxis? _gizmoUnder(Offset at) {
    if (_handles.isEmpty) return null;
    final Ray ray = PickingView(
      camera: widget.stage.camera,
      size: _viewport,
    ).rayThrough(at);
    final GizmoHit? hit = GizmoHit.nearest(
      _handles,
      ray.origin,
      ray.direction.normalized(),
    );
    return hit?.handle.axis;
  }

  void _up(PointerEvent event) {
    if (_stroking.remove(event.pointer)) {
      // The view a stroke ends with is the one its own last sample was cast
      // through, not a fresh one built from whatever `_viewport` happens to
      // be this exact frame — `_strokeView`'s own doc comment says why, and
      // it is never null here: [_stroking] only ever holds a pointer once
      // `_down` has already set it.
      widget.onStroke?.call(
        StrokeEvent(
          phase: StrokePhase.end,
          at: event.localPosition,
          view: _strokeView!,
          kind: _kindOf(event.kind),
          force: 0.0,
        ),
      );
      _strokeView = null;
      return;
    }
    _gestures.pointerUp(event.pointer);
    final start = _pressed.remove(event.pointer);
    final bool travelled = _travelled.remove(event.pointer);
    final SelectionBox? box = _box;
    if (box != null) {
      _box = null;
      setState(() {});
      // Only when it grew into one. A drag of three pixels is a click that
      // wobbled, and answering it with a box that caught nothing would clear
      // the selection somebody was aiming at.
      if (box.isBox && !_viewport.isEmpty) {
        widget.onBox?.call(
          box,
          PickingView(camera: widget.stage.camera, size: _viewport),
        );
      }
      return;
    }
    if (travelled && start?.button == GestureButton.primary) {
      widget.onDragDone?.call();
    }
    // `ux-25`: a right-click that did not travel is a menu, wherever the
    // right button is not already the camera's.
    if (event is PointerUpEvent &&
        start != null &&
        !travelled &&
        start.button == GestureButton.secondary &&
        !_gestures.isLooking) {
      widget.onContextMenu?.call(event.position);
      return;
    }
    if (event is! PointerUpEvent || start == null || travelled) return;
    // The left button only: a middle-drag that happens not to travel is a
    // camera gesture that did nothing, and answering it with a selection
    // change would be answering a gesture nobody made. The right button is the
    // context menu's, whenever there is one.
    if (start.button != GestureButton.primary) return;
    _pick(start.at, event.kind);
  }

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _apply(
      _gestures.scroll(
        kind: _kindOf(event.kind),
        dx: event.scrollDelta.dx,
        dy: event.scrollDelta.dy,
        modifiers: _modifiers(),
      ),
    );
  }

  /// A trackpad's own gesture stream, which macOS and the web deliver instead
  /// of a scroll.
  ///
  /// `panDelta` is the fingers' own travel since the last event and
  /// `scrollDelta` is the view's, which are opposite statements about the same
  /// motion — hence the negation, and this is the one line to flip if a
  /// trackpad ever pans the wrong way on a platform. `scale` is cumulative
  /// since the gesture began, which is what `pinchUpdate` expects: it keeps
  /// the running total and answers with the step.
  void _panZoom(PointerPanZoomUpdateEvent event) {
    _apply(
      _gestures.scroll(
        kind: PointerKind.trackpad,
        dx: -event.panDelta.dx,
        dy: -event.panDelta.dy,
        modifiers: _modifiers(),
      ),
    );
    _apply(_gestures.pinchUpdate(event.scale));
  }

  /// Walks the camera for one frame, while free-look is held — `ux-04`.
  ///
  /// **Read from the keyboard's own state rather than from key events.**
  /// Walking is continuous: a key held for half a second is half a second of
  /// travel, not one step per repeat, and the repeat rate is a setting on the
  /// person's machine rather than anything this can count on. So the keys are
  /// asked what they are doing on the frame that draws, and [_lookKey] is
  /// what keeps those same presses from reaching the tools they are bound to.
  void _walkWhileLooking() {
    // `ux-26`: the strip has to say that the buttons mean something else
    // right now, so the one place that already knows per frame reports it.
    // Only on the edge — this runs every frame, and a callback per frame
    // would be a `setState` per frame in whatever is listening.
    if (_gestures.isLooking != _toldLooking) {
      _toldLooking = _gestures.isLooking;
      widget.onLookingChanged?.call(_toldLooking);
    }
    if (!_gestures.isLooking) {
      _lookStarted = null;
      return;
    }
    final Duration now = SchedulerBinding.instance.currentFrameTimeStamp;
    final Duration? last = _lookStarted;
    _lookStarted = now;
    // The first frame of a look has no interval behind it, and a frame that
    // arrived a quarter of a second after the last one is a hitch — a window
    // dragged, a file opened — that would otherwise be walked through in one
    // jump.
    if (last == null) return;
    final double seconds = (now - last).inMicroseconds / 1e6;
    if (seconds <= 0.0 || seconds > 0.25) return;

    final Set<LogicalKeyboardKey> down =
        HardwareKeyboard.instance.logicalKeysPressed;
    double axis(LogicalKeyboardKey plus, LogicalKeyboardKey minus) =>
        (down.contains(plus) ? 1.0 : 0.0) - (down.contains(minus) ? 1.0 : 0.0);

    _look.walk(
      forward: axis(LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyS),
      right: axis(LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyA),
      up: axis(LogicalKeyboardKey.keyE, LogicalKeyboardKey.keyQ),
      seconds: seconds,
      // Shift is the sprint every game in the field puts it on; Ctrl is the
      // other half nobody agrees about, and slow is the more useful of the
      // two to have beside it when placing a camera inside a room.
      fast: HardwareKeyboard.instance.isShiftPressed,
      slow: HardwareKeyboard.instance.isControlPressed,
    );
  }

  /// Swallows the walk keys for as long as free-look is held.
  ///
  /// `W` arms the move tool under one preset and walks the camera forward
  /// here, and the one that should win is the one the right button is
  /// currently holding open. Everything else — a save, an undo — goes up to
  /// the application unchanged.
  KeyEventResult _lookKey(FocusNode node, KeyEvent event) =>
      _gestures.isLooking && _walkKeys.contains(event.logicalKey)
      ? KeyEventResult.handled
      : KeyEventResult.ignored;

  /// Moves the camera by [intent], in the sense `OrbitController` takes.
  ///
  /// The two negations are the whole of the conversion: an intent's pitch and
  /// pan are positive upward, because that is how a person describes a
  /// gesture, and the controller's are positive downward, because that is how
  /// a screen is measured.
  void _apply(CameraIntent intent) {
    if (!intent.movesCamera) return;
    final orbit = widget.stage.orbit;
    if (intent.deltaYaw != 0.0 || intent.deltaPitch != 0.0) {
      orbit.rotate(intent.deltaYaw, -intent.deltaPitch);
    }
    // `ux-04`: the same two numbers, about a different pivot — see [FreeLook].
    if (intent.lookYaw != 0.0 || intent.lookPitch != 0.0) {
      _look.look(intent.lookYaw, -intent.lookPitch);
    }
    if (intent.panRight != 0.0 || intent.panUp != 0.0) {
      orbit.pan(
        intent.panRight,
        -intent.panUp,
        viewportHeight: _viewport.height,
      );
    }
    if (intent.zoomBy != 1.0) orbit.zoom(intent.zoomBy);
  }

  /// Asks the renderer what is drawn at [at] and hands the answer up.
  ///
  /// The frame that answers is the next one, so this is a future that outlives
  /// the click; `mounted` is checked because the window can close between the
  /// two, and the error arm is the renderer's own advice — a pick whose frame
  /// failed is a pick that hit nothing.
  Future<void> _pick(Offset at, PointerDeviceKind kind) async {
    if (_viewport.isEmpty) return;
    final bool extend = HardwareKeyboard.instance.isShiftPressed;

    // Elements first, because a caller that wants them has said so by handing
    // one over, and asking the renderer for a node as well would cost a whole
    // extra frame to answer a question nobody asked.
    final onElement = widget.onElementPick;
    if (onElement != null) {
      onElement(
        PickingView(camera: widget.stage.camera, size: _viewport),
        at,
        kind,
        // `ux-28`: the command key stands in for control on a Mac, where
        // control-click is the system's own secondary click and never
        // reaches this at all.
        intent: ElementPickIntent.forModifiers(
          extend: extend,
          alternate: HardwareKeyboard.instance.isAltPressed,
          control:
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed,
        ),
      );
      return;
    }

    final onPick = widget.onPick;
    if (onPick == null) return;
    try {
      final MeshNode? node = await widget.renderer.pickPixel(
        at.dx / _viewport.width,
        at.dy / _viewport.height,
      );
      if (!mounted) return;
      onPick(objectUnder(node), extend: extend);
    } on Object {
      if (!mounted) return;
      onPick(pickedNothing, extend: extend);
    }
  }

  /// What releasing the box would do, from the modifiers held right now.
  ///
  /// Read at every move rather than latched at the press, because people reach
  /// for shift after starting to drag at least as often as before — and the
  /// rectangle drawn on screen is a promise about what letting go will do.
  static SelectionBoxMode _boxMode() {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) return SelectionBoxMode.add;
    if (keys.isControlPressed || keys.isMetaPressed) {
      return SelectionBoxMode.subtract;
    }
    return SelectionBoxMode.replace;
  }

  static GestureModifiers _modifiers() => GestureModifiers(
    shift: HardwareKeyboard.instance.isShiftPressed,
    control: HardwareKeyboard.instance.isControlPressed,
    alt: HardwareKeyboard.instance.isAltPressed,
  );

  static GesturePoint _pointOf(Offset at) => GesturePoint(at.dx, at.dy);

  /// Flutter's device kinds down to the four the rules are written in.
  ///
  /// An inverted stylus is the eraser end of a pen and is still a pen, which
  /// is the whole point of refusing it the camera. `unknown` is what a
  /// synthesised event carries, and a mouse is the kind whose rules leave the
  /// left button to the tools — so it is the safe default for something whose
  /// origin nobody knows.
  static PointerKind _kindOf(PointerDeviceKind kind) => switch (kind) {
    PointerDeviceKind.mouse => PointerKind.mouse,
    PointerDeviceKind.touch => PointerKind.touch,
    PointerDeviceKind.trackpad => PointerKind.trackpad,
    PointerDeviceKind.stylus ||
    PointerDeviceKind.invertedStylus => PointerKind.stylus,
    PointerDeviceKind.unknown => PointerKind.mouse,
  };

  /// Which button began this press.
  ///
  /// The middle button is checked first because a press with both the left and
  /// the middle down is a middle-drag with a stray finger, and the camera is
  /// the gesture that cannot be taken back.
  static GestureButton _buttonOf(int buttons) {
    if (buttons & kMiddleMouseButton != 0) return GestureButton.middle;
    if (buttons & kSecondaryMouseButton != 0) return GestureButton.secondary;
    return GestureButton.primary;
  }
}

/// The rectangle a box-select is being dragged as.
///
/// A hairline and a wash, in the colour the mode means: the same teal the
/// selection wash uses for replace and add, and the warm accent for subtract —
/// because a person dragging a subtract box over half a model wants to be sure
/// which way round it is before letting go.
class _BoxPainter extends CustomPainter {
  const _BoxPainter(this.box);

  final SelectionBox box;

  @override
  void paint(Canvas canvas, Size size) {
    final Color colour = switch (box.mode) {
      SelectionBoxMode.subtract => const Color(0xFFFF9926),
      _ => const Color(0xFF62D4E3),
    };
    final Paint wash = Paint()..color = colour.withValues(alpha: 0.12);
    final Paint line = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // `ux-28`: the loop as it was drawn, closed back to where it started —
    // which is the shape `SelectionBox.encloses` will be asked about, so
    // what is on the glass is what letting go will mean.
    if (box.trail case final List<Offset> path when path.length > 1) {
      final Path drawn = Path()..addPolygon(path, true);
      canvas
        ..drawPath(drawn, wash)
        ..drawPath(drawn, line);
      return;
    }
    canvas
      ..drawRect(box.rect, wash)
      ..drawRect(box.rect, line);
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.box.rect != box.rect ||
      old.box.mode != box.mode ||
      old.box.trail?.length != box.trail?.length;
}

/// `ux-24`'s own brush circle: how far the weight brush reaches, where the
/// pointer is.
///
/// **On the glass rather than on the model.** The radius is a number of
/// screen pixels — `WeightPaintSession` converts it to world units at the
/// depth it finds — so the honest picture of it is a circle on screen, and a
/// ring projected onto the surface would be a different shape from the one
/// the stroke actually covers.
class _BrushPainter extends CustomPainter {
  const _BrushPainter({
    required this.at,
    required this.radius,
    required this.inverting,
  });

  final Offset at;
  final double radius;
  final bool inverting;

  @override
  void paint(Canvas canvas, Size size) {
    // Warm for adding weight, cool for taking it away — the same two
    // directions `SelectionBoxMode` already colours, so a hand that has
    // learned one has learned the other.
    final Color colour = inverting
        ? const Color(0xFF62D4E3)
        : const Color(0xFFFF9926);
    canvas
      ..drawCircle(
        at,
        radius,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      )
      // A second, darker ring just outside it: the brush is drawn over a
      // model that is sometimes the same colour as the circle, and one line
      // disappears into it.
      ..drawCircle(
        at,
        radius + 1.5,
        Paint()
          ..color = const Color(0x66000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }

  @override
  bool shouldRepaint(_BrushPainter old) =>
      old.at != at || old.radius != radius || old.inverting != inverting;
}

/// The ring `view-26n` draws round whatever a snapped drag is about to land
/// on, before the pointer that would commit it comes up.
///
/// A warm ring rather than [_BoxPainter]'s teal: the box states a region that
/// is about to become the selection, and this states a single point the
/// selection is about to become — the same distinction `MeshOverlayColours`
/// draws between an unselected vertex and one that is, in the one warm colour
/// this file already reads that as.
class _SnapPainter extends CustomPainter {
  const _SnapPainter(this.at);

  final Offset at;

  static const Color _colour = Color(0xFFFF9926);

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawCircle(
        at,
        9.0,
        Paint()
          ..color = _colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      )
      ..drawCircle(at, 2.0, Paint()..color = _colour);
  }

  @override
  bool shouldRepaint(_SnapPainter old) => old.at != at;
}
