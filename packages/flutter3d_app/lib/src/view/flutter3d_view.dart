/// One widget that owns an engine — item 25 of the 1.0 scope.
///
/// `SceneSurface` draws a scene a caller already set up: a device opened, a
/// renderer made, a loop stepped, focus, lifecycle and teardown all the
/// caller's. That stays, as the low level. [Flutter3dView] is everything
/// around it, so a first scene is about ten lines:
///
/// ```dart
/// Flutter3dView(
///   onCreated: (engine) => engine.scene.add(
///     MeshNode(
///       DeviceMesh.upload(engine.device, CuboidShape().build()),
///       RenderMaterial(baseColor: LinearColor.fromSrgb(0.9, 0.5, 0.2, 1.0)),
///     ),
///   ),
/// )
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart'
    show ParticleSystem;
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        EngineLoop,
        FrameCadence,
        FrameSpan,
        InputState,
        IsolateSimulation,
        SimulationHandle,
        TimeSource,
        simFormats;

import '../backend_native.dart'
    if (dart.library.js_interop) '../backend_web.dart'
    show platformDevices, presentFrame;
import '../l10n/app_localizations.dart';
import '../surface/scene_surface.dart';
import '../widget_surface/widget_texture.dart';
import '../xr/xr_driver.dart';
import 'frame_info.dart';
import 'simulation_placing.dart';
import 'view_settings.dart';

/// What a [Flutter3dView] made, handed to [Flutter3dView.onCreated] once the
/// device is open: the scene to fill, the camera, the loop to add systems
/// and plugins to, and the renderer's single extension point.
///
/// **It says what it owns.** A device or renderer the view was handed is
/// borrowed — [ownsDevice] and [ownsRenderer] are false — and left alone
/// when the view goes; what the view opened or made itself it disposes.
final class Flutter3dEngine {
  Flutter3dEngine._({
    required this.devices,
    required GraphicsDevice device,
    required Renderer renderer,
    required this._scene,
    required this.view,
    required this.loop,
    required this.simulation,
    required this.log,
    required this.backendRefusals,
    required this.ownsDevice,
    required this.ownsRenderer,
    // A named parameter may not be private, and the two are replaced after
    // a device loss, so they are fields behind getters.
    // ignore: prefer_initializing_formals
  }) : _device = device,
       // ignore: prefer_initializing_formals
       _renderer = renderer,
       _published = ValueNotifier<PublishedState>(simulation.published);

  /// What the simulation published last, as the view saw it after the
  /// frame it drew: its step, its components and positions, its events, and
  /// what every probe read ([PublishedState.probes]).
  ///
  /// **The way a widget beside the view reads the simulation.** A gauge, a
  /// chart or a readout over the picture listens here (a
  /// `ValueListenableBuilder`, or [ProbeBuilder] for one probe) rather than
  /// reaching into the world, so it reads the same wherever the simulation
  /// runs: inline, or in an isolate (`SimulationPlacement.isolate`), where
  /// the state arrives as plain values. It changes at most once a frame the
  /// view draws, and not while the view is paused.
  ValueListenable<PublishedState> get published => _published;
  final ValueNotifier<PublishedState> _published;

  /// Brings [published] up to what [simulation] holds now.
  void _republish() {
    final now = simulation.published;
    if (!identical(now, _published.value)) _published.value = now;
  }

  /// The backends this engine chose its device from — its own registry, not
  /// one shared with other engines in the isolate. The registry it opens a
  /// device from again when the one it had is lost for good.
  final DeviceRegistry devices;

  /// The device the engine draws with.
  ///
  /// **Not the same object for the engine's whole life.** A device lost for
  /// good (a WebGPU device, a GPU reset) is replaced by one the engine opens
  /// from [devices], when it opened the first itself; see
  /// [Flutter3dView.onDeviceRestored]. Read it where it is used rather than
  /// keeping it.
  GraphicsDevice get device => _device;
  GraphicsDevice _device;

  /// The renderer. Its `renderSteps` is the one place a frame is extended,
  /// and the loop's plugins are handed it as a registry.
  ///
  /// Made again after a device loss, over the device that came back; the
  /// new one takes over the old one's `renderSteps`, so the loop's plugins,
  /// installed again, extend it. Read it where it is used.
  Renderer get renderer => _renderer;
  Renderer _renderer;

  /// The loss the engine is waiting out, or null while the device works:
  /// a WebGL context the browser has not given back yet.
  DeviceLoss? get loss => _loss;
  DeviceLoss? _loss;

