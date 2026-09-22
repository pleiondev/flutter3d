/// `edu-02`'s own screen: the same `edu-00` lesson document `edu-06`'s
/// [LessonStereoView] plays back through a headset, drawn flat and stepped
/// through by the same two buttons — `flutter3d_stereo`'s version is the
/// template this file follows line for line, swapping [StereoSurface]/
/// [StereoRig] for [SceneSurface]/[CameraNode], since a flat screen has no
/// stage to move, only a camera.
///
/// **Between steps, the camera is a turntable, not a statue.** `edu-00`
/// gives a step a bare position and yaw, no orbit target — but a viewer that
/// only ever snapped to a step's exact pose and held perfectly still there
/// would be a slideshow, not something a person could look around in, and
/// Dmitrii asked for drag-to-rotate/pinch-to-zoom/two-finger-pan the same
/// way `flutter3d_modeler` already gives a model. So a step's `at`/`yaw`
/// only places the *start* of an [OrbitController] turntable, owned by
/// [OrbitCubit] — and from there a mouse or a finger owns the camera until
/// the next step resets it. This is additive to the format, not a
/// reinterpretation of it: `next`/`previous` still lands exactly where
/// `edu-00` says a step should.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
// `Material` the widget, under a prefix: both imports below hide the bare
// name because `flutter3d` has its own `Material` (a render material, not a
// widget), and this file needs Flutter's — only for the one line that gives
// `CheckPrompt`'s `TextField` an ancestor to assert on.
import 'package:flutter/material.dart'
    as widgets_material
    show Material, MaterialType;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'check_prompt.dart';
import 'lesson_player.dart';
import 'orbit_cubit.dart';

/// Wraps [SceneSurface] around a [LessonPlayer], with a "Previous"/"Next"
/// button pair driving it and the current step's `caption` shown beside
/// them — the flat counterpart of `flutter3d_stereo`'s `LessonStereoView`.
class LessonView extends StatefulWidget {
  const LessonView({
    super.key,
    required this.renderer,
    required this.scene,
    required this.camera,
    required this.player,
    this.nodes = const <String, SceneNode>{},
    this.restPositions = const <String, Vector3>{},
  });

  final Renderer renderer;
  final Scene scene;
  final CameraNode camera;
  final LessonPlayer player;

  /// Named scene nodes a step's `visible`/`hidden` list can reach — empty
  /// for a lesson (like the shipped tour) that names none. Resolving level
  /// entity names to nodes is left to the caller, the same split
  /// `LessonStereoView`'s own doc comment already draws.
  final Map<String, SceneNode> nodes;

  /// Where each named node sits with nothing taken apart, so a step's
  /// `offsets` can be read as the whole disassembled state rather than as a
  /// move from wherever the last step left things. Empty for a lesson that
  /// takes nothing apart, which is every lesson that ships today.
  final Map<String, Vector3> restPositions;

  @override
  State<LessonView> createState() => _LessonViewState();
}

class _LessonViewState extends State<LessonView> {
  late final OrbitCubit _orbit;

  /// Cumulative scale as of the last `onScaleUpdate`, so the step reported
  /// each time is the *change* since then — `OrbitController.zoom` wants a
  /// step, not the running total `ScaleUpdateDetails.scale` carries.
  double _lastScale = 1.0;

  double _viewportHeight = 600.0;

  @override
  void initState() {
    super.initState();
    _orbit = OrbitCubit(OrbitController(widget.camera))
      ..resetFromStep(
        widget.player.current,
        nodes: widget.nodes,
        restPositions: widget.restPositions,
      );
  }

  @override
  void dispose() {
    unawaited(_orbit.close());
    super.dispose();
  }

