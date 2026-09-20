import 'package:flame/game.dart' show FlameGame, GameWidget;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import 'bridge_clock.dart';

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

  /// Called once a Flame frame, after [game]'s own components have updated,
  /// with that frame's `dt` — the seam a physics step, an actor system step,
  /// or a camera sync controller advances from.
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
  bool _clockAdded = false;

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
      final scene = widget.buildScene(device);
      if (scene.cameras.isEmpty) scene.add(widget.camera);
      if (!mounted) return;
      setState(
        () =>
            _ready = (renderer: Renderer.create(device: device), scene: scene),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// **Deferred to the next frame's start, not called from here directly.**
  /// [BridgeClock.update] fires from inside `GameWidget`'s own `build` — a
  /// `LayoutBuilder` callback — so a `setState` made right here throws
  /// "called during build". A post-frame callback runs once this frame has
  /// finished laying out and painting, which is the earliest a rebuild is
  /// legal; [SceneSurface] then renders one frame behind Flame's own update,
  /// the ordinary cost of two widgets sharing one clock instead of two.
  void _onFlameTick(double dt) {
    widget.onTick?.call(dt);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // Added once the game is actually in a tree Flame can attach a component
    // to, and not again — `GameWidget` may rebuild this state without
    // recreating `widget.game`.
    if (!_clockAdded) {
      _clockAdded = true;
      widget.game.add(BridgeClock(onTick: _onFlameTick));
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
          SceneSurface(
            renderer: renderer,
            scene: scene,
            view: _view,
            settings: widget.settings ?? () => const RenderSettings(),
            onBeforeFrame: () {},
            presentFrame: presentFrame,
          ),
          GameWidget(game: widget.game),
        ],
      ),
    };
  }
}
