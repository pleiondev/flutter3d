/// The fields of one engine: [FieldRegistry].
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'field.dart';
import 'host_field.dart';

/// The fields one engine has, declared by the application and its plugins:
/// `host.registry<FieldRegistry>()`.
///
/// **Declared before anything writes them.** A field is a declaration
/// first ([FieldDeclaration]): its quantity and unit, its grid, where it is
/// held, who writes it and who reads it. A subsystem that writes a field
/// names it, and the registry of subsystems refuses one that writes a field
/// nobody declared or that another step writes; the frame's nodes carry a
/// field on a device under its id.
///
/// **A host field's values are the simulation's.** Declaring one makes its
/// [hostField], every value nought, and puts it in the loop's snapshots, so
/// a rollback, a replay and the double-step check carry it like the world.
/// What the view and audio read is the [published] copy: the values at the
/// end of the last step, which no step changes under a frame that is
/// reading them.
///
/// **Extended by the engine, called by plugins**, as every registry is.
/// Each declaration a plugin makes is under its own id
/// (`<pluginId>.<name>`) and taken back when the plugin is switched off.
abstract base class FieldRegistry extends PluginRegistry {
  /// A registry; the engine's subclass holds the fields.
  const FieldRegistry();

  /// Declares [field]. Throws an [ArgumentError] for a declaration with a
  /// [FieldDeclaration.problem] or an id already declared; a
  /// [PluginException] for a plugin's id outside its namespace
  /// (`PluginManifest.nameProblem`).
  Registration declare(FieldDeclaration field);

  /// Every field declared, in the order it was.
  List<FieldDeclaration> get declared;

  /// The field called [id], or null when none is.
  FieldDeclaration? declarationOf(String id) {
    for (final field in declared) {
      if (field.id == id) return field;
    }
    return null;
  }

  /// The values of the host field called [id] as the simulation holds
  /// them, or null for a field on a device or one nobody declared.
  ///
  /// For the simulation's own steps: a subsystem is handed its fields by
  /// its context, which holds it to what it declared.
  ///
  /// **Read only through a plugin's view**, `HostField.readOnly`, unless
  /// the plugin declared the field itself and touches the simulation: a
  /// plugin may not write another's field, or the engine's, past the
  /// declared writer, and a view or tooling plugin writes none.
  HostField? hostField(String id);

  /// The values of the host field called [id] at the end of the last step,
  /// or null for a field on a device or one nobody declared: what a frame's
  /// node and a sound read. Before the first step, every value nought.
  HostField? published(String id);

  @override
  FieldRegistry forPlugin(PluginScope scope);
}
