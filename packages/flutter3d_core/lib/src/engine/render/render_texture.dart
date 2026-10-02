import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../scene/camera_node.dart';
import '../scene/mesh_node.dart';

/// A camera that draws into a texture rather than onto the screen — `P4`:
/// a security monitor, a portal, a minimap, a mirror at an angle no plane
/// would give.
///
/// **The same pass as a planar reflection's**, pointed through an ordinary
/// camera instead of a mirrored one: the scene's meshes with the frame's
/// lights and shadows, its sky behind them, drawn before the frame's own
/// scene so a material can show the picture in the same frame it was taken.
/// No post chain runs on it, and nothing a contributor draws — particles,
/// splats — is in it.
///
/// [texture] holds sRGB bytes, the way a picture loaded from a file does, so
/// it goes into a material's albedo or emissive slot as one: an unlit quad
/// shows exactly what the camera saw, and a lit one shows it lit again, like
/// a printed photograph. The light is multiplied by [exposure] and clipped
/// at one; tone mapping is left to the frame that shows it, which would
/// otherwise apply it twice. Its first row is the top of the picture on
/// every backend, as an uploaded image's is, so a mesh shows it the right
/// way up where it would show a photograph the right way up: a
/// `PlaneShape` stood up, yes; the sides of a `CuboidShape`, whose v runs
/// up, no.
///
/// Owned by whoever made it: add it to a scene with
/// `Scene.addRenderTexture` to have it drawn, and give [texture] back with
/// `Renderer.releaseTextureAfterFrame` when it is done with.
final class RenderTexture {
  /// A texture of [width] × [height] for [camera] to draw into, made on
  /// [device].
  factory RenderTexture.create(
    GraphicsDevice device, {
    required CameraNode camera,
    required int width,
    required int height,
    int layerMask = ~0,
    Vector4? clearColor,
    double exposure = 1.0,
    bool refreshEveryFrame = true,
  }) {
    if (width < 1 || height < 1) {
      throw ArgumentError(
        'a RenderTexture of ${width}x$height has no pixels to draw into; '
        'ask for at least one each way',
      );
    }
    return RenderTexture._(
      device.createTexture(
        RenderTargetSpec(
          width: width,
          height: height,
          format: TextureFormat.r8g8b8a8UNormInt,
        ),
      ),
      camera: camera,
      layerMask: layerMask,
      clearColor: clearColor ?? Vector4(0.055, 0.062, 0.078, 1.0),
      exposure: exposure,
      refreshEveryFrame: refreshEveryFrame,
    );
  }

  RenderTexture._(
    this.texture, {
    required this.camera,
    required this.layerMask,
    required this.clearColor,
    required this.exposure,
    required this.refreshEveryFrame,
  });

  /// What the camera drew, as sRGB bytes. Whatever the allocation held until
  /// the first frame draws it; see [isDrawn].
  final TextureHandle texture;

  int get width => texture.width;
  int get height => texture.height;

  /// Where the picture is taken from, with its own projection; the aspect is
  /// the texture's.
  CameraNode camera;

  /// Which layers the camera draws.
  int layerMask;

  /// What shows where nothing was drawn and the sky is off, sRGB-encoded as
  /// `RenderView.clearColor` is.
  Vector4 clearColor;

  /// What the light is multiplied by before it is clipped and encoded.
  double exposure;

  /// Whether every frame draws it again. False draws it once and then only
  /// after [invalidate]: a portrait of a room nobody changes is one picture,
  /// not sixty a second.
  bool refreshEveryFrame;

  /// Meshes the camera leaves out — the screen showing the picture, most
  /// often, which would otherwise show itself.
  final Set<MeshNode> excluded = <MeshNode>{};

  /// Asks for the picture to be drawn again on the next frame.
  void invalidate() => _generation++;

  int _generation = 0;
  int _drawnGeneration = -1;

  /// Whether [texture] holds a picture rather than an allocation's contents.
  bool get isDrawn => _drawnGeneration >= 0;

  /// Whether the next frame has to draw it.
  bool get isDue => refreshEveryFrame || _drawnGeneration != _generation;

  /// Called by the renderer once the picture is in [texture].
  void markDrawn() => _drawnGeneration = _generation;
}
