/// The groups a `Flutter3dView` takes its options in: the device, the view,
/// the loop and the plugins.
///
/// **Groups, so the widget can grow.** A view with thirty-four named
/// parameters is a constructor nobody reads, and every one added later makes
/// it longer. Each group is a final, const class with a complete `copyWith`,
/// so an option added in a minor release lands in one group with a default,
/// and a caller that never named it is untouched.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show InputState, SimulationFactory, WorldTiming;

import '../surface/scene_surface.dart' show FramePresenter;
import 'flutter3d_view.dart' show Flutter3dEngine, ViewResolution;

/// Where a `Flutter3dView`'s simulation runs: in the view's own loop, on
/// the thread that draws ([SimulationPlacement.inline]), or in an isolate of
/// its own ([SimulationPlacement.isolate]).
///
/// **An open set**: a later minor may add a placement (a worker of the
/// browser's, a server) without breaking anybody's code, so there is no
/// `switch` to write over it.
final class SimulationPlacement {
  /// In the view's own loop, `Flutter3dEngine.loop`, stepped once a frame
  /// on the thread that draws: the default, and what a game whose systems
  /// `onCreated` adds wants.
  ///
  /// What `Flutter3dEngine.simulation.submit` is handed goes to
  /// [applyInput] at the start of the next step; null drops it, for a game
  /// that writes the loop's `InputState` directly.
  const SimulationPlacement.inline({this.applyInput})
    : factory = null,
      arguments = null,
      debugName = null;

  /// In an isolate spawned for it: [factory], a top-level function or a
  /// static method, builds the loop there from [arguments], which must be
  /// plain values that cross isolates. The view steps it once a frame by
  /// the frame's time (`IsolateSimulation.advance`), so it pauses with the
  /// view, and draws what it publishes (`Flutter3dEngine.simulation`).
  ///
  /// **On the web there is no isolate a package can spawn**, so the same
  /// factory is called in this isolate and its loop stepped by the view, as
  /// `SimulationSetup.local` builds it: one factory, both places, and the
  /// game reads the same handle either way.
  const SimulationPlacement.isolate(
    SimulationFactory this.factory, {
    this.arguments,
    this.debugName,
  }) : applyInput = null;

  /// What builds the simulation where it runs; null for
  /// [SimulationPlacement.inline], which runs in the view's own loop.
  final SimulationFactory? factory;

  /// The plain values [factory] is handed.
  final Object? arguments;

  /// The isolate's name in a debugger.
  final String? debugName;

  /// Inline, what `Flutter3dEngine.simulation.submit` hands on: told each
  /// input and its seat ([SeatInput]) at the start of the next step. Null
  /// drops them.
  final void Function(SeatInput input)? applyInput;

  @override
  String toString() => factory == null
      ? 'SimulationPlacement.inline'
      : 'SimulationPlacement.isolate';
}

/// The device a `Flutter3dView` draws with: one to borrow or where to open
/// one, what shows its frames, and what is done when it is lost.
final class DeviceSettings {
  const DeviceSettings({
    this.device,
    this.renderer,
    this.devices,
    this.presenter,
    this.fallbackBanner = true,
    this.onDeviceLost,
    this.onDeviceRestored,
  });

  /// A device to borrow instead of opening one.
  final GraphicsDevice? device;

  /// A renderer to borrow instead of making one; it must be over [device].
  final Renderer? renderer;

  /// Where to open the device from; null uses this platform's backends, in
  /// a registry of this view's own.
  final DeviceRegistry? devices;

  /// What shows a drawn frame; null presents it through the registry the
  /// device came from ([devices]). A test without a backend passes its own.
  final FramePresenter? presenter;

  /// Whether the view says so on screen when the backend it preferred would
  /// not start and another draws instead — Impeller off, so the frames come
  /// from the software rasteriser. True by default: a picture drawn on the
  /// CPU looks like a slow game, and nobody finds the switch from that. The
  /// banner can be closed; the engine's log has the reasons either way.
  final bool fallbackBanner;

  /// Told when the device stops working — a WebGL context lost, a WebGPU
  /// device lost — before the view waits for it or opens another. Nothing is
  /// drawn until [onDeviceRestored]; the loop goes on stepping.
  final void Function(DeviceLostEvent event)? onDeviceLost;

  /// Told when the engine draws again after a loss: the device came back, or
  /// the view opened a new one from [devices] (only when it opened the first
  /// itself), and the renderer was made again over it with the loop's
  /// plugins installed again. **What the application uploaded is gone with
  /// the old device**: upload the scene's meshes and textures again here,
  /// on `engine.device`. A loss the view cannot recover from — a borrowed
  /// device or renderer lost for good, a device that will not open — shows
  /// the view's failure instead.
  final void Function(Flutter3dEngine engine)? onDeviceRestored;

