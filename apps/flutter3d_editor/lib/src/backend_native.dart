/// Impeller, by name — see `backend.dart` for why not the registry.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';

/// Opens the device the editor draws through, or throws with something worth
/// putting on screen.
Future<GraphicsDevice> openEditorDevice() => GpuRenderBackend.open();

/// The widget that shows [frame] — always drawn through `GpuRenderBackend`,
/// since that is the only device [openEditorDevice] opens here.
Widget presentEditorFrame(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.fill,
  FilterQuality quality = FilterQuality.none,
}) => GpuFrameImage(frame: frame, fit: fit, quality: quality);
