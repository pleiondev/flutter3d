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
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

import 'element_picking.dart';
import 'ground_grid.dart';
import 'mesh_overlay_builder.dart';
import 'object_picking.dart';
import 'orbit_gestures.dart';
import 'staging.dart';

/// Draws [stage] through [renderer], and orbits it under the pointer.
class ModelerViewport extends StatefulWidget {
  const ModelerViewport({
    super.key,
    required this.renderer,
    required this.stage,
    required this.onFrame,
    this.onRendered,
    this.onPick,
    this.onElementPick,
    this.onDragTool,
    this.onDragDone,
    this.editMesh,
    this.settings = const RenderSettings(),
    this.grid = const GroundGrid(),
    this.elements,
    this.meshVersion = 0,
    this.elementsVersion = 0,
  });

  final Renderer renderer;
  final ModelerStage stage;

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

  /// The floor, or null for none.
  ///
  /// Null rather than a `showGrid` flag, because the two questions a viewport
  /// asks are "is there a floor" and "what does it look like", and one nullable
  /// value answers both. A material preview wants none of it.
  final GroundGrid? grid;

  /// Called immediately before each frame, after the camera has been placed —
  /// where a caller advances anything drawn but not simulated.
  final VoidCallback onFrame;

  /// What the frame just drawn cost inside `Renderer.render`, in microseconds.
  ///
  /// Reported rather than measured by the caller, because the number worth
  /// having is the renderer's own: a caller timing `build` measures Flutter's
  /// layout as well and cannot tell the two apart.
  final void Function(int micros)? onRendered;

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
  final void Function(
    PickingView view,
    Offset at,
    PointerDeviceKind pointer, {
    required bool extend,
  })?
  onElementPick;

  /// A left-button drag with a tool armed, in logical pixels, with the height
  /// the picture was laid out at so a caller can turn it into world units.
  ///
  /// The camera never sees these: `OrbitGestures` leaves the left button to the
  /// tools, which is the rule that lets a drag mean "move this vertex" without
  /// the model swinging away underneath it.
  final void Function(Offset delta, double viewportHeight)? onDragTool;

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
    for (final MeshOverlay? overlay in <MeshOverlay?>[_ground, _mesh]) {
      if (overlay != null) widget.renderer.removeContributor(overlay);
    }
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
    final look = widget.stage.overlayView(_viewport.height);

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
      return;
    }
    _builder.build(
      mesh,
      mesh: edit,
      selection: widget.elements ?? _nothingSelected,
      meshVersion: widget.meshVersion,
      selectionVersion: widget.elementsVersion,
      view: MeshOverlayView(
        eye: look.eye,
        right: look.right,
        up: look.up,
        pixel: look.pixel,
        perspective: look.perspective,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Listener(
      // On the picture and nothing else. A `Listener` up at the scaffold would
      // orbit the camera when somebody drags a value in the properties panel,
      // which is the first bug every viewport in every tool has had.
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: (PointerCancelEvent event) => _up(event),
      onPointerSignal: _signal,
      onPointerPanZoomStart: (PointerPanZoomStartEvent event) =>
          _gestures.pinchStart(),
      onPointerPanZoomUpdate: _panZoom,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          _viewport = constraints.biggest;
          widget.onFrame();
          // Near and far from where the camera ended up, every frame: a fixed
          // range spends its precision on empty space when the model is small
          // and clips it when the model is large, and a modeller meets both
          // inside one session.
          widget.stage.orbit.syncProjectionDepth(widget.stage.camera);
          // After the projection and before the render: the overlay is sized
          // against the camera as it will be for this frame, not as it was for
          // the last one, and a grid a frame behind is a grid that swims under
          // a model while somebody orbits.
          _buildOverlay(widget.renderer);
          final frame = widget.renderer.render(
            // Clamped because a zero-sized viewport is a real state — a panel
            // animating open, a window dragged to nothing — and a render
            // target of no pixels is not.
            width: (constraints.maxWidth * dpr).round().clamp(1, 8192),
            height: (constraints.maxHeight * dpr).round().clamp(1, 8192),
            scene: widget.stage.scene,
            views: widget.stage.views(),
            settings: widget.settings,
          );
          widget.onRendered?.call(frame.cpuMicros);
          // From the device rather than painted from an image, for the
          // reason `SceneSurface` gives: a backend whose frame is composited
          // elsewhere has no image to paint, and `present` is the one answer
          // both can give.
          return widget.renderer.device.present(frame.frame);
        },
      ),
    );
  }

  void _down(PointerDownEvent event) {
    final GestureButton button = _buttonOf(event.buttons);
    _pressed[event.pointer] = (at: event.localPosition, button: button);
    _travelled.remove(event.pointer);
    _gestures.pointerDown(
      event.pointer,
      kind: _kindOf(event.kind),
      at: _pointOf(event.localPosition),
      button: button,
      modifiers: _modifiers(),
    );
  }

  void _move(PointerMoveEvent event) {
    final start = _pressed[event.pointer];
    if (start != null && (event.localPosition - start.at).distance > _slop) {
      _travelled.add(event.pointer);
    }
    final onDrag = widget.onDragTool;
    if (onDrag != null &&
        start != null &&
        start.button == GestureButton.primary &&
        _travelled.contains(event.pointer)) {
      // The tool takes the drag and the camera does not see it. Reported as a
      // delta rather than a position because that is what a transform is, and
      // because a tool that had to remember where the drag began would be a
      // second copy of what this map already holds.
      onDrag(event.delta, _viewport.height);
      return;
    }
    _apply(_gestures.pointerMove(event.pointer, _pointOf(event.localPosition)));
  }

  void _up(PointerEvent event) {
    _gestures.pointerUp(event.pointer);
    final start = _pressed.remove(event.pointer);
    final bool travelled = _travelled.remove(event.pointer);
    if (travelled && start?.button == GestureButton.primary) {
      widget.onDragDone?.call();
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
        extend: extend,
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
