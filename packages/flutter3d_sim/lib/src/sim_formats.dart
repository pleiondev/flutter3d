import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart' show FormatSpec;

import 'input/input_tape.dart';
import 'level/level.dart';
import 'level/level_visibility.dart';
import 'level/lightmap.dart';
import 'save/demo.dart';
import 'save/snapshot.dart';
import 'share/share_bundle.dart';
import 'telemetry/telemetry_upload.dart';

/// Every format `flutter3d_sim` writes and promises to keep reading, for an
/// engine's `FormatRegistry`: the level and what is baked beside it, a save,
/// a recorded run and its input tape, a shared run and a telemetry upload.
///
/// `Flutter3dView` registers these with `flutter3d_core`'s `coreFormats`, so
/// a plugin asking the loop for its `FormatRegistry` finds them.
const List<FormatSpec> simFormats = <FormatSpec>[
  Level.format,
  LevelVisibility.format,
  Lightmap.format,
  Snapshot.format,
  Demo.format,
  InputTape.format,
  ShareBundle.format,
  TelemetryUpload.format,
];
