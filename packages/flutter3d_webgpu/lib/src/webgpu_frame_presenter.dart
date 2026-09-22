/// The widget `presentFrame` in `flutter3d_app` returns for a [WebGpuDevice].
///
/// Not shared with `flutter3d_webgl`'s own presenter, deliberately: there is
/// no package both already depend on that isn't going flat in this exact
/// change, and the two backends already ship in the same web binary when
/// `FLUTTER3D_WEBGPU=true`, so a shared helper would save source lines and not
/// a single byte of the bundle — below this codebase's own bar for extracting
/// something.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgpu_device.dart';

/// Copies [frame] into [device]'s canvas and shows it, styled by [fit] and
/// [quality] through CSS on the element rather than through Flutter, since
/// Flutter does not composite these pixels.
class WebGpuFramePresenter extends StatelessWidget {
  const WebGpuFramePresenter({
    super.key,
    required this.device,
    required this.frame,
    this.fit = BoxFit.fill,
    this.quality = FilterQuality.none,
  });

  final WebGpuDevice device;
  final TextureHandle frame;
  final BoxFit fit;
  final FilterQuality quality;

  @override
  Widget build(BuildContext context) {
    device.copyToCanvas(frame);
    device.applyCanvasStyle(fit: fit, quality: quality);
    return HtmlElementView(viewType: device.viewType);
  }
}
