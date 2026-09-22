/// The widget `presentFrame` in `flutter3d_app` returns for a [WebGlDevice].
///
/// Not shared with `flutter3d_webgpu`'s own presenter, deliberately: there is
/// no package both already depend on that isn't going flat in this exact
/// change, and the two backends already ship in the same web binary when
/// `FLUTTER3D_WEBGPU=true`, so a shared helper would save source lines and not
/// a single byte of the bundle — below this codebase's own bar for extracting
/// something.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgl_device.dart';

/// Blits [frame] onto [device]'s canvas and shows it, styled by [fit] and
/// [quality] through CSS on the element rather than through Flutter, since
/// Flutter does not composite these pixels.
class WebGlFramePresenter extends StatelessWidget {
  const WebGlFramePresenter({
    super.key,
    required this.device,
    required this.frame,
    this.fit = BoxFit.fill,
    this.quality = FilterQuality.none,
  });

  final WebGlDevice device;
  final TextureHandle frame;
  final BoxFit fit;
  final FilterQuality quality;

  @override
  Widget build(BuildContext context) {
    device.blitToCanvas(frame);
    device.canvas.style
      ..width = '100%'
      ..height = '100%'
      // A display surface, not a control. Left interactive, the canvas takes
      // the pointer events over it and the Flutter widgets above the platform
      // view never see them — which reads as an application whose camera does
      // not turn while its keyboard works fine.
      ..pointerEvents = 'none'
      ..objectFit = switch (fit) {
        BoxFit.contain => 'contain',
        BoxFit.cover => 'cover',
        BoxFit.fill => 'fill',
        BoxFit.fitWidth ||
        BoxFit.fitHeight ||
        BoxFit.none ||
        BoxFit.scaleDown => 'contain',
      }
      ..imageRendering = quality == FilterQuality.none ? 'pixelated' : 'auto';
    return HtmlElementView(viewType: device.viewType);
  }
}
