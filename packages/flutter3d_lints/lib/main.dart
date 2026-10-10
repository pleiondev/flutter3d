/// The analysis server's door into this package.
///
/// **A file the analysis server imports by this name and nothing else.** When
/// an `analysis_options.yaml` lists `flutter3d_lints` under `plugins:`, the
/// server generates a package that imports `lib/main.dart` and reads the
/// top-level [plugin]. Tooling of one's own imports `flutter3d_lints.dart`
/// instead.
library;

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/migration/migration_rules.dart';
import 'src/rules.dart';

/// What the analysis server loads.
final Flutter3dLintsPlugin plugin = Flutter3dLintsPlugin();

/// The rules for code a fixed step runs, registered as warnings, and the
/// migration diagnostics for code written against flutter3d 0.8.
///
/// **Warnings, so enabling the plugin is enabling them.** A rule registered
/// as a lint is off until each project names it under `diagnostics:`; these
/// guard a promise — a replay is the same run — that a project which installs
/// this package has already made, so they are on, and a project turns one
/// off by name. The migration diagnostics are warnings for the same reason:
/// a project on 1.0 that still uses what 0.8 had is one the plugin should
/// tell, and one that is done migrating never sees them.
final class Flutter3dLintsPlugin extends Plugin {
  @override
  String get name => 'flutter3d_lints';

  @override
  void register(PluginRegistry registry) {
    for (final rule in simulationRules()) {
      registry.registerWarningRule(rule);
    }
    registry
      ..registerWarningRule(Flutter3dMigrationRule())
      ..registerWarningRule(ManualMigrationRule())
      ..registerFixForRule(Flutter3dMigrationRule.code, ApplyMigration.new);
  }
}
