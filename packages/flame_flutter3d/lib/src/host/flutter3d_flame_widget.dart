import 'package:flame/game.dart' show FlameGame, GameWidget;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import 'bridge_clock.dart';
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
/// **One clock.** A [BridgeClock] is added to [game] once it loads, and every
/// Flame frame — after every other component in [game] has updated — calls
/// [onTick] with that frame's own `dt`, then triggers a Flutter rebuild so
/// [SceneSurface] renders the 3D frame in step. Nothing here starts a second
/// ticker; see [BridgeClock] for why that matters.
class Flutter3dFlameWidget extends StatefulWidget {
  const Flutter3dFlameWidget({
    super.key,
    required this.game,
    required this.camera,
    required this.buildScene,
    this.existing,
    this.onTick,
    this.clearColor,
    this.settings,
    this.width = 1280,
    this.height = 720,
  });

  /// The Flame game whose [GameWidget] draws the 2D layer. Constructed by
  /// the caller — this widget only adds one [BridgeClock] to it, once.
  final FlameGame game;

  /// The camera the 3D layer renders through. Added to the built [Scene]
  /// automatically if [buildScene] did not already add it.
  final CameraNode camera;

  /// Builds the 3D scene once a [GraphicsDevice] is open. Called exactly
  /// once, the same contract `flutter3d_app`'s own examples use.
  final Scene Function(GraphicsDevice device) buildScene;

  /// A device and renderer opened by the caller, reused instead of this
  /// widget opening its own. A host that already has one — a page inside a
  /// larger application, say, where `DemoContext` hands one out per page —
  /// opening a second `GraphicsDevice` just to show a bridged demo would be
  /// two GPU contexts open for one picture. `openDevice` runs only when this
  /// is null.
  final ({GraphicsDevice device, Renderer renderer})? existing;

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

  /// The [GraphicsDevice]'s own backing size — not this widget's size on
  /// screen, which `SceneSurface` already resizes the render target to
  /// independently of this.
  final int width;
  final int height;

  @override
  State<Flutter3dFlameWidget> createState() => _Flutter3dFlameWidgetState();
}

class _Flutter3dFlameWidgetState extends State<Flutter3dFlameWidget> {
  late final RenderView _view = RenderView(
    camera: widget.camera,
    clearColor: widget.clearColor ?? Vector4(0.05, 0.05, 0.07, 1.0),
  );

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
    final existing = widget.existing;
    if (existing != null) {
      // Already open: build the scene synchronously rather than through the
      // async `openDevice` path nothing here needs a second time.
      final scene = widget.buildScene(existing.device);
      if (scene.cameras.isEmpty) scene.add(widget.camera);
      _ready = (renderer: existing.renderer, scene: scene);
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
      final scene = widget.buildScene(device);
      if (scene.cameras.isEmpty) scene.add(widget.camera);
      _ownsDevice = true;
      setState(
        () =>
            _ready = (renderer: Renderer.create(device: device), scene: scene),
      );
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
                  settings: widget.settings ?? () => const RenderSettings(),
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
    return _gameWidget = GameWidget<FlameGame>(game: game);
  }
}
