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

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show DeviceLoss, DeviceRegistry;
import 'package:flutter3d_particles/flutter3d_particles.dart'
    show ParticleSystem;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        Flutter3dPlugin,
        FormatRegistry,
        FormatSpec,
        OriginShifted,
        PluginRegistry,
        Registration,
        VmExtensions;
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show EngineLoop, FrameCadence, InputState, WorldTiming, simFormats;

import '../backend_native.dart'
    if (dart.library.js_interop) '../backend_web.dart'
    show platformDevices, presentFrame;
import '../l10n/app_localizations.dart';
import '../surface/scene_surface.dart';
import 'frame_info.dart';

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
    required this.ownsDevice,
    required this.ownsRenderer,
    // A named parameter may not be private, and the two are replaced after
    // a device loss, so they are fields behind getters.
    // ignore: prefer_initializing_formals
  }) : _device = device,
       // ignore: prefer_initializing_formals
       _renderer = renderer;

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
  final RenderView view;

  /// The loop: systems, plugins, input and the fixed step, advanced once a
  /// frame while the view is shown and the application in the foreground.
  final EngineLoop loop;

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
/// [EngineLoop] with [plugins], draws [scene] through a [RenderView], and
/// owns focus, input, lifecycle and teardown — item 25 of the 1.0 scope.
/// `SceneSurface` stays as the low level it is built on.
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
/// **Ownership.** A [device] or [renderer] handed in is borrowed and left
/// alone at dispose; one the view opened or made it disposes, with the view
/// and the loop's plugins. See [Flutter3dEngine].
class Flutter3dView extends StatefulWidget {
  /// A view of [scene] (a new, empty one by default) through [camera] (one
  /// at `(0, 1, 5)` looking at the origin by default).
  const Flutter3dView({
    super.key,
    this.scene,
    this.camera,
    this.onCreated,
    this.onBeforeFrame,
    this.onFrame,
    this.plugins = const <Flutter3dPlugin>[],
    this.formats = const <FormatSpec>[],
    this.registries = const <PluginRegistry>[],
    this.settings = const RenderSettings(),
    this.viewOptions = const RenderViewSettings(),
    this.timing = const WorldTiming(),
    this.input,
    this.drainLook,
    this.device,
    this.renderer,
    this.devices,
    this.focusNode,
    this.autofocus = false,
    this.onKeyEvent,
    this.resolution = ViewResolution.native,
    this.restorationId,
    this.saveState,
    this.restoreState,
    this.onPausedChanged,
    this.onListenerMoved,
    this.placeholder = const SizedBox.expand(),
    this.failure,
    this.views,
    this.continuous = true,
    this.frameRateCap,
    this.originShift = defaultOriginShift,
    this.presenter,
    this.onDeviceLost,
    this.onDeviceRestored,
  });

  /// The world to draw; null makes an empty one, with a light.
  final Scene? scene;

  /// The camera to draw through; null makes one.
  final CameraNode? camera;

  /// Called once, when the device is open and the engine made: where a
  /// first scene adds its meshes, and a game its systems.
  final void Function(Flutter3dEngine engine)? onCreated;

  /// Called every frame the view draws, after the loop has stepped and
  /// before the frame is drawn, with the engine and the frame: the seconds
  /// since the last ([FrameInfo.seconds]) and what the renderer answered
  /// for the frame before ([FrameInfo.result]).
  ///
  /// The engine is the context every callback of this view is handed first,
  /// as [onDeviceLost] is; what is said about the frame is one [FrameInfo],
  /// so it can say more without breaking a handler.
  final void Function(Flutter3dEngine engine, FrameInfo frame)? onFrame;

  /// Called every frame the view draws, with the engine and the frame (see
  /// [onFrame]), before the loop steps: where a game reads a device that is
  /// polled, a gamepad, and decides whether the loop is paused this frame
  /// (`engine.loop.isPaused`), so the frame that reads a press is the frame
  /// it acts in.
  final void Function(Flutter3dEngine engine, FrameInfo frame)? onBeforeFrame;

  /// The plugins the loop installs, in order, with the renderer's steps as
  /// one of their registries.
  final Iterable<Flutter3dPlugin> plugins;

