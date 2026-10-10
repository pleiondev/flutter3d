import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../scene/camera_node.dart';
import '../scene/mesh_node.dart';
import 'render_settings.dart';

/// How a sub-list of draws is ordered.
///
/// Modes rather than one hardcoded policy: the right order
/// depends on what is being drawn, and the caller knows that better than the
/// renderer does.
enum SortMode {
  /// Group by pipeline, then material, then near-to-far. The default for opaque
  /// geometry: it minimises pipeline changes, which here are the most
  /// expensive state change there is.
  stateThenDepth,

  /// Far-to-near. Required for correct alpha blending.
  backToFront,

  /// Near-to-far, to let early-z reject more fragments.
  frontToBack,

  /// Respect only `RenderMaterial.drawBucket`, leaving the rest in submission order.
  manual,

  /// Submission order.
  none,
}

/// One camera drawing into one target, as an object that lives across frames
/// — item 26 of the 1.0 scope.
///
/// **What a view owns.** Its [camera], where it draws ([texture], or the
/// frame's surface when that is null), its own settings and visibility hook
/// in [options], and what a frame remembers for the next one: the temporal
/// resolve's history, the reprojection's last view-projection and the
/// effects carried across frames. Those are kept by the renderer **per
/// view**, not per renderer and not per [CameraNode], so two views of one
/// camera — a stereo pair, an editor's viewports, a picture-in-picture —
/// each keep their own and none blends another's last frame into its own.
/// What is shared is everything that is not about one view: pipelines,
/// meshes, textures, the shadow maps of a frame.
///
/// **Two kinds of target.**
///
///  * The surface: `Renderer.render` draws every surface view of the call
///    into the frame it hands back, each into its [viewportFraction] of it —
///    a split screen is two views. This is what the constructor makes.
///  * A texture: [RenderView.texture] makes a view that draws into a texture
///    of its own, for a material to show — a security monitor, a portal, a
///    minimap. Added to a scene with `Scene.addTextureView`, it is drawn
///    every frame (or once, see [RenderViewSettings.refreshEveryFrame]) with
///    the scene's lights and shadows, before the scene that shows it. It is
///    what `RenderTexture` was before 1.0.
///
/// **Owned by whoever made it**, and released with [dispose]: the texture
/// of a texture view and the history every renderer kept for it.
///
/// The fields a frame reads directly — [camera], [viewportFraction],
/// [layerMask], [priority], [clearColorSrgb], the two sorts and [cut] — stay
/// mutable fields, as they were on the descriptor this grew from; anything
/// added from 1.0 on arrives in [options], so the constructor does not grow.
final class RenderView {
  /// A view of [camera] onto the frame's surface.
  RenderView({
    required this.camera,
    this.viewportFraction = const ViewportRect(0.0, 0.0, 1.0, 1.0),
    this.layerMask = ~0,
    this.priority = 0,
    Vector4? clearColorSrgb,
    this.opaqueSort = SortMode.stateThenDepth,
    this.transparentSort = SortMode.backToFront,
    this.cut = false,
    this.options = const RenderViewSettings(),
  }) : clearColorSrgb = clearColorSrgb ?? Vector4(0.055, 0.062, 0.078, 1.0),
       _texture = null,
       _device = null;

  /// A view of [camera] into a texture of [width] × [height] of its own, made
  /// on [device] — what `RenderTexture.create` made before 1.0.
  ///
  /// [texture] holds sRGB bytes, the way a picture loaded from a file does,
  /// so it goes into a material's albedo or emissive slot as one. The light
  /// is multiplied by [RenderViewSettings.exposure] and clipped at one; tone
  /// mapping is left to the frame that shows it. Its first row is the top of
  /// the picture on every backend, as an uploaded image's is.
  ///
  /// Drawn by the same pass as a planar reflection's: the scene's meshes
  /// with the frame's lights and shadows and its sky, before the frame's own
  /// scene, with no post chain and nothing a contributor draws.
  factory RenderView.texture(
    GraphicsDevice device, {
    required CameraNode camera,
    required int width,
    required int height,
    int layerMask = ~0,
    Vector4? clearColorSrgb,
    RenderViewSettings options = const RenderViewSettings(),
  }) {
    if (width < 1 || height < 1) {
      throw ArgumentError(
        'a texture view of ${width}x$height has no pixels to draw into; ask '
        'for at least one each way',
      );
    }
    return RenderView._texture(
      device,
      device.createTexture(
        RenderTargetDescriptor(
          width: width,
          height: height,
          format: TextureFormat.r8g8b8a8UNormInt,
        ),
      ),
      camera: camera,
      layerMask: layerMask,
      clearColorSrgb: clearColorSrgb ?? Vector4(0.055, 0.062, 0.078, 1.0),
      options: options,
    );
  }

