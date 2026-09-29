import 'package:flame/game.dart'
    show FlameGame, GameWidget, OverlayWidgetBuilder;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import 'bridge_clock.dart';
import 'has_flutter3d.dart';
import 'transparent_flame_game.dart';

/// A 3D flutter3d layer and a 2D Flame layer, composited in one `Stack`, one
/// frame each.
///
/// **Both engines render their own layer.** [SceneSurface] draws the 3D
/// scene [buildScene] returns; Flame's own [GameWidget] draws [game]. Neither
/// engine's renderer is reimplemented, and neither drives the other's
/// drawing — they sit in one `Stack`, [game]'s [GameWidget] on top, the same
/// arrangement `apps/flutter3d_demo_platformer` already uses for its own HUD
/// and input layer over a bare `SceneSurface`: on the web the 3D surface is a
/// platform view that swallows pointer events, so whatever needs raw input —
/// here, Flame itself — has to sit above it in the tree.
///
/// **[game] must not paint an opaque background.** `GameWidget` paints
/// `game.backgroundColor()` as a `DecoratedBox` behind its own canvas, and
/// `Game.backgroundColor()` defaults to opaque black — which, sitting on top
/// of [SceneSurface] the way this widget arranges the two, draws a solid
/// black rectangle over the whole 3D layer every frame. Extend
/// [TransparentFlameGame] instead of [FlameGame], or override
/// `backgroundColor()` the same way it does.
///
/// **A game that owns its world needs nothing else.** Give [game] the
/// [HasFlutter3d] mixin and pass it alone: its [HasFlutter3d.camera3d] is
/// the camera, [HasFlutter3d.open3d] opens its scene on this widget's
/// device, its renderer is handed to [HasFlutter3d.attachRenderer], and its
/// [HasFlutter3d.renderSettings] and [HasFlutter3d.clearColor] draw the
/// frame. [camera], [buildScene], [settings], [clearColor] and
/// [onRendererReady] are for a game without it, and override it where given.
///
/// **One clock.** A [BridgeClock] is added to [game] once it loads, and every
/// Flame frame — after every other component in [game] has updated — calls
/// [onTick] with that frame's own `dt`, then triggers a Flutter rebuild so
/// [SceneSurface] renders the 3D frame in step. Nothing here starts a second
/// ticker; see [BridgeClock] for why that matters.
class Flutter3dFlameWidget extends StatefulWidget {
  const Flutter3dFlameWidget({
    super.key,
    required this.game,
    this.camera,
    this.buildScene,
    this.existing,
    this.onRendererReady,
    this.onTick,
    this.clearColor,
    this.settings,
    this.width = 1280,
    this.height = 720,
    this.overlayBuilderMap,
    this.initialActiveOverlays,
    this.focusNode,
    this.autofocus = true,
  }) : assert(
         game is HasFlutter3d || (camera != null && buildScene != null),
         'A game without HasFlutter3d needs a camera and a buildScene.',
       );

  /// The Flame game whose [GameWidget] draws the 2D layer. Constructed by
  /// the caller — this widget only adds one [BridgeClock] to it, once.
  final FlameGame game;

  /// The camera the 3D layer renders through. Added to the built [Scene]
  /// automatically if [buildScene] did not already add it. Null for a
  /// [HasFlutter3d] game, whose [HasFlutter3d.camera3d] it is.
  final CameraNode? camera;

  /// Builds the 3D scene once a [GraphicsDevice] is open. Called exactly
  /// once, the same contract `flutter3d_app`'s own examples use. Null for a
  /// [HasFlutter3d] game, which builds its own in [HasFlutter3d.onOpen3d].
  final Scene Function(GraphicsDevice device)? buildScene;

  /// A device and renderer opened by the caller, reused instead of this
  /// widget opening its own. A host that already has one — a page inside a
  /// larger application, say, where `DemoContext` hands one out per page —
  /// opening a second `GraphicsDevice` just to show a bridged demo would be
  /// two GPU contexts open for one picture. `openDevice` runs only when this
  /// is null.
  final ({GraphicsDevice device, Renderer renderer})? existing;

  /// Called once with the [Renderer] the 3D layer draws with, as soon as
  /// there is one: after [buildScene], whether this widget opened the device
  /// or was handed [existing].
  ///
  /// **For what a game has to ask the renderer itself**: letting go of a
  /// mesh it streamed in (`Renderer.releaseMeshAfterFrame`), adding a
  /// contributor that draws particles. Without it a bridged game saw the
  /// device in [buildScene] and never the renderer, which this widget made
  /// and kept.
  final void Function(Renderer renderer)? onRendererReady;

