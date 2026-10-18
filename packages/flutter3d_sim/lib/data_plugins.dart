/// What a data plugin's entity kinds need from the simulation: the
/// `entityKinds` section of a `.f3dplugin` document ([entityKindsSection])
/// and the [DataEntityKind]s it adds to the engine's `EntityKinds`.
///
/// **Here, beside the level's kinds, and not in `flutter3d_plugin_runtime`**,
/// which reads a document's sections through the plugin API's
/// `DataSectionRegistry` and depends on no subsystem a section installs into.
/// An engine registers the section with the rest:
///
/// ```dart
/// final loader = DataPluginLoader(
///   sections: DataSections(<DataSection>[entityKindsSection]),
/// );
/// ```
library;

export 'src/level/data_entity_kind.dart';