  /// Moves [particles]' live particles with every origin shift of this
  /// engine's scenes, until the registration is cancelled — item 18's hook
  /// for particles, which hold positions in the scene's space and are not
  /// nodes the shift moves.
  ///
  /// Through `ParticleSystem.followOrigin` on [scene], and again on the
  /// scene a game swaps in: the system's one handler per scene, so a system
  /// a `Particles3D` draws as well moves once a shift, not twice.
  Registration followOrigin(ParticleSystem particles) {
    final follower = _shiftFollowers.putIfAbsent(
      particles,
      () => _Follower(particles.followOrigin(_scene)),
    );
    follower.holders++;
    var cancelled = false;
    return Registration(() {
      if (cancelled) return;
      cancelled = true;
      if (--follower.holders > 0) return;
      follower.onScene.cancel();
      _shiftFollowers.remove(particles);
    });
  }

  final Map<ParticleSystem, _Follower> _shiftFollowers =
      Map<ParticleSystem, _Follower>.identity();

  /// What the engine does with an origin shift the loop published: the
  /// scene's nodes move, and its handlers move what follows it — the
  /// particles among them.
  void _shiftOrigin(OriginShifted shift) => _scene.shiftOrigin(shift.to);

  /// The world being drawn: the one the view was given or made, until a
  /// game hands it another.
  ///
  /// **Settable, for a game whose levels are scenes of their own** —
  /// `LevelLoader.build` makes one per level. The next frame draws the new
  /// one, an origin shift moves it, and [camera] moves into it when it stood
  /// in the old one. The old scene is the game's: the view neither keeps nor
  /// disposes it.
  Scene get scene => _scene;
  set scene(Scene value) {
    if (identical(value, _scene)) return;
    final eye = camera;
    if (identical(eye.scene, _scene)) {
      eye.removeFromParent();
      value.add(eye);
    }
    _scene = value;
    for (final MapEntry(key: particles, value: follower)
        in _shiftFollowers.entries) {
      follower.onScene.cancel();
      follower.onScene = particles.followOrigin(value);
    }
  }

  Scene _scene;

  /// The view onto it: the camera, the settings, the history the temporal
  /// resolve keeps.
  final CameraView view;

  /// The loop: systems, plugins, input and the fixed step, advanced once a
  /// frame while the view is shown and the application in the foreground.
  final EngineLoop loop;

  /// The simulation, wherever `LoopSettings.simulation` placed it: what a
  /// game submits input to and the view reads published state from.
  ///
  /// Inline (the default) it is a `LocalSimulation` over [loop]. Placed in
  /// an isolate it is an `IsolateSimulation`, stepped by the view once a
  /// frame and paused with it; [loop] then runs the view's own frame
  /// systems and plugins, and the world is the isolate's. On the web the
  /// same factory's loop runs here, stepped the same way.
  final SimulationHandle simulation;

  /// What the engine says about itself: the device it opened, a backend
  /// that would not start, a device lost, a callback that threw. The one
  /// the view was handed, or one of its own.
  final EngineLog log;

  /// Why the backends tried before the one that draws would not start, one
  /// line each; empty when the first one did. Not empty on a phone or a
  /// desktop with Impeller off, where the software rasteriser draws.
  final List<String> backendRefusals;

  /// Whether [device] was opened by the view and is disposed with it.
  final bool ownsDevice;

  /// Whether [renderer] was made by the view and is disposed with it.
  final bool ownsRenderer;

  /// The camera [view] looks through.
  CameraNode get camera => view.camera;

  void _dispose() {
    for (final id in loop.plugins.order.toList().reversed) {
      if (loop.plugins.isEnabled(id)) loop.plugins.disable(id);
    }
    view.dispose();
    if (ownsRenderer) renderer.dispose();
    if (ownsDevice) device.dispose();
    _published.dispose();
  }
}

/// How many device pixels a [Flutter3dView] draws per logical pixel — its
/// resolution policy. An open set: a later minor may add a policy.
final class ViewResolution {
  const ViewResolution._(this._scale, this._maxPixels);

  /// The screen's own: every device pixel drawn.
  static const ViewResolution native = ViewResolution._(1.0, null);

  /// The screen's resolution times [factor] — 0.5 draws a quarter of the
  /// pixels, which a phone may want for a 3D view behind its UI.
  const ViewResolution.scaled(double factor) : this._(factor, null);

  /// The screen's own, lowered until the view is no more than [maxPixels]
  /// device pixels in all.
  const ViewResolution.capped(int maxPixels) : this._(1.0, maxPixels);

  final double _scale;
  final int? _maxPixels;

  /// The pixel ratio to draw a view of [size] logical pixels at, on a screen
  /// of [devicePixelRatio].
  double pixelRatioFor(double devicePixelRatio, Size size) {
    final ratio = devicePixelRatio * _scale;
    final cap = _maxPixels;
    if (cap == null || size.isEmpty) return ratio;
    final pixels = size.width * ratio * size.height * ratio;
    if (pixels <= cap) return ratio;
    return ratio * math.sqrt(cap / pixels);
  }
}

