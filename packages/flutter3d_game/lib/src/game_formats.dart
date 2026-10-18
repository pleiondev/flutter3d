import 'package:flutter3d_foundation/flutter3d_foundation.dart';

import 'cloud/consents.dart';
import 'cloud/save_sync.dart';
import 'config/game_config.dart';
import 'input/action_map.dart';
import 'screens/save_file.dart';

/// Every format `flutter3d_game` writes and promises to keep reading, for an
/// engine's `FormatRegistry`: the settings file, an action map, the index of
/// save slots, the cloud-save state and the telemetry answer. A save itself
/// is `flutter3d_sim`'s (`simFormats`).
///
/// Hand it to `Flutter3dView.formats`, which registers it beside
/// `coreFormats` and `simFormats`.
const List<FormatSpec> gameFormats = <FormatSpec>[
  GameSettings.format,
  ActionMap.format,
  SaveSlots.indexFormat,
  SaveSync.stateFormat,
  Consents.telemetryFormat,
];
