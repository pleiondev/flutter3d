import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show FrameCadence;

import '../hot_swap/hot_swap.dart';
import '../view/frame_info.dart';

/// The shape of `presentFrame`, and of every presenter a backend registers.
///
/// A parameter of [SceneSurface] rather than a call it makes: `presentFrame`
/// is picked by a conditional export between `backend_native.dart` and
/// `backend_web.dart`, and a caller that wants to show a frame some other way
/// — a test with no backend, a presenter of its own — passes that instead.
/// A caller that does not simply passes `presentFrame`.
typedef FramePresenter =
    Widget Function(
      GraphicsDevice device,
      TextureHandle frame, {
      BoxFit fit,
      FilterQuality quality,
    });

/// The widget that hands a rendered frame to Flutter.
///
/// **The third copy is what made this a package, and the third copy argued
/// against it.** All three applications had these forty lines, and the racing
/// one carried the objection written out:
///
/// > It is not one yet because the three differ in exactly one place, the
/// > shadow settings, and a package whose only parameter is the thing each
/// > caller sets differently is a package that has moved an argument rather
/// > than removed a duplicate.
///
/// That was right about a settings *parameter*, and it is answered by not
/// having one. The three no longer differ in one place either — the crypt turns
/// reflections off, the platformer asks for three cascades at 2048, the circuit
/// sets an exposure and a sky — so a parameter per difference would be four
/// parameters and growing.
///
/// [settings] is a **function called once per frame**, and that is a capability
/// rather than a style: it lets a game derive what a frame is drawn with from
/// where the camera ended up.
///
/// The circuit needs that — its fog colour is the colour of the air *along this
/// view*, so it is only right if it is worked out after the camera has moved.
/// It manages that today by placing its camera in the tick, before `setState`,
/// and computing the colour in the parent's `build`. The crypt cannot: it
/// places its camera in [onBeforeFrame], which runs *after* the parent has
/// built, so anything it derived there would describe the frame before.
///
/// So the two games do the same thing in two different places, and only one of
/// the two places works for both. A function called here is that place.
///
/// **A hot reload relinks the renderer.** In a debug build the surface
/// registers its [renderer] with [HotSwap] and runs a reload from
/// `reassemble`, so an edited shader is drawn on the next frame with the world
/// as it was — see [HotSwap] for what that does and why.
class SceneSurface extends StatefulWidget {
  const SceneSurface({
    super.key,
    required this.renderer,
    required this.scene,
    required this.view,
    required this.settings,
    required this.onBeforeFrame,
    required this.presentFrame,
    this.moreViews = const <RenderView>[],
    this.onFrame,
    this.cadence,
    this.pixelRatio,
  });

  /// Device pixels per logical pixel to draw at; null uses the screen's
  /// (`MediaQuery.devicePixelRatioOf`). A view that renders below native
  /// resolution on a phone — `Flutter3dView.resolution` — sets it.
  final double? pixelRatio;

  /// The frame-rate cap — `A1.5`: on a refresh [FrameCadence.due] skips, the
  /// surface presents the picture it already has, without calling
  /// [onBeforeFrame] or drawing. Null, the default, draws whenever it is
  /// built.
  ///
  /// The refresh is the scheduler's current frame timestamp. A parent that
  /// drives its own simulation from a ticker asks the same cadence there and
  /// skips the rebuild instead, which is cheaper; this is for one that
  /// rebuilds every refresh regardless.
  final FrameCadence? cadence;

  final Renderer renderer;
  final Scene scene;
  final RenderView view;

  /// Views drawn into the same frame after [view], each through its own
  /// camera into its own `RenderView.viewportFraction`: the other half of a
  /// split screen, a rear-view mirror.
  ///
  /// **The renderer drew several views, and this surface handed it one.** A
  /// two-player game had to leave this widget and drive the renderer itself.
  final List<RenderView> moreViews;

  /// What this frame should be drawn with.
  ///
  /// Called after [onBeforeFrame] and immediately before the frame, so anything
  /// derived from where the camera ended up is derived from where it actually
  /// ended up.
  final RenderSettings Function() settings;

  /// The last thing to happen before the frame: place the camera, sync the
  /// visuals, advance whatever is drawn but not simulated.
  final VoidCallback onBeforeFrame;

