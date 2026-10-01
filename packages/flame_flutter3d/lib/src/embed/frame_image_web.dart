import 'dart:ui' as ui;

import 'package:flutter3d/flutter3d.dart' show GraphicsDevice, TextureHandle;

/// Always null: WebGL and WebGPU draw into textures Flutter does not
/// composite, so their frames reach a canvas only as pixels read back.
ui.Image? frameImageNow(GraphicsDevice device, TextureHandle frame) => null;