  /// Formats beyond the engine's own for the loop's `FormatRegistry`: a
  /// game's (`gameFormats` from `flutter3d_game`) and the application's.
  /// The registry always holds `coreFormats` and `simFormats`, and a plugin
  /// registers its own into it.
  final Iterable<FormatSpec> formats;

  /// The application's own registries, handed to the loop ahead of the
  /// view's. A registry is found by its type, so a `FormatRegistry` or a
  /// `VmExtensions` here is used in place of the one the view would build.
  final Iterable<PluginRegistry> registries;

  /// What every frame is drawn with.
  final RenderSettings settings;

  /// The view's own options: a visibility hook, a label.
  final RenderViewSettings viewOptions;

  /// The loop's fixed step.
  final WorldTiming timing;

  /// The input the loop reads; null makes one.
  final InputState? input;

  /// The view movement a game's devices gathered since the last call, added
  /// into `out`: the loop's `EngineLoop.drainLook`, spread over the frame's
  /// steps and written onto the tape with them. Null drains nothing.
  final void Function(Vector2 out)? drainLook;

  /// A device to borrow instead of opening one.
  final GraphicsDevice? device;

  /// A renderer to borrow instead of making one; it must be over [device].
  final Renderer? renderer;

  /// Where to open the device from; null uses this platform's backends, in
  /// a registry of this view's own.
  final DeviceRegistry? devices;

  /// The view's focus node; null makes one.
  final FocusNode? focusNode;

  /// Whether the view takes focus when it is first shown. False by default.
  final bool autofocus;

  /// Key events while the view has focus.
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;

  /// How many device pixels the view draws per logical pixel.
  final ViewResolution resolution;

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

  /// What shows while the device opens.
  final Widget placeholder;

  /// What shows when no device would open; null shows
  /// [Flutter3dAppLocalizations.viewDidNotStart] with the reason.
  final Widget Function(Object error)? failure;

  /// Several views drawn into one frame, each in its own viewport fraction —
  /// a stereo pair, a split screen — in place of the one through [camera].
  ///
  /// Null, the default, draws [Flutter3dEngine.view]. Given, it holds one
  /// view or more and is read on every frame, so a caller may fit the
  /// views' projections to the size it is laid out at; the views are the
  /// caller's, and the view leaves them undisposed. [onListenerMoved] still
  /// follows [camera].
  final List<RenderView>? views;

  /// Whether the view draws a frame on every display refresh, stepping the
  /// loop before each. True by default. False draws a frame only when the
  /// view is built again — a still picture whose parent rebuilds it when
  /// something changed — and steps nothing between.
  final bool continuous;

  /// Frames a second this view is drawn at most, held to a whole number of
  /// the display's refreshes — `A1.5`: sixty on a 120 Hz screen is every
  /// other refresh. The loop steps by all the time since the last drawn
  /// frame. Null, the default, draws on every refresh, and so does a cap of
  /// nought or less.
  final double? frameRateCap;

  /// How far, in metres, the camera may wander from the origin before the
  /// view moves the origin to it; null leaves the origin where the game puts
  /// it. [defaultOriginShift], a kilometre, by default.
  ///
  /// **Precision is the camera's, not the origin's.** A scene's nodes, the
  /// GPU and the simulation's bodies hold float32 offsets from one origin,
  /// and float32 has a millimetre between neighbours at about 8 km and
  /// half a metre at 4000 km. So after each frame, when the camera stands
  /// further than this from the origin, the view calls
  /// `EngineLoop.shiftOrigin` with the camera's place rounded to whole
  /// metres: the loop's hooks move the bodies (`EngineLoop.shiftsPhysics`),
  /// the scene its nodes and the particles that follow it, and nothing
  /// moves in the world. What is near the camera is then near the origin,
  /// wherever in the world it is.
  ///
  /// **What the game holds in the old frame stays there.** A game that
  /// copies its bodies' float32 positions onto nodes each frame registers
  /// its world with `EngineLoop.shiftsPhysics`, so the bodies move with the
  /// shift; one that does not would draw them a kilometre off after it, and
  /// passes null here until it does.
  ///
  /// The shift happens between steps, at the view's camera, which is not on
  /// a run's tape: a game that records runs for replay and moves far shifts
  /// the origin from inside a step itself, and passes null here.
  final double? originShift;

