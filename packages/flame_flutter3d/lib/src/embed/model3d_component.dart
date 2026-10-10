import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show protected, visibleForTesting;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart' show openDevice;

import '../animation/model_animation_component.dart';
import 'frame_image.dart';

/// A 3D model drawn into its own rectangle of a plain Flame game: a
/// [PositionComponent] like any other, with no 3D layer and no host widget.
///
/// ```dart
/// world.add(Model3dComponent(
///   model: 'assets/models/skeleton.glb',
///   position: Vector2(200, 300),
///   size: Vector2.all(256),
///   priority: 5,
/// ));
/// ```
///
/// **Drawn in Flame's canvas, so it sits in Flame's order.** The model is
/// rendered into a texture the size of the component on screen and painted
/// in [render], which puts it in front of whatever has a lower priority and
/// behind whatever has a higher one: a skeleton between a parallax backdrop
/// and a sprite walking past it. Position, size, anchor, angle, scale and
/// the Flame camera's zoom apply to it as to a sprite. The bridge proper,
/// [Flutter3dFlameWidget] with [HasFlutter3d], draws one whole 3D world
/// under the 2D layer instead, and is what a game set in 3D wants.
///
/// **How the picture reaches the canvas depends on the backend.** On
/// Impeller the frame becomes a `ui.Image` over the texture it was drawn
/// into, with no copy. On WebGL, WebGPU and the software rasteriser the
/// frame is read back and decoded, which costs a copy of the component's
/// pixels each frame and shows the picture one frame late; a few hundred
/// pixels square is cheap, a full-screen model is not.
///
/// **The model loads itself.** [model] is read with `loadModelByPath`,
/// uploaded, put in a [scene] of its own and framed by [camera3d] from
/// [viewFrom]. A model with clips plays [animation], or its first clip, on
/// Flame's clock, so it stops when the game is paused. A subclass that
/// wants something other than one model in a scene overrides [buildScene].
///
/// **One device per game, one renderer per component.** Every
/// [Model3dComponent] in a game draws on the device the first one opened,
/// and the last one removed closes it. Each keeps its own [Renderer],
/// because a renderer's targets are sized to what it draws, and two models
/// of different sizes sharing one would reallocate them twice a frame. A
/// [device] passed in is used instead and is never closed here.
class Model3dComponent extends PositionComponent {
  Model3dComponent({
    this.model,
    this.animation,
    GraphicsDevice? device,
    this.pixelRatio,
    Vector3? viewFrom,
    super.position,
    super.size,
    super.scale,
    super.angle,
    super.anchor,
    super.children,
    super.priority,
    super.key,
  }) : _givenDevice = device,
       viewFrom = viewFrom ?? Vector3(0.6, 0.4, 1.0);

  /// The model file, by the path `loadModelByPath` reads: a bundled
  /// `assets/...glb`, or a source under `assets_src/` the build hook
  /// converts. Null for a subclass whose [buildScene] makes its own.
  final String? model;

  /// The clip to loop, by name; null plays the model's first clip, if it
  /// has any.
  final String? animation;

  /// Physical pixels per logical pixel of the texture the model is drawn
  /// into; null reads the display's own. Lower is softer and cheaper, which
  /// is the knob to turn where the frame is read back.
  final double? pixelRatio;

  /// Which side the camera looks from, in the model's space: front and a
  /// little above and to the right by default. Only the direction counts;
  /// the distance is whatever fits the model in the component.
  final Vector3 viewFrom;

  final GraphicsDevice? _givenDevice;

  /// The scene the model stands in, lit by the renderer's default key light
  /// and a softer ambient than the engine's own default.
  final Scene scene = Scene(name: 'Model3dComponent')
    ..ambientIntensity = 0.3 * Photometric.legacyUnit;

  /// The camera [render] draws through, placed by [frameModel].
  late final CameraNode camera3d = scene.add(CameraNode(name: 'model3d eye'));

  /// What one frame of [scene] is drawn with. Its clear colour is
  /// transparent, so the 2D game shows round the model.
  late final RenderView view = RenderView(
    camera: camera3d,
    clearColorSrgb: Vector4.zero(),
  );

  /// The loaded model, once [onLoad] has finished; null for a subclass
  /// that built its own scene.
  ModelInstance? get instance => _instance;
  ModelInstance? _instance;
  ModelAsset? _asset;

  /// The model's clips on Flame's clock, when it has any.
  ModelAnimationComponent? get animations => _animations;
  ModelAnimationComponent? _animations;

  /// The device this component draws on, once loaded.
  GraphicsDevice get device => _device!;
  GraphicsDevice? _device;
  FlameGame? _sharedFrom;
  Renderer? _renderer;

  /// The bounds [frameModel] last framed, kept to frame again when the
  /// component changes shape.
  Aabb3? _framed;
  double _framedAspect = 0.0;

  /// How a game's shared device is opened: `flutter3d_app`'s `openDevice`,
  /// or a test's software device.
  @visibleForTesting
  static Future<GraphicsDevice> Function({
    required int width,
    required int height,
  })
  openSharedDevice = openDevice;

  /// The picture [render] paints, or null before the first frame arrives.
  @visibleForTesting
  ui.Image? get frameImage => _image;
  ui.Image? _image;
  bool _due = true;
  bool _reading = false;
  final ui.Paint _paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;