  /// A copy with the fields given replaced; a `clear…` flag sets that field
  /// back to null.
  DeviceSettings copyWith({
    GraphicsDevice? device,
    Renderer? renderer,
    DeviceRegistry? devices,
    FramePresenter? presenter,
    bool? fallbackBanner,
    void Function(DeviceLostEvent event)? onDeviceLost,
    void Function(Flutter3dEngine engine)? onDeviceRestored,
    bool clearDevice = false,
    bool clearRenderer = false,
    bool clearDevices = false,
    bool clearPresenter = false,
    bool clearOnDeviceLost = false,
    bool clearOnDeviceRestored = false,
  }) => DeviceSettings(
    device: clearDevice ? null : device ?? this.device,
    renderer: clearRenderer ? null : renderer ?? this.renderer,
    devices: clearDevices ? null : devices ?? this.devices,
    presenter: clearPresenter ? null : presenter ?? this.presenter,
    fallbackBanner: fallbackBanner ?? this.fallbackBanner,
    onDeviceLost: clearOnDeviceLost ? null : onDeviceLost ?? this.onDeviceLost,
    onDeviceRestored: clearOnDeviceRestored
        ? null
        : onDeviceRestored ?? this.onDeviceRestored,
  );
}

/// What a `Flutter3dView` draws and how: the frame's settings, the view's
/// own, the resolution, when it draws, and what shows instead.
final class ViewSettings {
  const ViewSettings({
    this.settings = const RenderSettings(),
    this.render = const RenderViewSettings(),
    this.resolution = ViewResolution.native,
    this.views,
    this.continuous = true,
    this.frameRateCap,
    this.placeholder = const SizedBox.expand(),
    this.failure,
    this.warmUp = true,
    this.onWarmUpProgress,
  });

  /// What every frame is drawn with.
  final RenderSettings settings;

  /// The view's own settings: a visibility hook, a label.
  final RenderViewSettings render;

  /// How many device pixels the view draws per logical pixel.
  final ViewResolution resolution;

  /// Several views drawn into one frame, each in its own viewport fraction —
  /// a stereo pair, a split screen — in place of the one through the view's
  /// camera.
  ///
  /// Null, the default, draws `Flutter3dEngine.view`. Given, it holds one
  /// view or more and is read on every frame, so a caller may fit the
  /// views' projections to the size it is laid out at; the views are the
  /// caller's, and the view leaves them undisposed. `onListenerMoved` still
  /// follows the camera.
  final List<RenderView>? views;

  /// Whether the view draws a frame on every display refresh, stepping the
  /// loop before each. True by default. False draws a frame only when the
  /// view is built again — a still picture whose parent rebuilds it when
  /// something changed — and steps nothing between.
  final bool continuous;

  /// Frames a second this view is drawn at most, held to a whole number of
  /// the display's refreshes: sixty on a 120 Hz screen is every other
  /// refresh. The loop steps by all the time since the last drawn frame.
  /// Null, the default, draws on every refresh, and so does a cap of nought
  /// or less.
  final double? frameRateCap;

  /// What shows while the device opens.
  final Widget placeholder;

  /// What shows when no device would open; null shows
  /// `Flutter3dAppLocalizations.viewDidNotStart` with the reason.
  final Widget Function(Object error)? failure;

  /// Whether the view links the scene's pipelines once the device is open
  /// and the first frame is laid out, a little at a time between frames
  /// (`Renderer.warmUpInSlices`), so the first seconds of play do not stall
  /// on each material's first draw. True by default; what `onCreated` added
  /// is what gets linked.
  final bool warmUp;

  /// Told the share of the warm-up done, from just above nought to one:
  /// what a loading bar over the view draws.
  final void Function(double done)? onWarmUpProgress;

  /// A copy with the fields given replaced; a `clear…` flag sets that field
  /// back to null.
  ViewSettings copyWith({
    RenderSettings? settings,
    RenderViewSettings? render,
    ViewResolution? resolution,
    List<RenderView>? views,
    bool? continuous,
    double? frameRateCap,
    Widget? placeholder,
    Widget Function(Object error)? failure,
    bool? warmUp,
    void Function(double done)? onWarmUpProgress,
    bool clearViews = false,
    bool clearFrameRateCap = false,
    bool clearFailure = false,
    bool clearOnWarmUpProgress = false,
  }) => ViewSettings(
    settings: settings ?? this.settings,
    render: render ?? this.render,
    resolution: resolution ?? this.resolution,
    views: clearViews ? null : views ?? this.views,
    continuous: continuous ?? this.continuous,
    frameRateCap: clearFrameRateCap ? null : frameRateCap ?? this.frameRateCap,
    placeholder: placeholder ?? this.placeholder,
    failure: clearFailure ? null : failure ?? this.failure,
    warmUp: warmUp ?? this.warmUp,
    onWarmUpProgress: clearOnWarmUpProgress
        ? null
        : onWarmUpProgress ?? this.onWarmUpProgress,
  );
}