  void _step(void Function() advance) {
    setState(() {
      advance();
      _orbit.resetFromStep(
        widget.player.current,
        nodes: widget.nodes,
        restPositions: widget.restPositions,
      );
    });
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount <= 1) {
      // One finger, or a mouse: a turntable drag.
      _orbit.rotate(details.focalPointDelta.dx, -details.focalPointDelta.dy);
    } else {
      // Two or more: the same "slide to pan, pinch to zoom" a phone's photo
      // viewer already trained every finger to expect.
      _orbit.pan(
        details.focalPointDelta.dx,
        -details.focalPointDelta.dy,
        viewportHeight: _viewportHeight,
      );
      if (details.scale > 0.0) {
        _orbit.zoom(_lastScale / details.scale);
        _lastScale = details.scale;
      }
    }
  }

  void _onScroll(PointerScrollEvent event) {
    // A wheel notch, for a mouse with no pinch to give it. `0.0015` is
    // `flutter3d_modeler`'s own `OrbitGestures.zoomPerScrollPixel` — one
    // constant to keep in step with rather than a second one to drift from.
    _orbit.zoom(math.exp(event.scrollDelta.dy * 0.0015));
  }

  /// The browser's own pinch-to-zoom on a trackpad — a discrete signal, not
  /// a stream with a start and an end the way [ScaleUpdateDetails] or
  /// [PointerPanZoomUpdateEvent] are. Confirmed by instrumenting a real
  /// trackpad pinch and reading what actually arrived: over a hundred of
  /// these in one gesture and not one [PointerPanZoomUpdateEvent], which is
  /// what this file wired first, on the strength of `flutter3d_modeler`'s
  /// own comment about what "macOS and the web" deliver — true for a
  /// two-finger *pan*, not for this. [PointerScaleEvent.scale] is each
  /// event's own step since the last one, not a running total, so it needs
  /// no `_lastScale`-style bookkeeping the way [ScaleUpdateDetails.scale]
  /// does.
  void _onPointerScale(PointerScaleEvent event) {
    if (event.scale > 0.0) _orbit.zoom(1.0 / event.scale);
  }

  /// macOS and the web deliver a trackpad's two-finger *pan* as this stream
  /// rather than as a [PointerScrollEvent] — `flutter3d_modeler`'s
  /// `_panZoom` wires the identical callback for the identical reason. The
  /// zoom half of that same comment does not hold here: see
  /// [_onPointerScale].
  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _orbit.pan(
      event.panDelta.dx,
      event.panDelta.dy,
      viewportHeight: _viewportHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentStep = widget.player.current;
    final caption = currentStep?.string('caption');
    final checkSpec = currentStep == null
        ? null
        : CheckSpec.fromStep(currentStep);
    // `MaterialType.transparency`: paints nothing of its own, only gives
    // `CheckPrompt`'s `TextField` the `Material` ancestor it asserts on —
    // found the hard way, live, because `main.dart`'s `LessonReady` branch
    // returns this widget with no `Scaffold` around it (the loading and
    // error screens each carry their own; this one, until now, needed none).
    return widgets_material.Material(
      type: widgets_material.MaterialType.transparency,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Listener(
              onPointerSignal: (PointerSignalEvent event) {
                if (event is PointerScrollEvent) _onScroll(event);
                if (event is PointerScaleEvent) _onPointerScale(event);
              },
              onPointerPanZoomUpdate: _onPanZoomUpdate,
              child: GestureDetector(
                // Opaque rather than the default `deferToChild`: the scene
                // surface underneath is a presented GPU frame (or, headless in
                // a test, nothing painted at all), and a drag anywhere over
                // the viewport should orbit the camera regardless of what
                // happens to be drawn at that exact pixel.
                behavior: HitTestBehavior.opaque,
                onScaleStart: (ScaleStartDetails details) => _lastScale = 1.0,
                onScaleUpdate: _onScaleUpdate,
                // Rebuilds this subtree on every `OrbitCubit` emit — the only
                // reason it needs to. `SceneSurface` calls `renderer.render`
                // from inside its own `build`
                // (`packages/flutter3d_app/lib/src/surface/scene_surface.dart`),
                // so a mutation to the turntable with no rebuild to follow
                // moves the camera and leaves the picture on screen exactly as
                // it was — found the hard way, by a drag that changed
                // `camera.readWorldPosition()` in a widget test and changed
                // nothing a person watching a real browser could see.
                child: BlocBuilder<OrbitCubit, OrbitPose>(
                  bloc: _orbit,
                  builder: (BuildContext context, OrbitPose pose) {
                    return LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            _viewportHeight = constraints.maxHeight;
                            return SceneSurface(
                              renderer: widget.renderer,
                              scene: widget.scene,
                              view: RenderView(camera: widget.camera),
                              settings: () => const RenderSettings(),
                              // The turntable already wrote the camera's
                              // transform the moment a gesture moved it;
                              // `apply()` here is idempotent — it only
                              // replays the orbit's own last-known state — so
                              // calling it again on an unrelated rebuild costs
                              // nothing.
                              onBeforeFrame: () => _orbit.orbit.apply(),
                              presentFrame: presentFrame,
                            );
                          },
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24.0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (caption != null && caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xCC0E1013),
                        borderRadius: BorderRadius.circular(6.0),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Text(
                          caption,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.0,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (checkSpec != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    // Keyed by the step's own name, not the spec's contents:
                    // the ordinary Flutter answer to "a fresh attempt counter
                    // on a fresh step" is a fresh `State`, not a field this
                    // widget has to remember to reset itself.
                    child: CheckPrompt(
                      key: ValueKey(currentStep!.name),
                      spec: checkSpec,
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Previous step',
                      onPressed: widget.player.isFirst
                          ? null
                          : () => _step(widget.player.previous),
                    ),
                    const SizedBox(width: 24.0),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      tooltip: 'Next step',
                      onPressed: widget.player.isLast
                          ? null
                          : () => _step(widget.player.next),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
