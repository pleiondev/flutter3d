/// Drawing several views of one frame: in one pass where the device has
/// `DeviceFeature.multiview`, one pass per view where it does not.
///
/// **The fallback is the contract's, not each caller's.** A stereo view, a
/// headset's two eyes or a cube drawn as six layers all want the same
/// thing, and the device that draws them in one pass is the exception: no
/// backend has multiview yet. Written once here, the choice is the same on
/// every backend and a caller writes its draws once, for a view index it is
/// handed or one its stage reads.
library;

import 'capabilities.dart';
import 'command_encoder.dart';
import 'graphics_device.dart';

/// One pass [ViewPasses.draw] opened, and which views it draws.
final class ViewPass {
  const ViewPass._(this.viewMask, this.viewIndex);

  /// Every view the pass draws, one bit each, as
  /// `RenderPassDescriptor.viewMask` names them.
  final int viewMask;

  /// The one view this pass draws, or null for a multiview pass that draws
  /// every view of [viewMask] at once, where a stage reads its view index
  /// from the hardware instead. What a caller hands its draws so the view's
  /// own matrices are bound.
  final int? viewIndex;

  /// Whether this one pass draws every view.
  bool get isMultiview => viewIndex == null;

  @override
  String toString() => isMultiview
      ? 'ViewPass(mask 0x${viewMask.toRadixString(16)})'
      : 'ViewPass(view $viewIndex)';
}

/// Opens the passes that draw a descriptor's views.
abstract final class ViewPasses {
  /// Draws [descriptor]'s views on [device] and returns how many passes it
  /// opened: one multiview pass when the device has `DeviceFeature.multiview`
  /// and the views fit `DeviceLimits.maxMultiviewViews`, otherwise one pass
  /// per view through `RenderPassDescriptor.forView`, each drawing into its
  /// own layer. [draw] records each pass; this submits it.
  ///
  /// A descriptor with no view mask is one pass, as it always was. The
  /// per-view passes need `DeviceFeature.renderToArrayLayer` for a view
  /// above zero, and a device without that refuses the second pass with it
  /// named, as `beginRenderPass` refuses any pass that draws into a layer.
  static int draw(
    GraphicsDevice device,
    RenderPassDescriptor descriptor,
    void Function(CommandEncoder pass, ViewPass view) draw,
  ) {
    final mask = descriptor.viewMask;
    if (mask == null) {
      final pass = device.beginRenderPass(descriptor);
      draw(pass, const ViewPass._(1, 0));
      pass.submit();
      return 1;
    }
    if (inOnePass(device, descriptor)) {
      final pass = device.beginRenderPass(descriptor);
      draw(pass, ViewPass._(mask, null));
      pass.submit();
      return 1;
    }
    final views = descriptor.views;
    for (final view in views) {
      final pass = device.beginRenderPass(descriptor.forView(view));
      draw(pass, ViewPass._(mask, view));
      pass.submit();
    }
    return views.length;
  }

  /// Whether [draw] would draw [descriptor]'s views in one pass on [device]:
  /// it has `DeviceFeature.multiview` and the highest view is under its
  /// `DeviceLimits.maxMultiviewViews`.
  static bool inOnePass(
    GraphicsDevice device,
    RenderPassDescriptor descriptor,
  ) {
    final mask = descriptor.viewMask;
    if (mask == null) return true;
    if (!device.features.has(DeviceFeature.multiview)) return false;
    return mask.bitLength <= device.limits.maxMultiviewViews;
  }
}
