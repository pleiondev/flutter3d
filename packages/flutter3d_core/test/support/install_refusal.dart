/// Where a test reads a registry's refusal of a plugin at install.
///
/// A plugin whose `install` throws is switched off with what it threw, and
/// the others install, so the refusal is in the plugin's status rather than
/// thrown at the test.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// What the first plugin of [plugins] switched off by a throw threw, or
/// null when none was.
Object? installRefusal(PluginManager plugins) =>
    plugins.statuses.map((s) => s.error).nonNulls.firstOrNull;
