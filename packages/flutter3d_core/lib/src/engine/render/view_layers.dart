/// What an XR runtime takes from a frame and what it gives one, as nodes of
/// the frame graph: the views copied into the layers of the runtime's
/// image, and the depth of the real world for a node that occludes with it
/// — 1.0.
///
/// **The frame stays one frame.** The renderer draws a headset's views as
/// it draws a stereo pair, side by side in one target, one viewport each
/// (`FrameContext.views`, from the runtime's poses and angles). A runtime
/// wants each view in a layer of its own image, so the last node of the
/// frame copies each view's rectangle into its layer: the one-pass-per-view
/// path every device with texture copies has. A device with
/// `DeviceFeature.multiview` could draw the views into the layers in one
/// pass instead; the scene pass does not do that yet, and the copy is the
/// path a runtime gets on every backend.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show RenderAnchor;

import 'frame_graph.dart';
import 'frame_plan.dart';
import 'render_node.dart';

/// The node that hands each view of a frame to the layer of a runtime's
/// image it belongs in: the projection layer an XR session submits.
///
/// **It reads the finished picture and gives it back unchanged** (`frame`
/// in, `frame` out), so it runs last at [RenderAnchor.beforePresent] and is
/// never culled; on the way it copies the rectangle of each of
/// `FrameContext.views` into layer `FrameView.index` of [target], from the
/// top left. A frame with no [target] copies nothing.
///
/// [target] is the image the runtime handed out for this frame — an array
/// texture with a layer per view, imported from the runtime's swapchain
/// (`GraphicsDevice.importTexture`) where the device can, or one of the
/// engine's own that the session copies out where it cannot. It is set
/// before each frame and read once, by [execute].
final class ProjectionLayerNode extends RenderNode {
  /// A node with no image yet.
  ProjectionLayerNode();

  /// The image the next frame's views are copied into, or null to copy
  /// none: an array texture of a layer per view, in the format of the
  /// frame's picture, at least as large as each view's rectangle.
  TextureHandle? target;

  /// How many views the last frame copied.
  int get copied => _copied;
  int _copied = 0;

  /// How many frames have been copied into a [target].
  int get frames => _frames;
  int _frames = 0;

  @override
  String get name => 'projection layer';

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.frame];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  RenderAnchor get defaultAnchor => RenderAnchor.beforePresent;

  /// Throws the refusal a frame drawn on [device] would meet copying into
  /// [image]: an [UnsupportedCapabilityException] naming
  /// `DeviceFeature.textureCopy` on a device without copies, and an
  /// [ArgumentError] for an image that is not a texture with a layer per
  /// view in [format]. What a session asks before its first frame, so a
  /// runtime that cannot be fed is refused once, by name, and not every
  /// frame.
  static void check(
    GraphicsDevice device,
    TextureHandle image, {
    required int views,
    required TextureFormat format,
  }) {
    if (!device.features.has(DeviceFeature.textureCopy)) {
      throw UnsupportedCapabilityException(
        DeviceFeature.textureCopy,
        backend: device.backendName,
        reason:
            "a headset's views are copied into the layers of its image, "
            'and this device copies no texture',
      );
    }
    if (image.depthOrArrayLayers < views) {
      throw ArgumentError(
        'the image holds ${image.depthOrArrayLayers} layers and the frame '
        'has $views views; a projection layer needs a layer per view',
      );
    }
    if (_base(image.format) != _base(format)) {
      throw ArgumentError(
        'the image is ${image.format.name} and the frame is drawn in '
        '${format.name}; a copy keeps the format, so ask the runtime for '
        'an image in the frame\'s',
      );
    }
  }

  /// [format] with the sRGB-ness taken off: a copy may cross it.
  static String _base(TextureFormat format) =>
      format.name.replaceAll('Srgb', '').replaceAll('SRGB', '');

  @override
  void execute(RenderFrame frame) {
    final picture = frame.resources.texture(FrameResourceIds.frame);
    frame.resources.provide(FrameResourceIds.frame, picture);
    _copied = 0;
    final image = target;
    if (image == null) return;
    final views = frame.views;
    check(frame.device, image, views: views.length, format: picture.format);
    final copies = frame.device.beginTransferPass(label: name);
    for (final view in views) {
      final rect = view.viewport;
      final x = (rect.x * picture.width).round();
      final y = (rect.y * picture.height).round();
      final width = (rect.width * picture.width).round().clamp(0, image.width);
      final height = (rect.height * picture.height).round().clamp(
        0,
        image.height,
      );
      if (width == 0 || height == 0) continue;
      copies.copyTextureToTexture(
        TextureCopyLocation(picture, x: x, y: y),
        TextureCopyLocation(image, z: view.index),
        width: width,
        height: height,
      );
      _copied++;
    }
    copies.submit();
    _frames++;
  }
}