  /// Called every time Flame updates [game], after its own components have,
  /// with that update's `dt`: the seam a physics step, an actor system step,
  /// or a camera sync controller advances from.
  ///
  /// **Once a frame, and occasionally with a `dt` of zero.** `GameWidget`
  /// calls `update(0)` from its own layout whenever it is rebuilt: on its
  /// first frame, and when its size changes. This widget no longer rebuilds
  /// it every frame, but a step that divides by `dt` should still ignore a
  /// zero.
  final void Function(double dt)? onTick;

  /// The 3D layer's clear color, behind whatever [buildScene] draws.
  final Vector4? clearColor;

  /// What the 3D layer's frame is drawn with. Re-read every frame, after
  /// [onTick] — the same contract `SceneSurface.settings` already has.
  final RenderSettings Function()? settings;

  /// Flame's overlays: Flutter widgets over the game, shown and hidden by
  /// name through `game.overlays`. Handed to the `GameWidget` as they are.
  ///
  /// **What a bridged game had to build a second `Stack` for.** A pause
  /// menu or a name entry over the 3D layer is what `GameWidget` already
  /// does with these; the host did not pass them on.
  final Map<String, OverlayWidgetBuilder<FlameGame>>? overlayBuilderMap;

  /// The overlays shown from the start.
  final List<String>? initialActiveOverlays;

  /// The focus the game's keyboard listens through, for a host that moves
  /// focus between the game and its own widgets.
  final FocusNode? focusNode;

  /// Whether the game takes the keyboard focus when it appears.
  final bool autofocus;

  /// The [GraphicsDevice]'s own backing size — not this widget's size on
  /// screen, which `SceneSurface` already resizes the render target to
  /// independently of this.
  final int width;
  final int height;

  @override
  State<Flutter3dFlameWidget> createState() => _Flutter3dFlameWidgetState();
}

class _Flutter3dFlameWidgetState extends State<Flutter3dFlameWidget> {
  /// The game, when it owns its world.
  HasFlutter3d? get _owner => switch (widget.game) {
    final HasFlutter3d owner => owner,
    _ => null,
  };

  CameraNode get _camera => widget.camera ?? _owner!.camera3d;

  late RenderView _view = _viewFor();

  RenderView _viewFor() => RenderView(
    camera: _camera,
    clearColor:
        widget.clearColor ??
        _owner?.clearColor ??
        Vector4(0.05, 0.05, 0.07, 1.0),
  );

  /// **A new camera or a new clear colour is used.** Both went into the view
  /// once, when this state was made, and a rebuild that handed in a
  /// different camera, or a sky for the next level, changed nothing on
  /// screen.
  @override
  void didUpdateWidget(Flutter3dFlameWidget old) {
    super.didUpdateWidget(old);
    if (!identical(old.camera, widget.camera) ||
        old.clearColor != widget.clearColor ||
        !identical(old.game, widget.game)) {
      final scene = _ready?.scene;
      final camera = _camera;
      if (scene != null && !scene.cameras.contains(camera)) scene.add(camera);
      _view = _viewFor();
    }
  }

  /// The scene on [device]: built by [Flutter3dFlameWidget.buildScene] when
  /// given, opened by the game when it owns its world.
  Scene _sceneOn(GraphicsDevice device) {
    final build = widget.buildScene;
    if (build != null) {
      final scene = build(device);
      if (scene.cameras.isEmpty) scene.add(_camera);
      final owner = _owner;
      if (owner != null && !owner.has3d) owner.open3d(device, scene: scene);
      return scene;
    }
    final owner = _owner!;
    if (!owner.has3d) owner.open3d(device);
    return owner.scene;
  }

  void _rendererReady(Renderer renderer) {
    _owner?.attachRenderer(renderer);
    widget.onRendererReady?.call(renderer);
  }

  RenderSettings Function() get _settings =>
      widget.settings ?? _owner?.renderSettings ?? () => const RenderSettings();

  ({Renderer renderer, Scene scene})? _ready;
  Object? _error;

  /// The clock added to [Flutter3dFlameWidget.game], and the game it was
  /// added to, so a new game passed in by a rebuild gets its own and the
  /// old one stops calling back here.
  ({FlameGame game, BridgeClock clock})? _clocked;

  /// Whether this state opened the device and renderer in [_ready] itself,
  /// and so has to release them. Not when they came in through
  /// [Flutter3dFlameWidget.existing]: those belong to the caller.
  bool _ownsDevice = false;

  /// Bumped once a Flame update to redraw the 3D layer, and nothing else.
  ///
  /// **Only the 3D layer is rebuilt each frame.** A `setState` here used to
  /// rebuild the whole `Stack`, `GameWidget` with it, and `GameWidget` calls
  /// `game.update(0)` from its own layout whenever it is rebuilt, so every
  /// frame the game was updated twice, [BridgeClock] fired twice and
  /// `onTick` saw a second call with a `dt` of zero.
  final ValueNotifier<int> _frames = ValueNotifier<int>(0);