/// An engine as a widget: it opens a device, makes a renderer, runs an
/// [EngineLoop] with the plugins of [plugins], draws [scene] through a
/// [CameraView], and owns focus, input, lifecycle and teardown — item 25 of
/// the 1.0 scope. `SceneSurface` stays as the low level it is built on, and
/// `Scene3D` is sugar over this widget for a scene written as widgets.
///
/// **Its options come in four groups**: [device] (a device to borrow or
/// where to open one, what shows its frames, what a loss does), [view]
/// (settings, resolution, when it draws, the warm-up), [loop] (the step,
/// the input, where the simulation runs, the origin) and [plugins]. What is
/// left at the top is what a first scene names: the scene, the camera, the
/// callbacks, focus, restoration and the log.
///
/// **Focus.** [autofocus] is false by default: a 3D view is often one
/// widget on a page, and taking the keyboard from a text field is not its
/// call. A tap on the view focuses it. Key events reach [onKeyEvent] only
/// while it has focus — the input of this view, not the application's;
/// an `ActionMap` from `flutter3d_game` consumes them there.
///
/// **Lifecycle.** The loop and [onPausedChanged] pause when the view stops
/// being shown — `TickerMode` off, which a route that is not current and an
/// offstage subtree turn off — and when the application leaves the
/// foreground (`AppLifecycleState` other than resumed). An audio engine
/// pauses on [onPausedChanged]; it is the seam because this package does not
/// depend on one.
///
/// **One audio listener per view.** [onListenerMoved] is told where the
/// camera is and which way it faces after every frame: where the
/// application's `AudioListener` goes.
///
/// **Restoration.** With a [restorationId], [saveState] is asked for a
/// JSON-encodable value whenever the view pauses, and [restoreState] is
/// handed it back when the route is restored — a run snapshot and its save
/// slot, typically.
///
/// **Ownership.** A device or renderer handed in through [device] is
/// borrowed and left alone at dispose; one the view opened or made it
/// disposes, with the view and the loop's plugins. See [Flutter3dEngine].
///
/// **When the GPU backend will not start**, the view draws with the next
/// one it can open — the software rasteriser where Impeller is off — and
/// says so in a banner over the picture, which can be closed and which
/// `DeviceSettings.fallbackBanner` turns off. The reasons go to [log].
final class Flutter3dView extends StatefulWidget {
  /// A view of [scene] (a new, empty one by default) through [camera] (one
  /// at `(0, 1, 5)` looking at the origin by default).
  const Flutter3dView({
    super.key,
    this.scene,
    this.camera,
    this.onCreated,
    this.onBeforeFrame,
    this.onFrame,
    this.device = const DeviceSettings(),
    this.view = const ViewSettings(),
    this.loop = const LoopSettings(),
    this.plugins = const PluginSettings(),
    this.log,
    this.focusNode,
    this.autofocus = false,
    this.onKeyEvent,
    this.restorationId,
    this.saveState,
    this.restoreState,
    this.onPausedChanged,
    this.onListenerMoved,
    this.time,
    this.xr,
  });

  /// An XR session the view drives, or null for a view of the screen.
  ///
  /// **The runtime paces the frames.** The session is started once the
  /// device is open; from then on a frame is drawn when the runtime hands
  /// one (`XrSession.waitFrame`), and the loop's time is the gap between
  /// the display times it predicts (`DisplayTime`), so [time] is not asked.
  /// The frame's poses, planes and meshes enter the loop's input as
  /// external state, on the tape with their step; its controls drive
  /// `XrSettings.actions`; the camera is where the player stands and the
  /// eyes are placed under it by the runtime's poses and angles; what was
  /// drawn is copied into the runtime's images and the frame ends with the
  /// projection layer and a layer for each `XrSettings.panels`. The screen
  /// shows the eyes side by side. A session that refuses to start, or a
  /// device that cannot feed it, is the view's error ([ViewSettings.failure]).
  final XrSettings? xr;

  /// Where the simulation's time comes from: how many seconds each frame
  /// the view draws hands the loop. Null is the display's own clock,
  /// `TimeSource.realTime`.
  ///
  /// **The loop's step stays fixed whatever the source**, so a run is as
  /// deterministic at a tenth of real speed as at full: a slower source
  /// hands each frame less time, and the loop runs fewer steps. A
  /// laboratory slows its world with `TimeSource.scaled(0.1)` or steps it by
  /// hand with `TimeSource.manual()` (`ManualTime.advance` from a button); a
  /// digital twin replays a recorded log at the pace it was taken with
  /// `TimeSource.log`. Which display refreshes are drawn is still the
  /// display's ([ViewSettings.frameRateCap]); every frame drawn asks this
  /// source for its seconds, the frame callbacks are told them
  /// ([FrameInfo.seconds]), and a simulation placed in an isolate is
  /// stepped by them too.
  ///
  /// A source handed in is the caller's: the view asks it and never resets
  /// it, so a log goes on where it was when the view's ticker stops and
  /// starts again. Replacing it with another starts the new one from the
  /// next frame.
  final TimeSource? time;

