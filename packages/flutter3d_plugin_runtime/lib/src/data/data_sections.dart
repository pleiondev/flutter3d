import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The sections data plugins may have beyond the runtime's own, filled by
/// the subsystems that read them: the slot [DataSectionRegistry] names.
///
/// One per engine, handed to the loop among its registries and to the
/// [DataPluginLoader] that reads documents for it:
///
/// ```dart
/// final sections = DataSections(<DataSection>[
///   entityKindsSection,        // flutter3d_sim
///   ...renderDataSections,     // flutter3d_core: materials, renderSteps
///   effectsSection,            // flutter3d_particles
///   physicalMaterialsSection,  // flutter3d_matter
///   materialPairsSection,      // flutter3d_matter
/// ]);
/// final loader = DataPluginLoader(sections: sections);
/// ```
///
/// A section registered by a compiled plugin goes again when the plugin is
/// switched off; a document read after that keeps the section as written
/// and does not read it.
final class DataSections extends DataSectionRegistry {
  /// A registry holding [sections], registered by the application.
  DataSections([Iterable<DataSection> sections = const <DataSection>[]]) {
    sections.forEach(register);
  }

  /// The keys of a `.f3dplugin` document the runtime reads itself, which no
  /// section may take: the envelope of version 1, the manifest, and what
  /// every engine has, a replaying server included (the loop's phases, the
  /// bus, and the step systems in Wasm and in the expression language), and
  /// the render modules in Wasm, which it decodes and runs for the section
  /// that draws.
  static const Set<String> runtimeKeys = <String>{
    'f3dplugin',
    'manifest',
    'phases',
    'events',
    'wasm',
    'wasmRender',
    'expressions',
  };

  final List<DataSection> _sections = <DataSection>[];

  @override
  Registration register(DataSection section) => _register(section, null);

  Registration _register(DataSection section, PluginScope? scope) {
    final name = section.name;
    if (runtimeKeys.contains(name) || FormatSpec.envelopeKeys.contains(name)) {
      throw ArgumentError.value(
        name,
        'section',
        'is a key the runtime reads itself; a section takes a name of its own',
      );
    }
    // A section's name is a key of the document, which the engine's own
    // sections share: a plugin's is in its namespace (D23).
    if (scope?.manifest.nameProblem(name, what: 'the data section')
        case final problem?) {
      throw PluginException(problem);
    }
    if (this[name] != null) {
      throw NameTakenException(
        name,
        what: 'the data section',
        detail: 'one name is one section in one engine',
      );
    }
    _sections.add(section);
    final registration = Registration(() => _sections.remove(section));
    scope?.track(registration);
    return registration;
  }

  @override
  DataSection? operator [](String name) =>
      _sections.where((DataSection s) => s.name == name).firstOrNull;

  @override
  List<String> get names =>
      List<String>.unmodifiable(<String>[for (final s in _sections) s.name]);

  @override
  DataSectionRegistry forPlugin(PluginScope scope) =>
      _PluginSections(this, scope);
}

/// [DataSections] as one plugin sees it: what it registers is tracked by its
/// scope, and goes when the plugin is switched off.
final class _PluginSections extends DataSectionRegistry {
  const _PluginSections(this._sections, this._scope);

  final DataSections _sections;
  final PluginScope _scope;

  @override
  Registration register(DataSection section) =>
      _sections._register(section, _scope);

  @override
  DataSection? operator [](String name) => _sections[name];

  @override
  List<String> get names => _sections.names;

  @override
  DataSectionRegistry forPlugin(PluginScope scope) =>
      _sections.forPlugin(scope);
}