  RenderView._texture(
    GraphicsDevice this._device,
    TextureHandle this._texture, {
    required this.camera,
    required this.layerMask,
    required this.clearColorSrgb,
    required this.options,
  }) : viewportFraction = const ViewportRect(0.0, 0.0, 1.0, 1.0),
       priority = 0,
       opaqueSort = SortMode.stateThenDepth,
       transparentSort = SortMode.backToFront,
       cut = false;

  /// Whether this frame is a cut: the camera jumped rather than moved, and
  /// nothing the temporal resolve remembers is worth keeping — `R2`. Set for
  /// the one frame after a jump and cleared again; a cut every frame is a
  /// resolve that never resolves anything.
  bool cut;

  /// Where the view looks from, with its own projection; the aspect is the
  /// view's own rectangle's.
  CameraNode camera;

  /// Normalized rectangle within the target. Fractions rather
  /// than pixels so a view survives a resize unchanged. A texture view
  /// covers its whole texture.
  ViewportRect viewportFraction;

  /// Nodes are drawn only where `node.layerMask & view.layerMask != 0`.
  int layerMask;

  /// Views are rendered in ascending priority: a lower number draws first.
  int priority;

  /// What shows where nothing was drawn and the sky is off, sRGB-encoded:
  /// the numbers a colour picker shows, which the renderer decodes once.
  ///
  /// **`Srgb` in the name** because every other colour the engine takes is
  /// linear (docs/CONTRACTS.md, "Linear unless the name says sRGB"). It was
  /// `clearColor` before 1.0. A linear colour goes in through
  /// `LinearColor.toSrgb`.
  Vector4 clearColorSrgb;

  /// How the opaque draws are ordered.
  SortMode opaqueSort;

  /// How the transparent draws are ordered.
  SortMode transparentSort;

  /// Everything about this view that is not one of the fields above, as one
  /// value — replaced whole, `view.options = view.options.copyWith(...)`.
  RenderViewSettings options;

  final TextureHandle? _texture;
  final GraphicsDevice? _device;

  /// What a texture view draws into; null for a view of the surface.
  TextureHandle? get texture => _texture;

  /// Whether this view draws into a [texture] of its own — what a caller
  /// holding views of both kinds asks before reading [texture].
  bool get isTextureView => _texture != null;

  /// The size of [texture], or zero for a surface view (its size is the
  /// frame's).
  int get width => _texture?.width ?? 0;

  /// See [width].
  int get height => _texture?.height ?? 0;

  /// Meshes this view leaves out — the screen showing a texture view's
  /// picture, most often, which would otherwise show itself.
  final Set<MeshNode> excluded = <MeshNode>{};

  /// Whether this view is drawn this frame: [RenderViewSettings.visible]
  /// asked, or true when there is no hook.
  bool get isVisible => options.visible?.call() ?? true;

  /// Asks for a texture view's picture to be drawn again on the next frame.
  void invalidate() => _generation++;

  int _generation = 0;
  int _drawnGeneration = -1;

  /// Whether [texture] holds a picture rather than an allocation's contents.
  bool get isDrawn => _drawnGeneration >= 0;

  /// Whether the next frame has to draw this texture view.
  bool get isDue =>
      options.refreshEveryFrame || _drawnGeneration != _generation;

  /// Called by the renderer once the picture is in [texture].
  void markDrawn() => _drawnGeneration = _generation;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  final List<void Function()> _onDispose = <void Function()>[];

  /// Gives back what this view owns: the history each renderer kept for it
  /// and, for a texture view, its [texture]. A disposed view is not drawn
  /// again; a second call does nothing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final release in List<void Function()>.of(_onDispose)) {
      release();
    }
    _onDispose.clear();
    final texture = _texture;
    if (texture != null) _device?.releaseTexture(texture);
  }
}

/// What a renderer keeps per view: called by the renderer, not an
/// application. Not exported by `flutter3d_core.dart`.
extension RenderViewInternals on RenderView {
  /// Runs [release] when the view is disposed — how a renderer gives back
  /// the history textures it kept for this view.
  void whenDisposed(void Function() release) => _onDispose.add(release);
}