  /// How far, in metres, the camera wanders before a [Flutter3dView] moves
  /// the origin to it by default: a kilometre, where float32 still has a
  /// tenth of a millimetre between neighbours.
  static const double defaultOriginShift = 1000.0;

  /// What shows a drawn frame; null presents it through the registry the
  /// device came from ([devices]). A test without a backend passes its own.
  final FramePresenter? presenter;

  /// Told when the device stops working — a WebGL context lost, a WebGPU
  /// device lost — before the view waits for it or opens another. Nothing is
  /// drawn until [onDeviceRestored]; the loop goes on stepping.
  final void Function(Flutter3dEngine engine, DeviceLoss loss)? onDeviceLost;

  /// Told when the engine draws again after a loss: the device came back, or
  /// the view opened a new one from [devices] (only when it opened the first
  /// itself), and the renderer was made again over it with the loop's
  /// plugins installed again. **What the application uploaded is gone with
  /// the old device**: upload the scene's meshes and textures again here,
  /// on `engine.device`. A loss the view cannot recover from — a borrowed
  /// device or renderer lost for good, a device that will not open — shows
  /// [failure] instead.
  final void Function(Flutter3dEngine engine)? onDeviceRestored;

  @override
  State<Flutter3dView> createState() => _Flutter3dViewState();
}

class _Flutter3dViewState extends State<Flutter3dView>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        RestorationMixin {
  Flutter3dEngine? _engine;
  Object? _error;
  Ticker? _ticker;
  Duration _last = Duration.zero;
  bool _shown = true;
  bool _foreground = true;
  bool _paused = false;
  FocusNode? _ownFocus;
  final RestorableStringN _saved = RestorableStringN(null);
  Object? _pendingRestore;
  bool _hasPendingRestore = false;
  StreamSubscription<DeviceLoss>? _losses;
  final FrameCadence _cadence = FrameCadence();
  double _owed = 0.0;

  /// What the renderer answered for the last frame drawn, for
  /// [FrameInfo.result].
  FrameResult? _drawn;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

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
    try {
      final devices = widget.devices ?? platformDevices();
      final borrowed = widget.device;
      final device = borrowed ?? await devices.open(width: 1280, height: 720);
      if (!mounted) {
        if (borrowed == null) device.dispose();
        return;
      }
      final borrowedRenderer = widget.renderer;
      final renderer = borrowedRenderer ?? Renderer.create(device: device);
      final scene = widget.scene ?? _defaultScene();
      final camera = widget.camera ?? _defaultCamera();
      if (camera.parent == null) scene.add(camera);
      final loop = EngineLoop(
        input: widget.input ?? InputState(),
        drainLook: widget.drainLook,
        timing: widget.timing,
        plugins: widget.plugins,
        registries: <PluginRegistry>[
          ...widget.registries,
          renderer.renderSteps,
          // A plugin asks the loop for these by type; without them a format
          // or a VM extension it brings had nowhere to go.
          if (!widget.registries.any((r) => r is FormatRegistry))
            FormatRegistry(<FormatSpec>[
              ...coreFormats,
              ...simFormats,
              ...widget.formats,
            ]),
          if (!widget.registries.any((r) => r is VmExtensions)) VmExtensions(),
          // The physical materials need no line here: the loop installs the
          // built-in `MaterialCatalog` itself, or the one among these.
        ],
      );
      // The picture and the simulation share one origin: a shift the loop
      // publishes moves the scene graph the same distance.
      loop.onOriginShift((shift) => _engine?._shiftOrigin(shift));
      final engine = Flutter3dEngine._(
        devices: devices,
        device: device,
        renderer: renderer,
        scene: scene,
        view: RenderView(camera: camera, options: widget.viewOptions),
        loop: loop,
        ownsDevice: borrowed == null,
        ownsRenderer: borrowedRenderer == null,
      );
      setState(() => _engine = engine);
      widget.onCreated?.call(engine);
      if (_hasPendingRestore) {
        widget.restoreState?.call(_pendingRestore);
        _hasPendingRestore = false;
        _pendingRestore = null;
      }
      _watchDevice(engine);
      if (widget.continuous) _startTicker();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  static Scene _defaultScene() =>
      Scene()..add(LightNode()..lookAt(Vector3(-0.4, -1.0, -0.6)));

  static CameraNode _defaultCamera() => CameraNode()
    ..setPosition(0.0, 1.0, 5.0)
    ..lookAt(Vector3.zero());

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
      // The same device, with every resource it held gone: a renderer over
      // it again, and the plugins installed again on that.
      _recover(engine);
      return;
    }
    setState(() => engine._loss = loss);
    widget.onDeviceLost?.call(engine, loss);
    if (loss.isRecoverable) return;
    // For good. A device the view opened is opened again from the same
    // registry; a borrowed one is its owner's, and so is the failure.
    if (!engine.ownsDevice || !engine.ownsRenderer) {
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
    } on Object catch (error) {
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
    widget.onDeviceRestored?.call(engine);
  }