  /// `presentFrame`, normally — see [FramePresenter] for why this is a
  /// parameter rather than an import.
  final FramePresenter presentFrame;

  /// Handed every frame this surface draws: [FrameInfo.result] as the
  /// renderer answered it, and [FrameInfo.seconds] since the frame this
  /// surface drew before it.
  ///
  /// **The counters were drawn and thrown away.** A [FrameResult] says what
  /// each pass of the frame cost and which passes did not run, and the one
  /// widget that had it dropped it on the floor after taking the texture
  /// out. An editor's render-graph view is the reader this was added for.
  ///
  /// Called during layout, so a caller keeps the result rather than
  /// rebuilding on it; the [FrameResult.frame] inside is the renderer's own
  /// target and is good only until the next frame.
  final void Function(FrameInfo frame)? onFrame;

  @override
  State<SceneSurface> createState() => _SceneSurfaceState();
}

class _SceneSurfaceState extends State<SceneSurface> {
  /// The last frame drawn and its size, presented again on a refresh the
  /// cadence skips.
  FrameResult? _last;
  (int, int)? _lastSize;

  /// The display's timestamp of the last frame drawn, for
  /// [FrameInfo.seconds].
  Duration? _drawnAt;

  /// Seconds since the last frame drawn, by the scheduler's frame timestamp;
  /// nought for the first, and outside a frame, where there is no timestamp.
  double _secondsSinceDrawn() {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.idle) return 0.0;
    final now = scheduler.currentFrameTimeStamp;
    final was = _drawnAt;
    _drawnAt = now;
    return was == null ? 0.0 : (now - was).inMicroseconds / 1e6;
  }

  /// The refresh [_due] last answered for, and its answer: a layout can run
  /// twice in one refresh, and the cadence must be asked once.
  Duration? _askedAt;
  bool _answer = true;

  bool _due(FrameCadence cadence) {
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    if (_askedAt == now) return _answer;
    _askedAt = now;
    _answer = cadence.due(now) != null;
    return _answer;
  }

  @override
  void initState() {
    super.initState();
    HotSwap.instance
      ..registerRenderer(widget.renderer)
      ..registerScene(widget.scene);
  }

  @override
  void didUpdateWidget(SceneSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.renderer, widget.renderer)) {
      HotSwap.instance.registerRenderer(widget.renderer);
    }
    if (!identical(oldWidget.scene, widget.scene)) {
      HotSwap.instance.registerScene(widget.scene);
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    unawaited(HotSwap.instance.swap());
  }

  @override
  Widget build(BuildContext context) {
    final SceneSurface(
      :renderer,
      :scene,
      :view,
      :settings,
      :onBeforeFrame,
      :presentFrame,
      :moreViews,
      :onFrame,
      :cadence,
      :pixelRatio,
    ) = widget;
    final dpr = pixelRatio ?? MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Clamped because a zero-sized surface is a real state — a panel
        // being animated open, a window dragged to nothing — and a render
        // target of zero pixels is not. Clamped *before* rounding: an
        // unbounded axis — a surface inside a `Column` or a scroll view — is
        // infinite, and `double.infinity.round()` throws rather than
        // reaching a clamp after it.
        final width = (constraints.maxWidth * dpr).clamp(1.0, 8192.0).round();
        final height = (constraints.maxHeight * dpr).clamp(1.0, 8192.0).round();
        final last = _last;
        if (cadence != null &&
            last != null &&
            _lastSize == (width, height) &&
            !_due(cadence)) {
          return presentFrame(renderer.device, last.frame);
        }
        onBeforeFrame();
        final frame = renderer.render(
          width: width,
          height: height,
          scene: scene,
          views: <RenderView>[view, ...moreViews],
          settings: settings(),
        );
        _last = frame;
        _lastSize = (width, height);
        final seconds = _secondsSinceDrawn();
        onFrame?.call(FrameInfo(seconds: seconds, result: frame));
        // From the device rather than painted from an image: a backend whose
        // frame is composited elsewhere has no image to paint, and
        // presentFrame is the one answer every backend can give.
        return presentFrame(renderer.device, frame.frame);
      },
    );
  }
}
