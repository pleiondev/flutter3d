/// `wg-00`'s spike, made real: a widget pipeline that survives between
/// frames, repaints only when something in it asked to, and takes a pointer
/// event at a place on its own canvas rather than on the window.
///
/// [WidgetTexture] answers "draw this widget once" and tears its pipeline
/// down on the way out — right for a sign whose text changes once a lap, and
/// wrong for a control surface a player's thumb is on every frame. This
/// answers a different question: build the pipeline once, keep it, and redraw
/// it exactly when [PipelineOwner] or [BuildOwner] say something changed —
/// which is the other half of `doc/tooling-plan.md`'s `wg-00` alongside the
/// input path, and the two are tested by the same object because a control
/// that redraws on every frame regardless of whether a tap landed on it would
/// never have been caught by testing either alone.
///
/// ## The input path
///
/// A ray from a pointer hits a mesh somewhere in the 3D scene and comes back
/// with a UV — `dispatchAtUv` is where that UV stops being the 3D scene's
/// business and starts being this pipeline's: it is turned into a position on
/// the widget's own logical canvas and handed to [GestureBinding.dispatchEvent]
/// the same way `flutter_test`'s own synthetic gestures are, which is the
/// reason this reaches ordinary [GestureDetector]s and `TextField`s rather
/// than a bespoke re-implementation of hit testing.
///
/// ## What this is not
///
/// Not [WidgetSurface] — `wg-01` in the plan, a scene node with a registry
/// entry and a place in a level document. This is the pipeline `WidgetSurface`
/// will hold one of, proven on its own first because a scene node wrapped
/// around a pipeline that redraws every frame is a scene node that hides that
/// bug rather than one that has fixed it.
library;

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A widget's own render pipeline, kept alive across draws and pointer events.
///
/// Holds a [BuildOwner], a [PipelineOwner], a [RenderView] and the element
/// tree [child] built into — the same four pieces [WidgetTexture.rasterise]
/// builds and discards per call, kept here instead so that a [State] inside
/// [child] survives between frames the way it would inside the application's
/// own tree.
final class WidgetSurfacePipeline {
  WidgetSurfacePipeline({
    required Widget child,
    required int width,
    required int height,
    double pixelRatio = 1.0,
  }) : _logical = Size(width / pixelRatio, height / pixelRatio),
       _pixelRatio = pixelRatio {
    _boundary = RenderRepaintBoundary();
    _owner = PipelineOwner(onNeedVisualUpdate: _markDirty);
    _view = RenderView(
      view: WidgetsBinding.instance.platformDispatcher.views.first,
      configuration: ViewConfiguration(
        physicalConstraints: BoxConstraints.tight(_logical * pixelRatio),
        logicalConstraints: BoxConstraints.tight(_logical),
        devicePixelRatio: pixelRatio,
      ),
      child: _boundary,
    );
    _owner.rootNode = _view;
    _view.prepareInitialFrame();

    _build = BuildOwner(
      onBuildScheduled: _markDirty,
      focusManager: FocusManager(),
    );
    _element = RenderObjectToWidgetAdapter<RenderBox>(
      container: _boundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: _logical, devicePixelRatio: pixelRatio),
          child: child,
        ),
      ),
    ).attachToRenderTree(_build);

    // The first frame is drawn unconditionally — nothing has marked itself
    // dirty yet because nothing has run yet, and a pipeline nobody has drawn
    // has nothing to sample.
    _flush();
    _dirty = false;
  }

  final Size _logical;
  final double _pixelRatio;

  late final RenderRepaintBoundary _boundary;
  late final PipelineOwner _owner;
  late final RenderView _view;
  late final BuildOwner _build;
  late final RenderObjectToWidgetElement<RenderBox> _element;

  bool _dirty = true;
  int _redraws = 0;

  /// Whether [PipelineOwner] or [BuildOwner] have reported a change since the
  /// last [redrawIfDirty] — a render object calling `markNeedsPaint` or
  /// `markNeedsLayout`, or an [Element] calling `markNeedsBuild`.
  bool get isDirty => _dirty;

  /// How many times [redrawIfDirty] has actually run the pipeline, for a
  /// caller measuring how often a control redraws itself.
  int get redrawCount => _redraws;

  void _markDirty() => _dirty = true;

  void _flush() {
    _build.buildScope(_element);
    _build.finalizeTree();
    _owner.flushLayout();
    _owner.flushCompositingBits();
    _owner.flushPaint();
  }

  /// Runs the pipeline and returns `true` if [isDirty] was set — the
  /// mechanism `wg-00` measures the cost of, and the reason a control that
  /// nobody touched this frame costs nothing beyond this call and the branch
  /// inside it.
  bool redrawIfDirty() {
    if (!_dirty) return false;
    _flush();
    _dirty = false;
    _redraws++;
    return true;
  }

  /// The pipeline's canvas as an image, whatever it currently holds — call
  /// [redrawIfDirty] first if the caller wants it current.
  ///
  /// The caller owns the image and disposes it.
  Future<ui.Image> currentImage() => _boundary.toImage(pixelRatio: _pixelRatio);

  /// Turns a hit's UV — `(0, 0)` at the surface's own top-left, `(1, 1)` at
  /// its bottom-right, whatever the mesh underneath is shaped like — into a
  /// position on this pipeline's logical canvas and dispatches [event] there.
  ///
  /// [event] is built from the local position because a [PointerEvent] carries
  /// its own coordinates baked in: the caller cannot construct one before
  /// knowing where on this canvas it lands.
  void dispatchAtUv(Offset uv, PointerEvent Function(Offset local) event) {
    dispatchAtLocal(
      Offset(uv.dx * _logical.width, uv.dy * _logical.height),
      event,
    );
  }

  /// The same dispatch, for a caller that already has a position in the
  /// pipeline's own logical pixels rather than a UV.
  ///
  /// **Adds [GestureBinding] itself to the hit-test path, the way
  /// `RendererBinding.hitTestInView` does for the real window.** That entry's
  /// own `handleEvent` is where `pointerRouter.route` and the gesture arena's
  /// `close`/`sweep` happen — a `TapGestureRecognizer` registers with the
  /// router on the down event and is never hit-tested again, so without this
  /// its up event has nowhere to arrive and `onTap` never fires. Found by
  /// writing the test this was missing from first.
  ///
  /// **Reuses the down event's own hit test for every event after it, the
  /// way `GestureBinding._handlePointerEventImmediately` does for a real
  /// window** — its own comment names the reason: a move or an up "should be
  /// dispatched to the same place their initial down was", not wherever a
  /// fresh hit test lands now. Skipping this is invisible for a `Tap` (down
  /// and up land on the same point anyway) and silent for a `Scrollable`: no
  /// exception, no dropped frame, a `ListView` that never once scrolls under
  /// a perfectly good drag sequence, found by `wg-01`'s own scroll test
  /// failing for no reason a stack trace explained — the fix was reading
  /// `GestureBinding`'s own hit-test cache rather than guessing again from
  /// the symptom.
  final Map<int, HitTestResult> _activeHitTests = <int, HitTestResult>{};

  void dispatchAtLocal(
    Offset local,
    PointerEvent Function(Offset local) event,
  ) {
    final built = event(local);
    final pointer = built.pointer;
    final HitTestResult result;
    if (built is PointerDownEvent || built is PointerPanZoomStartEvent) {
      result = HitTestResult();
      _view.hitTest(result, position: local);
      result.add(HitTestEntry(GestureBinding.instance));
      _activeHitTests[pointer] = result;
    } else if (built is PointerUpEvent ||
        built is PointerCancelEvent ||
        built is PointerPanZoomEndEvent) {
      result = _activeHitTests.remove(pointer) ?? _freshHitTest(local);
    } else {
      result = _activeHitTests[pointer] ?? _freshHitTest(local);
    }
    GestureBinding.instance.dispatchEvent(built, result);
  }

  HitTestResult _freshHitTest(Offset local) {
    final result = HitTestResult();
    _view.hitTest(result, position: local);
    result.add(HitTestEntry(GestureBinding.instance));
    return result;
  }

  /// Announces the pointer to [GestureBinding]'s router before its first
  /// event and withdraws it after its last — the two events `dispatchAtUv`
  /// and `dispatchAtLocal` do not carry hit-test information for, per
  /// [GestureBinding.dispatchEvent]'s own contract.
  void announcePointer(int pointer, {required bool added}) {
    GestureBinding.instance.dispatchEvent(
      added
          ? PointerAddedEvent(pointer: pointer)
          : PointerRemovedEvent(pointer: pointer),
      null,
    );
  }

  /// Unmounts the element tree, the way [WidgetTexture.rasterise] does on its
  /// way out — for a [State] that holds a ticker, a listener or an image and
  /// should not keep it once the surface it drew for is gone.
  void dispose() {
    _build.finalizeTree();
  }
}