/// The settings of one [RenderView] that are not its camera, target or
/// rectangle — the object its growing parameters go into, so that adding one
/// in a minor release changes no constructor.
///
/// Immutable; [copyWith] makes the next one.
final class RenderViewSettings {
  /// Options with every default: the frame's own settings, always visible,
  /// redrawn every frame, at an exposure of one.
  const RenderViewSettings({
    this.settings,
    this.visible,
    this.refreshEveryFrame = true,
    this.exposure = 1.0,
    this.label,
  });

  /// This view's own settings, in place of the ones the frame was rendered
  /// with; null uses the frame's. Read for a texture view, and for a
  /// surface view drawn alone (the first view of a `render` call decides the
  /// frame's).
  final RenderSettings? settings;

  /// The visibility hook: asked before each frame, and a view that answers
  /// false is not drawn and keeps its history for when it is again — a
  /// minimap behind a closed panel, a monitor in a room nobody is in.
  /// Null is always visible.
  final bool Function()? visible;

  /// For a texture view: whether every frame draws it again. False draws it
  /// once and then only after `RenderView.invalidate`: a portrait of a room
  /// nobody changes is one picture, not sixty a second.
  final bool refreshEveryFrame;

  /// For a texture view: what the light is multiplied by before it is
  /// clipped and encoded.
  /// A linear multiplier.
  final double exposure;

  /// A name for a GPU debugger, a capture and the frame's report.
  final String? label;

  /// These options with the given fields replaced. [settings], [visible]
  /// and [label] are reset to null by passing [clearSettings],
  /// [clearVisible] or [clearLabel].
  RenderViewSettings copyWith({
    RenderSettings? settings,
    bool Function()? visible,
    bool? refreshEveryFrame,
    double? exposure,
    String? label,
    bool clearSettings = false,
    bool clearVisible = false,
    bool clearLabel = false,
  }) => RenderViewSettings(
    settings: clearSettings ? null : settings ?? this.settings,
    visible: clearVisible ? null : visible ?? this.visible,
    refreshEveryFrame: refreshEveryFrame ?? this.refreshEveryFrame,
    exposure: exposure ?? this.exposure,
    label: clearLabel ? null : label ?? this.label,
  );
}

/// Normalized viewport rectangle.
///
/// A local type rather than `dart:ui`'s `Rect`, so the render layer stays free of
/// Flutter's UI library and remains usable from a plain Dart test. Named
/// distinctly on purpose: `Rect` would collide with Flutter's in every file that
/// imports both.
final class ViewportRect {
  /// Fractions of the target, so every one of these belongs in `[0, 1]` and
  /// the rectangle has to stay inside it.
  ///
  /// Asserted rather than clamped, and rather than nothing — which is what it
  /// was. A rectangle running off the attachment is clipped by the driver, so
  /// it produces a picture rather than an error, and a different picture on
  /// each backend: the split-screen that is half off the bottom looks like a
  /// layout bug in the application and is a value nobody checked.
  const ViewportRect(this.x, this.y, this.width, this.height)
    : assert(x >= 0.0 && x <= 1.0, 'x is a fraction of the target'),
      assert(y >= 0.0 && y <= 1.0, 'y is a fraction of the target'),
      assert(width > 0.0 && width <= 1.0, 'width is a fraction, and not zero'),
      assert(
        height > 0.0 && height <= 1.0,
        'height is a fraction, and not zero',
      ),
      assert(x + width <= 1.0, 'the viewport runs off the right of the target'),
      assert(
        y + height <= 1.0,
        'the viewport runs off the bottom of the target',
      );

  /// Left edge, a 0..1 fraction of the target's width.
  final double x;

  /// Top edge, a 0..1 fraction of the target's height.
  final double y;

  /// A 0..1 fraction of the target's width.
  final double width;

  /// A 0..1 fraction of the target's height.
  final double height;

  /// Whether this viewport is the whole target.
  ///
  /// Nothing here asks: the engine sets the viewport either way and lets the
  /// hardware clip. It is for a caller writing a pass of its own that has a
  /// faster path when it owns the whole target — a full-target clear, or a blit
  /// that can skip the scissor — and needs to know which case it is in.
  bool get isFullTarget =>
      x == 0.0 && y == 0.0 && width == 1.0 && height == 1.0;

  @override
  String toString() => 'ViewportRect($x, $y, $width, $height)';
}
