import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart' show FormatSpec;

import 'f3d/f3d_format.dart';
import 'fmat/fmat.dart';
import 'material_language/material_parser.dart';
import 'splat/splat_octree.dart';

/// The engine's own model and material formats, for a `FormatRegistry`:
/// `.f3d`, `.fmat`, `.f3dmat` and `.f3dsplat`.
///
/// The formats this package reads from other projects — glTF, OBJ, STL,
/// USDZ, KTX2 — are not here: their versions are other people's, and a
/// registry entry promises fixtures at every version of ours.
/// `flutter3d_core.dart`'s `coreFormats` adds the frame capture.
const List<FormatSpec> modelFormats = <FormatSpec>[
  f3dFormat,
  fmatFormat,
  f3dmatFormat,
  f3dsplatFormat,
];