/// How a `Flutter3dView`'s loop runs: its step, its input, its profile,
/// where the simulation is, and when the origin follows the camera.
final class LoopSettings {
  const LoopSettings({
    this.timing = const WorldTiming(),
    this.input,
    this.drainLook,
    this.originShift = defaultOriginShift,
    this.simulation = const SimulationPlacement.inline(),
    this.profile = SimulationProfile.deterministic,
  });

  /// How far, in metres, the camera wanders before the view moves the
  /// origin to it by default: a kilometre, where float32 still has a tenth
  /// of a millimetre between neighbours.
  static const double defaultOriginShift = 1000.0;

  /// The loop's fixed step.
  final WorldTiming timing;

  /// The input the loop reads; null makes one.
  final InputState? input;

  /// The view movement a game's devices gathered since the last call, added
  /// into `out`: the loop's `EngineLoop.drainLook`, spread over the frame's
  /// steps and written onto the tape with them. Null drains nothing.
  final void Function(Vector2 out)? drainLook;

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
  /// moves in the world.
  ///
  /// **What the game holds in the old frame stays there.** A game that
  /// copies its bodies' float32 positions onto nodes each frame registers
  /// its world with `EngineLoop.shiftsPhysics`, so the bodies move with the
  /// shift; one that does not passes null here until it does.
  ///
  /// The shift happens between steps, at the view's camera, which is not on
  /// a run's tape: a game that records runs for replay and moves far shifts
  /// the origin from inside a step itself, and passes null here.
  final double? originShift;

  /// Where the simulation runs: [SimulationPlacement.inline], the default,
  /// or [SimulationPlacement.isolate].
  final SimulationPlacement simulation;

  /// What the view's own loop promises about its numbers:
  /// [SimulationProfile.deterministic], the one a game is played on, by
  /// default; [SimulationProfile.accurate] runs a laboratory in the view
  /// without an isolate. The loop hands it to every plugin and names it in
  /// its `simulationVersion`.
  ///
  /// The view's loop is the one it steps inline. A simulation placed with
  /// [SimulationPlacement.isolate] builds its own loop in its factory and
  /// says its profile there.
  final SimulationProfile profile;

  /// A copy with the fields given replaced; a `clear…` flag sets that field
  /// back to null.
  LoopSettings copyWith({
    WorldTiming? timing,
    InputState? input,
    void Function(Vector2 out)? drainLook,
    double? originShift,
    SimulationPlacement? simulation,
    SimulationProfile? profile,
    bool clearInput = false,
    bool clearDrainLook = false,
    bool clearOriginShift = false,
  }) => LoopSettings(
    timing: timing ?? this.timing,
    input: clearInput ? null : input ?? this.input,
    drainLook: clearDrainLook ? null : drainLook ?? this.drainLook,
    originShift: clearOriginShift ? null : originShift ?? this.originShift,
    simulation: simulation ?? this.simulation,
    profile: profile ?? this.profile,
  );
}

/// What a `Flutter3dView`'s loop installs and the registries it hands them.
final class PluginSettings {
  const PluginSettings({
    this.plugins = const <Flutter3dPlugin>[],
    this.formats = const <FormatSpec>[],
    this.registries = const <PluginRegistry>[],
  });

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

  /// A copy with the fields given replaced.
  PluginSettings copyWith({
    Iterable<Flutter3dPlugin>? plugins,
    Iterable<FormatSpec>? formats,
    Iterable<PluginRegistry>? registries,
  }) => PluginSettings(
    plugins: plugins ?? this.plugins,
    formats: formats ?? this.formats,
    registries: registries ?? this.registries,
  );
}

/// What `SimulationPlacement.inline`'s `applyInput` is told: one input a
/// game submitted, and the [seat] it came from.
///
/// **One object, so a later minor can say more** (the step it was submitted
/// at, the player behind the seat) without breaking a handler.
final class SeatInput {
  /// [input] from [seat].
  const SeatInput({required this.seat, required this.input});

  /// The seat that submitted it: nought for a game of one.
  final int seat;

  /// What was submitted, as `Flutter3dEngine.simulation.submit` was handed
  /// it.
  final Object? input;
}

/// What `DeviceSettings.onDeviceLost` is told: the [engine] whose device
/// stopped working, and the [loss].
///
/// **One object, so a later minor can say more** (what the view will try
/// next) without breaking a handler.
final class DeviceLostEvent {
  /// [engine]'s device was lost, as [loss] says.
  const DeviceLostEvent({required this.engine, required this.loss});

  /// The engine of the view that lost its device.
  final Flutter3dEngine engine;

  /// Why, as the backend said.
  final DeviceLoss loss;
}
