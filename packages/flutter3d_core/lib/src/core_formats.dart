import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show hardwareFormats;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart' show FormatSpec;

import 'engine/render/frame_capture.dart';
import 'formats/formats_registry.dart';

/// Every format `flutter3d_core` writes and promises to keep reading, for
/// an engine's `FormatRegistry`: the model and material formats of
/// `package:flutter3d_core/formats.dart` ([modelFormats]), the frame
/// capture, and the shader bundle and trace of `flutter3d_hardware`
/// ([hardwareFormats]).
const List<FormatSpec> coreFormats = <FormatSpec>[
  ...modelFormats,
  FrameCapture.format,
  ...hardwareFormats,
];