  void _startTicker() {
    _ticker ??= createTicker(_tick);
    if (!_ticker!.isActive) {
      // A ticker counts from nought each time it starts, and the cadence
      // would wait for the old count: forget the last frame it drew.
      _last = Duration.zero;
      _cadence.reset();
      _ticker!.start();
    }
  }

  void _tick(Duration elapsed) {
    final engine = _engine;
    if (engine == null) return;
    _owed += (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_paused) {
      _owed = 0.0;
      return;
    }
    // A refresh the cap skips is not drawn: the time goes on owing, and the
    // next frame drawn steps by all of it. A cap of nought or less is none,
    // and a display that says nought hertz does not know its rate: the
    // cadence measures it from the timestamps.
    final cap = widget.frameRateCap;
    final hertz = View.maybeOf(context)?.display.refreshRate;
    _cadence
      ..cap = cap != null && cap > 0.0 && cap.isFinite ? cap : null
      ..refreshRate = hertz != null && hertz > 0.0 && hertz.isFinite
          ? hertz
          : null;
    if (_cadence.due(elapsed) == null) return;
    final seconds = _owed;
    _owed = 0.0;
    final frame = FrameInfo(seconds: seconds, result: _drawn);
    widget.onBeforeFrame?.call(engine, frame);
    engine.loop.frame(seconds);
    widget.onFrame?.call(engine, frame);
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
  /// [Flutter3dView.originShift] from it — through the loop, whose hooks move
  /// the bodies and, through [Flutter3dEngine._shiftOrigin], the scene.
  /// Rounded to whole metres, as `Scene.rebaseAround` rounds, so a shift
  /// moves nothing by a fraction float32 would round.
  void _followCamera(Flutter3dEngine engine) {
    final beyond = widget.originShift;
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
    if (_engine == null) return;
    if (widget.continuous) {
      _startTicker();
    } else {
      _ticker?.stop();
    }
  }

  @override
  void dispose() {
    unawaited(_losses?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.dispose();
    _engine?._dispose();
    _ownFocus?.dispose();
    _saved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return widget.failure?.call(error) ??
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
    if (engine == null || engine.loss != null) return widget.placeholder;
    final presenter = widget.presenter;
    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: (FocusNode node, KeyEvent event) =>
          widget.onKeyEvent?.call(event) ?? KeyEventResult.ignored,
      child: Listener(
        onPointerDown: (_) => _focus.requestFocus(),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final ratio = widget.resolution.pixelRatioFor(
              MediaQuery.devicePixelRatioOf(context),
              constraints.biggest.isFinite ? constraints.biggest : Size.zero,
            );
            return SceneSurface(
              renderer: engine.renderer,
              scene: engine.scene,
              view: widget.views?.first ?? engine.view,
              moreViews: widget.views?.skip(1).toList() ?? const <RenderView>[],
              settings: () => widget.settings,
              onBeforeFrame: () {},
              onFrame: (FrameInfo frame) => _drawn = frame.result,
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