/// How far away the real world is, from one view, as an AR runtime
/// measures it: [width] × [height] distances in metres, row-major from the
/// top left, for the view at [view].
///
/// Infinity where the runtime saw nothing: nothing there occludes.
final class EnvironmentDepth {
  /// [metres] over [width] × [height], which must hold exactly as many.
  EnvironmentDepth({
    required this.width,
    required this.height,
    required this.metres,
    this.view = 0,
  }) {
    if (width < 1 || height < 1 || metres.length != width * height) {
      throw ArgumentError(
        'a depth image of ${width}x$height holds ${width * height} '
        'distances, not ${metres.length}',
      );
    }
  }

  /// Distances across.
  final int width;

  /// Distances down.
  final int height;

  /// The distances, in metres.
  final Float32List metres;

  /// Which of the frame's views it was measured from.
  final int view;
}

/// The node that puts the real world's depth in the frame, as a texture
/// under [id] that a node occluding virtual things with real ones reads.
///
/// **The frame's half of depth occlusion.** An AR session hands [depth]
/// each frame; this uploads it as one `r32Float` texture of metres and
/// writes it under [id], before the opaque scene. A frame with no depth
/// gets a single texel at infinity, so a reader never starves. The engine's
/// own passes do not read it yet: a plugin's node or a material that
/// declares [id] does, and the graph orders it after this one.
final class EnvironmentDepthNode extends RenderNode {
  /// A node with no depth yet.
  EnvironmentDepthNode();

  /// Where the frame carries the real world's depth.
  static const ResourceId id = ResourceId('environment_depth');

  /// The depth the next frame uploads, or null for none.
  EnvironmentDepth? depth;

  /// The textures of the last frames, newest last: one is given back only
  /// once as many frames as can be in flight have been drawn after it.
  final List<(GraphicsDevice, TextureHandle)> _uploaded =
      <(GraphicsDevice, TextureHandle)>[];

  /// How many uploads are kept before the oldest is given back.
  static const int _kept = 4;

  @override
  String get name => 'environment depth';

  @override
  List<ResourceId> get writes => const <ResourceId>[id];

  @override
  RenderAnchor get defaultAnchor => RenderAnchor.beforeOpaque;

  @override
  void execute(RenderFrame frame) {
    final image =
        depth ??
        EnvironmentDepth(
          width: 1,
          height: 1,
          metres: Float32List.fromList(<double>[double.infinity]),
        );
    final texture = frame.device.createTextureFromPixels(
      width: image.width,
      height: image.height,
      format: TextureFormat.r32Float,
      pixels: ByteData.sublistView(image.metres),
    );
    _uploaded.add((frame.device, texture));
    while (_uploaded.length > _kept) {
      final (device, old) = _uploaded.removeAt(0);
      device.releaseTexture(old);
    }
    frame.resources.provide(id, texture);
  }

  /// Gives back every texture uploaded: when the session that fed it ends.
  void release() {
    for (final (device, texture) in _uploaded) {
      device.releaseTexture(texture);
    }
    _uploaded.clear();
  }
}
