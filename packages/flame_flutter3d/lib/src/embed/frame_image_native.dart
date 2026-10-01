import 'dart:ui' as ui;

import 'package:flutter3d/flutter3d.dart' show GraphicsDevice, TextureHandle;
import 'package:flutter3d_impeller/flutter3d_impeller.dart';

/// Impeller's frame as an image over the same GPU allocation, without a
/// copy; null for the software rasteriser, whose frame is read back.
ui.Image? frameImageNow(GraphicsDevice device, TextureHandle frame) =>
    device is GpuRenderBackend ? frame.gpuTexture.asImage() : null;
