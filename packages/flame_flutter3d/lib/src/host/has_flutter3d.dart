import 'package:flame/game.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter3d/flutter3d.dart' hide Material;

import '../transform/projector.dart';

/// A [FlameGame] that owns its 3D world: the scene, the camera it is seen
/// through, the renderer that draws it and the projector between the two
/// layers, all reachable from inside the game.
///
/// **What a bridged game had to be told from outside.** Without this, the
/// device and the scene arrived in a `buildScene` callback written in the
/// app's `main.dart`, the renderer in a second callback, and everything the
/// game needed of them (a projector for a score over a target, a renderer to
/// let a mesh go through, a chase camera to shake) was handed back to it by
/// hand, in an order the app had to get right. River Sortie's `main.dart`
/// was mostly that wiring. With this mixin the game builds its own world in
/// [onOpen3d], and `Flutter3dFlameWidget(game: game)` needs nothing else.
///
/// **The background is transparent**, as [TransparentFlameGame]'s is: the
/// 3D layer is under Flame's, and an opaque background hides it.
///
/// ## When the world is there
///
/// [open3d] is what opens it: `Flutter3dFlameWidget` calls it once its
/// device is open, which is before Flame loads the game, so [scene] and
/// [device] are there from [onLoad] on. A test with no widget calls it
/// itself, with a software device, before or after loading the game; either
/// way [onOpen3d] runs once, when the game has loaded and the world exists
/// to be built on.
mixin HasFlutter3d on FlameGame {
  /// The camera the 3D layer is drawn through. Made by [createCamera3d] the
  /// first time it is read.
  late final CameraNode camera3d = createCamera3d();

  /// Makes [camera3d]. Override to choose the lens.
  CameraNode createCamera3d() => CameraNode(name: 'camera 3d');

  /// Between [camera3d] and Flame's screen, over this game's own [size].
  late final BridgeProjector projector = BridgeProjector(
    camera: camera3d,
    viewSize: () => size,
  );

  /// Behind everything the 3D layer draws. The same vector every frame, so
  /// changing its components changes the sky on the next one.
  final Vector4 clearColor = Vector4(0.05, 0.05, 0.07, 1.0);

  /// What each 3D frame is drawn with, read before every frame.
  RenderSettings renderSettings() => const RenderSettings();

  GraphicsDevice? _device;
  Scene? _scene;
  Renderer? _renderer;
  bool _opened = false;
  bool _loaded = false;
  bool _rendererUsed = false;

  /// Whether [open3d] has run: whether there is a [scene] to build on.
  bool get has3d => _scene != null;

  /// The device the 3D layer is open on. Throws before [open3d].
  GraphicsDevice get device =>
      _device ?? (throw StateError('The 3D layer is not open yet.'));

  /// The scene the 3D layer draws, with [camera3d] in it. Throws before
  /// [open3d].
  Scene get scene =>
      _scene ?? (throw StateError('The 3D layer is not open yet.'));

  /// The renderer drawing the 3D layer, once there is one; null in a test
  /// that renders no frames.
  Renderer? get renderer => _renderer;

  /// Opens the 3D world on [device]: [scene], or a new one, with [camera3d]
  /// added to it. Then [onOpen3d], once the game is loaded as well.
  void open3d(GraphicsDevice device, {Scene? scene}) {
    if (_scene != null) {
      throw StateError('The 3D layer is already open.');
    }
    final opened = scene ?? Scene();
    if (!opened.cameras.contains(camera3d)) opened.add(camera3d);
    _device = device;
    _scene = opened;
    _openWhenReady();
  }

  /// Hands over the renderer the 3D layer draws with. Called by
  /// `Flutter3dFlameWidget`, and by a test that renders frames; the game's
  /// own use of it goes in [onRenderer3d].
  void attachRenderer(Renderer renderer) {
    _renderer = renderer;
    _openWhenReady();
  }

  /// Uses the renderer: adds a contributor, hands it to a particle pool.
  /// Runs once, after [onOpen3d], so what that built is there to be given
  /// it. The widget hands the renderer over before Flame has loaded the
  /// game, and a hook called at once met a game with nothing built yet.
  void onRenderer3d(Renderer renderer) {}

  /// Builds the 3D world: runs once, when [open3d] has run and the game has
  /// loaded, in whichever order those came. An override of [onLoad] that
  /// wants the world calls `super.onLoad()` first.
  void onOpen3d() {}

  /// Opens the world after the game's own loading, not on mount: Flame
  /// 1.38 mounts the root game without calling its `onMount`, in a
  /// `GameWidget` and in `flame_test` alike.
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _loaded = true;
    _openWhenReady();
  }

  void _openWhenReady() {
    if (_scene == null || !_loaded) return;
    if (!_opened) {
      _opened = true;
      onOpen3d();
    }
    final drawing = _renderer;
    if (drawing != null && !_rendererUsed) {
      _rendererUsed = true;
      onRenderer3d(drawing);
    }
  }

  @override
  Color backgroundColor() => const Color(0x00000000);
}