  /// The world to draw; null makes an empty one, with a light.
  final Scene? scene;

  /// The camera to draw through; null makes one.
  final CameraNode? camera;

  /// Called once, when the device is open and the engine made: where a
  /// first scene adds its meshes, and a game its systems.
  final void Function(Flutter3dEngine engine)? onCreated;

  /// Called every frame the view draws, after the loop has stepped and
  /// before the frame is drawn, with one [EngineFrame]: the engine, the
  /// seconds since the last ([FrameInfo.seconds]) and what the renderer
  /// answered for the frame before ([FrameInfo.result]).
  ///
  /// One object, as `DeviceSettings.onDeviceLost` is handed, so it can say
  /// more without breaking a handler.
  final void Function(EngineFrame frame)? onFrame;

  /// Called every frame the view draws, with the engine and the frame (an
  /// [EngineFrame], as [onFrame]), before the loop steps: where a game reads a device that is
  /// polled, a gamepad, and decides whether the loop is paused this frame
  /// (`engine.loop.isPaused`), so the frame that reads a press is the frame
  /// it acts in.
  final void Function(EngineFrame frame)? onBeforeFrame;

  /// The device: one to borrow, where to open one, what shows its frames,
  /// what a loss does, and whether a fallback is said on screen.
  final DeviceSettings device;

  /// What is drawn and how: the frame's settings, the view's own, the
  /// resolution, when frames are drawn, what shows instead, the warm-up.
  final ViewSettings view;

  /// The loop: its step, its input, where the simulation runs, and when the
  /// origin follows the camera.
  final LoopSettings loop;

  /// What the loop installs, and the registries it hands them.
  final PluginSettings plugins;

  /// Where the engine says what it did and what went wrong, and the hook a
  /// crash reporter hangs on (`EngineLog.onCrash`): an error a frame
  /// callback or the loop threw is reported there before it is rethrown.
  /// Null makes one of the view's own, at [LogLevel.info]
  /// (`Flutter3dEngine.log`).
  final EngineLog? log;

  /// The view's focus node; null makes one.
  final FocusNode? focusNode;

  /// Whether the view takes focus when it is first shown. False by default.
  final bool autofocus;

  /// Key events while the view has focus.
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;

  /// The restoration id of the view's saved state; null saves nothing.
  final String? restorationId;

  /// The state to save, as JSON-encodable values; asked when the view
  /// pauses.
  final Object? Function()? saveState;

  /// Hands back what [saveState] saved, when the route is restored.
  final void Function(Object? saved)? restoreState;

  /// Told when the view pauses (true) and resumes (false): where an audio
  /// engine pauses.
  final void Function(bool paused)? onPausedChanged;

  /// Told after every frame where the camera is in the world, which way it
  /// faces and which way is up, as one [ListenerPose]: where the view's
  /// audio listener goes.
  final void Function(ListenerPose ears)? onListenerMoved;

  @override
  State<Flutter3dView> createState() => _Flutter3dViewState();
}

class _Flutter3dViewState extends State<Flutter3dView>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        RestorationMixin {
  /// What the view says it did, under this source in the engine's log.
  static const String _source = 'flutter3d_app.view';

  Flutter3dEngine? _engine;
  PlacedSimulation? _placed;

  /// What drives `widget.xr`, once its session has started.
  XrDriver? _xr;
  Object? _error;
  Ticker? _ticker;
  bool _shown = true;
  bool _foreground = true;
  bool _paused = false;
  FocusNode? _ownFocus;
  EngineLog? _ownLog;
  final RestorableStringN _saved = RestorableStringN(null);
  Object? _pendingRestore;
  bool _hasPendingRestore = false;
  StreamSubscription<DeviceLoss>? _losses;
  late final FrameCadence _cadence = FrameCadence(time: widget.time);

  /// What an XR session's clock is asked with, set before every frame.
  final FrameSpan _xrSpan = FrameSpan();

  /// The vsync time the ticker's own count is added to: a ticker counts
  /// from nought each time it starts, and the cadence is handed one clock
  /// that only goes forward, so the source is asked across a stop and a
  /// start as if the stop had not happened rather than reset.
  Duration _ticks = Duration.zero;

  /// The last vsync time handed to the cadence, on that one clock.
  Duration _vsync = Duration.zero;