  /// Fills [scene]: loads [model], places it, frames it and starts its
  /// animation. A subclass may add to the scene after calling this, or
  /// replace it altogether and call [frameModel] itself.
  @protected
  Future<void> buildScene(GraphicsDevice device) async {
    final path = model;
    if (path == null) return;
    final asset = _asset = await ModelAsset.fromDocument(
      await loadModelByPath(path),
      device: device,
      name: path,
    );
    final instance = _instance = asset.instantiate(scene);
    frameModel(asset.localBounds);
    final player = instance.player;
    if (player != null && asset.clips.isNotEmpty) {
      add(
        _animations = ModelAnimationComponent(
          player,
          start: animation ?? asset.clips.first.name,
        ),
      );
    }
  }

  /// Points [camera3d] at [bounds] from [viewFrom], close enough that the
  /// whole box fits the component at its current shape.
  void frameModel(Aabb3 bounds) {
    _framed = bounds;
    final aspect = size.y > 0.0 ? size.x / size.y : 1.0;
    _framedAspect = aspect;
    final center = bounds.center;
    final radius = math.max(bounds.max.distanceTo(bounds.min) / 2.0, 1e-3);
    const fovY = math.pi / 4.0;
    // The narrower of the two angles decides: a tall component is limited
    // by its width.
    final halfFov = math.min(
      fovY / 2.0,
      math.atan(math.tan(fovY / 2.0) * aspect),
    );
    final distance = radius / math.sin(halfFov);
    final eye = center + viewFrom.normalized() * distance;
    camera3d
      ..projection = PerspectiveProjection(
        fovY: fovY,
        near: math.max(distance - radius * 2.0, distance * 0.01),
        far: distance + radius * 2.0,
      )
      ..setPosition(eye.x, eye.y, eye.z)
      ..lookAt(center);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await _open();
  }

  /// Takes a device and fills the scene, the first time and again after
  /// [onRemove] let them go.
  Future<void> _open() async {
    final device = _device = _givenDevice ?? await _acquire();
    await buildScene(device);
    _renderer = Renderer.create(device: device);
    _due = true;
  }

  Future<GraphicsDevice> _acquire() {
    final game = _sharedFrom = findGame()!;
    final shared = _devices[game] ??= _SharedDevice(
      openSharedDevice(width: 256, height: 256),
    );
    shared.users++;
    return shared.opening;
  }

  @override
  void onMount() {
    super.onMount();
    // Added again after a removal let everything go.
    if (isLoaded && _renderer == null) unawaited(_open());
  }

  @override
  void onRemove() {
    _image?.dispose();
    _image = null;
    _renderer?.dispose();
    _renderer = null;
    _animations?.removeFromParent();
    _animations = null;
    _instance?.root.removeFromParent();
    _instance = null;
    _asset?.dispose();
    _asset = null;
    _device = null;
    final game = _sharedFrom;
    _sharedFrom = null;
    if (game != null) _release(game);
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _due = true;
  }

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    final renderer = _renderer;
    if (renderer != null && _due && !_reading && !size.isZero()) {
      _due = false;
      _draw(renderer, canvas);
    }
    final image = _image;
    if (image == null) return;
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      size.toRect(),
      _paint,
    );
  }

  void _draw(Renderer renderer, ui.Canvas canvas) {
    final framed = _framed;
    final aspect = size.x / size.y;
    if (framed != null && aspect != _framedAspect) frameModel(framed);
    // The canvas's own scale: the component's, its parents' and the Flame
    // camera's zoom, so a zoomed-in model is drawn at the size it is shown.
    final m = canvas.getTransform();
    final zoom = math.sqrt(m[0] * m[0] + m[1] * m[1]);
    final ratio =
        (pixelRatio ??
            ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
            1.0) *
        zoom;
    final frame = renderer
        .render(
          width: (size.x * ratio).clamp(1.0, 4096.0).round(),
          height: (size.y * ratio).clamp(1.0, 4096.0).round(),
          scene: scene,
          views: <RenderView>[view],
        )
        .frame;
    final now = frameImageNow(renderer.device, frame);
    if (now != null) {
      _show(now);
    } else {
      unawaited(_readBack(renderer, frame));
    }
  }

  /// The frame's pixels, copied back and decoded: the path every backend
  /// but Impeller takes. Nothing is drawn while one is under way, so the
  /// renderer never reuses the texture being read.
  Future<void> _readBack(Renderer renderer, TextureHandle frame) async {
    _reading = true;
    try {
      final bytes = await renderer.device.readback(frame);
      if (!identical(renderer, _renderer)) return;
      final decoded = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        frame.width,
        frame.height,
        ui.PixelFormat.rgba8888,
        decoded.complete,
      );
      final image = await decoded.future;
      if (!identical(renderer, _renderer)) return image.dispose();
      _show(image);
    } finally {
      _reading = false;
    }
  }

  /// Closing the image shown before is safe once a newer one replaces it:
  /// a picture already recorded holds its own reference.
  void _show(ui.Image image) {
    _image?.dispose();
    _image = image;
  }
}

/// A device opened for the [Model3dComponent]s of one game, and how many of
/// them are using it.
final class _SharedDevice {
  _SharedDevice(this.opening);

  final Future<GraphicsDevice> opening;
  int users = 0;
}

final Expando<_SharedDevice> _devices = Expando<_SharedDevice>(
  'Model3dComponent device',
);

void _release(FlameGame game) {
  final shared = _devices[game];
  if (shared == null || --shared.users > 0) return;
  _devices[game] = null;
  unawaited(
    shared.opening.then(
      (GraphicsDevice device) => device.dispose(),
      onError: (Object _) {},
    ),
  );
}