  /// The `GameWidget`, made once per game and handed back unchanged, so a
  /// rebuild of this widget from above (a HUD beside it calling `setState`,
  /// say) does not rebuild Flame's own widget either.
  GameWidget<FlameGame>? _gameWidget;

  @override
  void initState() {
    super.initState();
    assert(() {
      // Not an assert that throws: a game that means to cover the 3D layer
      // is allowed to, and one that does not is told why the screen is one
      // colour.
      if (widget.game.backgroundColor().a > 0.0) {
        debugPrint(
          'Flutter3dFlameWidget: ${widget.game.runtimeType} paints an opaque '
          'background over the 3D layer, which will not be seen. Mix in '
          'HasFlutter3d, extend TransparentFlameGame, or return a clear '
          'colour from backgroundColor().',
        );
      }
      return true;
    }());
    final existing = widget.existing;
    if (existing != null) {
      // Already open: build the scene synchronously rather than through the
      // async `openDevice` path nothing here needs a second time.
      final scene = _sceneOn(existing.device);
      _ready = (renderer: existing.renderer, scene: scene);
      _rendererReady(existing.renderer);
    } else {
      _open();
    }
  }

  Future<void> _open() async {
    try {
      final device = await openDevice(
        width: widget.width,
        height: widget.height,
      );
      if (!mounted) return device.dispose();
      final scene = _sceneOn(device);
      _ownsDevice = true;
      final renderer = Renderer.create(device: device);
      setState(() => _ready = (renderer: renderer, scene: scene));
      _rendererReady(renderer);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// **Deferred to a post-frame callback, and still in step.** A rebuild
  /// asked for while a build or a layout is under way throws "called during
  /// build", so it is asked for once this frame is done, and only of the 3D
  /// layer ([_frames]). That does
  /// not put the 3D layer a frame behind, though this comment used to say it
  /// did. The callback only marks this state dirty; the next frame runs its
  /// transient callbacks first, and Flame's game loop is a `Ticker` among
  /// them, so [BridgeClock.update] has already moved the game to that frame
  /// when the build reaches [SceneSurface], which renders from its own
  /// `LayoutBuilder`. Both layers paint the same update while the ticker
  /// runs. A game stepped by hand while paused (`stepEngine`) updates
  /// outside a frame, and there the 3D layer does follow a frame later.
  void _onFlameTick(double dt) {
    widget.onTick?.call(dt);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) _frames.value++;
    });
  }

  /// **Releases what it opened.** A device this state opened is closed with
  /// it, renderer first; one passed in through
  /// [Flutter3dFlameWidget.existing] is left to its owner. The clock is
  /// taken off the game too, which may outlive this widget: a game kept
  /// across a route change, say, would otherwise go on calling back into a
  /// disposed state.
  @override
  void dispose() {
    _clocked?.clock.removeFromParent();
    _frames.dispose();
    final ready = _ready;
    if (_ownsDevice && ready != null) {
      ready.renderer.dispose();
      ready.renderer.device.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Added once per game, not once per build: `GameWidget` may rebuild
    // this state without recreating `widget.game`, and a rebuild from above
    // may hand in a different game, whose clock then replaces the old one's.
    final clocked = _clocked;
    if (clocked == null || !identical(clocked.game, widget.game)) {
      clocked?.clock.removeFromParent();
      final clock = BridgeClock(onTick: _onFlameTick);
      widget.game.add(clock);
      _clocked = (game: widget.game, clock: clock);
    }

    return switch ((_error, _ready)) {
      (final Object error, _) => DidNotStart(
        error,
        background: const Color(0xFF14161A),
        foreground: const Color(0xFFFF8A80),
      ),
      (_, null) => const ColoredBox(
        color: Color(0xFF14161A),
        child: Center(child: CircularProgressIndicator()),
      ),
      (_, (:final renderer, :final scene)?) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ValueListenableBuilder<int>(
            valueListenable: _frames,
            builder: (BuildContext context, int frame, Widget? child) =>
                SceneSurface(
                  renderer: renderer,
                  scene: scene,
                  view: _view,
                  settings: _settings,
                  onBeforeFrame: () {},
                  presentFrame: presentFrame,
                ),
          ),
          _gameWidgetFor(widget.game),
        ],
      ),
    };
  }

  GameWidget<FlameGame> _gameWidgetFor(FlameGame game) {
    final GameWidget<FlameGame>? made = _gameWidget;
    if (made != null && identical(made.game, game)) return made;
    return _gameWidget = GameWidget<FlameGame>(
      game: game,
      overlayBuilderMap: widget.overlayBuilderMap,
      initialActiveOverlays: widget.initialActiveOverlays,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
    );
  }
}
