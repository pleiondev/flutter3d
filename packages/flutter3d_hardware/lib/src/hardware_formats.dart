import 'package:flutter3d_foundation/flutter3d_foundation.dart' show FormatSpec;

import 'shader_bundle.dart';
import 'trace/trace.dart';

/// The two files `flutter3d_hardware` writes and promises to keep reading,
/// for an engine's `FormatRegistry`: the F3SB shader bundle and the
/// `.f3dtrace` a recording device keeps. `flutter3d_core`'s `coreFormats`
/// includes them.
const List<FormatSpec> hardwareFormats = <FormatSpec>[
  ShaderBundle.format,
  Trace.format,
];