  /// Whether the fallback banner was closed.
  bool _bannerClosed = false;

  /// Whether the view has been laid out with a size, which starts the
  /// warm-up once.
  bool _laidOut = false;

  /// The warm-up's pending yield between two slices, while it runs: what
  /// [dispose] cancels so no slice runs on a renderer the view has let go.
  Timer? _warmUpYield;
  bool _warmUpStopped = false;

  /// What the renderer answered for the last frame drawn, for
  /// [FrameInfo.result].
  FrameResult? _drawn;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  EngineLog get _log => widget.log ?? (_ownLog ??= EngineLog());

  @override
  String? get restorationId => widget.restorationId;

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_saved, 'state');
    final text = _saved.value;
    if (text == null) return;
    final saved = jsonDecode(text);
    if (_engine == null) {
      _pendingRestore = saved;
      _hasPendingRestore = true;
    } else {
      widget.restoreState?.call(saved);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  Future<void> _open() async {
    // Never inside `initState`, even with a device handed in: `onCreated`
    // may set state on a widget above this one, which is being built now.
    await Future<void>.value();
    if (!mounted) return;
    final log = _log;
    final options = widget.device;
    try {
      final devices = options.devices ?? platformDevices();
      final borrowed = options.device;
      final refusals = <String>[];
      final device =
          borrowed ??
          await devices.open(
            width: 1280,
            height: 720,
            onFallback: (String message) {
              refusals.add(message);
              log.warning(message, source: _source);
            },
          );
      if (!mounted) {
        if (borrowed == null) device.dispose();
        return;
      }
      if (refusals.isNotEmpty) {
        log.warning(
          'drawing with ${device.runtimeType}, not the preferred backend',
          source: _source,
        );
      } else if (borrowed == null) {
        log.info('opened ${device.runtimeType}', source: _source);
      }
      final borrowedRenderer = options.renderer;
      final renderer = borrowedRenderer ?? Renderer.create(device: device);
      final scene = widget.scene ?? _defaultScene();
      final camera = widget.camera ?? _defaultCamera();
      if (camera.parent == null) scene.add(camera);
      final loopOptions = widget.loop;
      final plugins = widget.plugins;
      final loop = EngineLoop(
        input: loopOptions.input ?? InputState(),
        drainLook: loopOptions.drainLook,
        timing: loopOptions.timing,
        profile: loopOptions.profile,
        plugins: plugins.plugins,
        registries: <PluginRegistry>[
          ...plugins.registries,
          renderer.renderSteps,
          // A plugin asks the loop for these by type; without them a format
          // or a VM extension it brings had nowhere to go.
          if (!plugins.registries.any((r) => r is FormatRegistry))
            FormatRegistry(<FormatSpec>[
              ...coreFormats,
              ...simFormats,
              ...plugins.formats,
            ]),
          if (!plugins.registries.any((r) => r is VmExtensions)) VmExtensions(),
          // The physical materials need no line here: the loop installs the
          // built-in `MaterialCatalog` itself, or the one among these.
        ],
      );
      final placed = await placeSimulation(
        loopOptions.simulation,
        loop,
        isolates: IsolateSimulation.isSupported,
      );
      if (!mounted) {
        unawaited(placed.dispose());
        if (borrowedRenderer == null) renderer.dispose();
        if (borrowed == null) device.dispose();
        return;
      }
      _placed = placed;
      // The picture and the simulation share one origin: a shift the loop
      // publishes moves the scene graph the same distance.
      loop.onOriginShift((shift) => _engine?._shiftOrigin(shift));
      final engine = Flutter3dEngine._(
        devices: devices,
        device: device,
        renderer: renderer,
        scene: scene,
        view: CameraView(camera: camera, options: widget.view.render),
        loop: loop,
        simulation: placed.handle,
        log: log,
        backendRefusals: List<String>.unmodifiable(refusals),
        ownsDevice: borrowed == null,
        ownsRenderer: borrowedRenderer == null,
      );
      setState(() => _engine = engine);
      _guarded('onCreated', () => widget.onCreated?.call(engine));
      if (_hasPendingRestore) {
        widget.restoreState?.call(_pendingRestore);
        _hasPendingRestore = false;
        _pendingRestore = null;
      }
      _watchDevice(engine);
      if (widget.xr case final xr?) {
        final driver = XrDriver(
          settings: xr,
          renderer: renderer,
          origin: camera,
          drawPanel: (XrPanelRequest panel) => WidgetTexture(
            device,
          ).draw(panel.widget, width: panel.width, height: panel.height),
        );
        await driver.start(input: loop.input);
        if (!mounted) {
          unawaited(driver.dispose());
          return;
        }
        _xr = driver;
        log.info('started ${xr.session.runtimeName}', source: _source);
      }
      if (widget.view.continuous) _startTicker();
    } on Object catch (error, stack) {
      log.error(
        'the view could not start',
        source: _source,
        error: error,
        stackTrace: stack,
      );
      if (mounted) setState(() => _error = error);
    }
  }

  /// Runs [call], one of the application's callbacks or the loop, and
  /// reports what it throws to the log's crash reporters before it goes on
  /// to Flutter as it would have.
  void _guarded(String what, void Function() call) {
    try {
      call();
    } on Object catch (error, stack) {
      _log.reportCrash(
        error,
        stack,
        source: _source,
        message: '$what threw: $error',
      );
      rethrow;
    }
  }

  static Scene _defaultScene() =>
      Scene()..add(LightNode()..lookAt(Vector3(-0.4, -1.0, -0.6)));

  static CameraNode _defaultCamera() => CameraNode()
    ..setPosition(0.0, 1.0, 5.0)
    ..lookAt(Vector3.zero());

  /// Links the scene's pipelines a slice at a time once the view has been
  /// laid out at [width] by [height] device pixels, so the first frames of
  /// play do not stall on each material's first draw; the frames drawn
  /// meanwhile are ordinary ones.
  void _warmUp(Flutter3dEngine engine, int width, int height) {
    if (!widget.view.warmUp) return;
    final views = widget.view.views ?? <CameraView>[engine.view];
    // The slices yield through a timer; run in a zone that keeps the one
    // pending, so a view that goes mid-way stops the warm-up there rather
    // than letting its next slice draw with a disposed renderer (and leave
    // a timer behind it).
    final yielding = ZoneSpecification(
      createTimer:
          (
            Zone self,
            ZoneDelegate parent,
            Zone zone,
            Duration duration,
            void Function() callback,
          ) {
            if (_warmUpStopped) return _StoppedTimer();
            return _warmUpYield = parent.createTimer(zone, duration, () {
              _warmUpYield = null;
              callback();
            });
          },
    );
    unawaited(
      runZoned(
        () => engine.renderer.warmUpInSlices(
          width: width,
          height: height,
          scene: engine.scene,
          views: views,
          settings: widget.view.settings,
          onProgress: (double done) {
            if (mounted) widget.view.onWarmUpProgress?.call(done);
          },
        ),
        zoneSpecification: yielding,
      ).then(
        (_) => engine.log.debug('warm-up done', source: _source),
        onError: (Object error, StackTrace stack) => engine.log.warning(
          'the warm-up stopped; the rest links on first draw',
          source: _source,
          error: error,
          stackTrace: stack,
        ),
      ),
    );
  }

  /// Follows [engine]'s device: what is done when it is lost, and when it
  /// comes back.
  void _watchDevice(Flutter3dEngine engine) {
    unawaited(_losses?.cancel());
    _losses = engine.device.lost.listen(
      (DeviceLoss loss) => unawaited(_onLoss(engine, loss)),
    );
  }

  Future<void> _onLoss(Flutter3dEngine engine, DeviceLoss loss) async {
    if (!mounted) return;
    if (loss.restored) {
      engine.log.info('the device came back', source: _source);
      // The same device, with every resource it held gone: a renderer over
      // it again, and the plugins installed again on that.
      _recover(engine);
      return;
    }
    engine.log.warning(
      'the device was lost: ${loss.reason}'
      '${loss.isRecoverable ? ', waiting for it' : ' for good'}',
      source: _source,
    );
    setState(() => engine._loss = loss);
    widget.device.onDeviceLost?.call(
      DeviceLostEvent(engine: engine, loss: loss),
    );
    if (loss.isRecoverable) return;
    // For good. A device the view opened is opened again from the same
    // registry; a borrowed one is its owner's, and so is the failure.
    if (!engine.ownsDevice || !engine.ownsRenderer) {
      engine.log.error('a borrowed device was lost for good', source: _source);
      setState(() => _error = loss);
      return;
    }
    try {
      final device = await engine.devices.open(width: 1280, height: 720);
      if (!mounted) {
        device.dispose();
        return;
      }
      engine._device = device;
      _watchDevice(engine);
      _recover(engine);
    } on Object catch (error, stack) {
      engine.log.error(
        'no device would open again',
        source: _source,
        error: error,
        stackTrace: stack,
      );
      if (mounted) setState(() => _error = error);
    }
  }

  /// A renderer over [engine]'s device as it is now, taking over the old
  /// one's steps, and the loop's plugins switched off and on again at the
  /// next step boundary so what they add is made on it. The old renderer is
  /// dropped rather than disposed: what it held went with the device, and
  /// giving it back to a device that no longer has it is not a call to make.
  void _recover(Flutter3dEngine engine) {
    if (!engine.ownsRenderer) {
      // A borrowed renderer is its owner's to make again.
      setState(() => _error = engine._loss ?? 'the device was lost');
      return;
    }
    final plugins = engine.loop.plugins;
    final enabled = <String>[
      for (final id in plugins.order)
        if (plugins.isEnabled(id)) id,
    ];
    for (final id in enabled.reversed) {
      plugins.disable(id);
    }
    engine._renderer = Renderer.create(
      device: engine.device,
      replacing: engine.renderer,
    );
    for (final id in enabled) {
      plugins.enable(id);
    }
    setState(() => engine._loss = null);
    widget.device.onDeviceRestored?.call(engine);
  }

  void _startTicker() {
    _ticker ??= createTicker(_tick);
    if (!_ticker!.isActive) {
      // A ticker counts from nought each time it starts: carry on the one
      // clock the cadence reads from where it stopped, so it neither waits
      // for the old count nor hands the source the time the view was away.
      // The source itself is not reset; a log goes on where it was.
      _ticks = _vsync;
      _ticker!.start();
    }
  }

  void _tick(Duration elapsed) {
    final engine = _engine;
    if (engine == null) return;
    final vsync = _vsync = _ticks + elapsed;
    // A cap of nought or less is none, and a display that says nought hertz
    // does not know its rate: the cadence measures it from the timestamps.
    final cap = widget.view.frameRateCap;
    final hertz = View.maybeOf(context)?.display.refreshRate;
    _cadence
      ..cap = cap != null && cap > 0.0 && cap.isFinite ? cap : null
      ..refreshRate = hertz != null && hertz > 0.0 && hertz.isFinite
          ? hertz
          : null;
    if (_paused) {
      // Counted as drawn against a clock that stands still, so the time away
      // is handed to nothing: not to the loop when the view comes back, and
      // not out of a log or a hand-moved clock while nobody watches.
      _cadence.due(vsync, clock: const _StandingStill());
      return;
    }
    // A refresh the cap skips is not drawn, and the next frame drawn asks
    // the source for all the time since the last one. With a session the
    // runtime decides instead: a frame is drawn when it hands one, and
    // brings the gap between its display times.
    final xr = _xr;
    if (xr != null && xr.beginFrame(engine.loop.input) == null) return;
    final seconds = xr != null
        ? xr.time.elapsed(
            _xrSpan
              ..from = vsync
              ..to = vsync,
          )
        : _cadence.due(vsync);
    if (seconds == null) return;
    final frame = EngineFrame(
      engine: engine,
      frame: FrameInfo(seconds: seconds, result: _drawn),
    );
    _guarded('onBeforeFrame', () => widget.onBeforeFrame?.call(frame));
    _guarded('the loop', () {
      engine.loop.frame(seconds);
      // A simulation placed apart is stepped by the same seconds, so it
      // pauses with the view and runs no faster than the frames.
      _placed?.advance(seconds);
    });
    // What an isolate published arrives between frames; what the loop here
    // published, during this one. Either way the widgets hear it once.
    engine._republish();
    _guarded('onFrame', () => widget.onFrame?.call(frame));
    _followCamera(engine);
    final listener = widget.onListenerMoved;
    if (listener != null) {
      final m = engine.camera.worldMatrix.storage;
      listener(
        ListenerPose(
          position: engine.camera.worldPosition,
          forward: Vector3(-m[8], -m[9], -m[10])..normalize(),
          up: Vector3(m[4], m[5], m[6])..normalize(),
          origin: engine.scene.origin,
        ),
      );
    }
    setState(() {});
  }

  /// Moves the origin to the camera when it has wandered further than
  /// [LoopSettings.originShift] from it — through the loop, whose hooks move
  /// the bodies and, through [Flutter3dEngine._shiftOrigin], the scene.
  /// Rounded to whole metres, as `Scene.rebaseAround` rounds, so a shift
  /// moves nothing by a fraction float32 would round.
  void _followCamera(Flutter3dEngine engine) {
    final beyond = widget.loop.originShift;
    if (beyond == null) return;
    final at = engine.camera.worldPosition;
    if (at.distanceSquaredTo(engine.scene.origin) <= beyond * beyond) return;
    engine.loop.shiftOrigin(
      WorldPosition(
        at.x.roundToDouble(),
        at.y.roundToDouble(),
        at.z.roundToDouble(),
      ),
    );
  }

  void _updatePaused() {
    final paused = !_shown || !_foreground;
    if (paused == _paused) return;
    _paused = paused;
    _engine?.loop.isPaused = paused;
    if (paused && widget.restorationId != null) {
      final save = widget.saveState;
      if (save != null) _saved.value = jsonEncode(save());
    }
    widget.onPausedChanged?.call(paused);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shown = TickerMode.valuesOf(context).enabled;
    _updatePaused();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updatePaused();
  }

  @override
  void didUpdateWidget(Flutter3dView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.time, oldWidget.time)) {
      _cadence.time = widget.time ?? const TimeSource.realTime();
    }
    if (_engine == null) return;
    if (widget.view.continuous) {
      _startTicker();
    } else {
      _ticker?.stop();
    }
  }

  @override
  void dispose() {
    _warmUpStopped = true;
    _warmUpYield?.cancel();
    _warmUpYield = null;
    unawaited(_losses?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.dispose();
    unawaited(_xr?.dispose());
    unawaited(_placed?.dispose());
    _engine?._dispose();
    _ownFocus?.dispose();
    _saved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final view = widget.view;
    if (error != null) {
      return view.failure?.call(error) ??
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: Text(
                Flutter3dAppLocalizations.of(context).viewDidNotStart(error),
              ),
            ),
          );
    }
    final engine = _engine;
    if (engine == null || engine.loss != null) return view.placeholder;
    final presenter = widget.device.presenter;
    final picture = Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: (FocusNode node, KeyEvent event) =>
          widget.onKeyEvent?.call(event) ?? KeyEventResult.ignored,
      child: Listener(
        onPointerDown: (_) => _focus.requestFocus(),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final size = constraints.biggest.isFinite
                ? constraints.biggest
                : Size.zero;
            final ratio = view.resolution.pixelRatioFor(
              MediaQuery.devicePixelRatioOf(context),
              size,
            );
            final width = (size.width * ratio).round();
            final height = (size.height * ratio).round();
            if (!_laidOut && width > 0 && height > 0) {
              _laidOut = true;
              // After this frame: the warm-up's first slice is not this
              // frame's work.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && identical(_engine, engine)) {
                  _warmUp(engine, width, height);
                }
              });
            }
            // A session's eyes, once its first frame has placed them; the
            // view's own until then.
            final eyes = _xr?.views ?? const <CameraView>[];
            final views = eyes.isNotEmpty ? eyes : view.views;
            return SceneSurface(
              renderer: engine.renderer,
              scene: engine.scene,
              view: views?.first ?? engine.view,
              moreViews: views?.skip(1).toList() ?? const <CameraView>[],
              settings: () => eyes.length > 1
                  ? widget.view.settings.forStereo()
                  : widget.view.settings,
              onBeforeFrame: () {},
              onFrame: (FrameInfo frame) {
                _drawn = frame.result;
                final xr = _xr;
                if (xr != null) unawaited(xr.endFrame());
              },
              presentFrame:
                  presenter ??
                  (
                    GraphicsDevice device,
                    TextureHandle frame, {
                    BoxFit fit = BoxFit.fill,
                    FilterQuality quality = FilterQuality.none,
                  }) => presentFrame(
                    device,
                    frame,
                    fit: fit,
                    quality: quality,
                    registry: engine.devices,
                  ),
              pixelRatio: ratio,
            );
          },
        ),
      ),
    );
    if (engine.backendRefusals.isEmpty ||
        !widget.device.fallbackBanner ||
        _bannerClosed) {
      return picture;
    }
    return Stack(
      textDirection: TextDirection.ltr,
      children: <Widget>[
        Positioned.fill(child: picture),
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          child: _FallbackBanner(
            device: engine.device,
            onClose: () => setState(() => _bannerClosed = true),
          ),
        ),
      ],
    );
  }
}

/// What a [Flutter3dView] shows over its picture when the backend it
/// preferred would not start and another one draws: which one, and how to
/// get the GPU back. Closed by a tap on its cross.
final class _FallbackBanner extends StatelessWidget {
  const _FallbackBanner({required this.device, required this.onClose});

  final GraphicsDevice device;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final words = Flutter3dAppLocalizations.of(context);
    const foreground = Color(0xFFFFFFFF);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xCC8A4B00),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  words.drawingWithFallback('${device.runtimeType}'),
                  style: const TextStyle(color: foreground, fontSize: 13),
                ),
              ),
              Semantics(
                button: true,
                label: words.close,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      '✕',
                      style: TextStyle(color: foreground, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A particle system an engine moves with its scene's origin: the system's
/// registration on the scene drawn now, and how many
/// [Flutter3dEngine.followOrigin] registrations hold it.
final class _Follower {
  _Follower(this.onScene);

  Registration onScene;
  int holders = 0;
}

/// The clock a paused view counts its refreshes against: no time passes.
final class _StandingStill extends TimeSource {
  const _StandingStill();

  @override
  double elapsed(FrameSpan span) => 0.0;
}

/// What the warm-up's zone hands out once the view has gone: a timer that
/// never fires, so the slice after it never runs.
final class _StoppedTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}
