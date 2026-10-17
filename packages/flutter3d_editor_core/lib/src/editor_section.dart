/// The `editor:` section of a `.f3dplugin` document, and where a project
/// keeps the data plugins the editor installs.
library;

import 'package:flutter3d_plugin_api/editor.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// What an `editor:` section held, read.
final class EditorSectionContents {
  const EditorSectionContents({
    this.components = const <ComponentHints>[],
    this.entityKinds = const <EntityKindHints>[],
    this.materials = const <MaterialHints>[],
  });

  final List<ComponentHints> components;
  final List<EntityKindHints> entityKinds;
  final List<MaterialHints> materials;
}

/// The `editor:` section of a data plugin: the hints its components, entity
/// kinds and lit models are edited with, as [ComponentHints.toJson],
/// [EntityKindHints.toJson] and [MaterialHints.toJson] write them.
///
/// ```json
/// "editor": {
///   "components": [{"id": "acme.glow", "title": "Glow", "fields": [...]}],
///   "entityKinds": [{"type": "lamp", "label": "Lamp", "fields": [...]}],
///   "materials": [{"model": "acme.velvet", "fields": [...]}]
/// }
/// ```
///
/// **An engine with no editor installs the plugin without it**, and says so
/// through the context's note: a game reads the same document and has no
/// inspector to fill. Registered with the loader's sections by the editor
/// (`DataSections(<DataSection>[editorSection, …])`); no `requires` names
/// it, since a build that skips it loses nothing a game needs.
const DataSection editorSection = _EditorSection();

final class _EditorSection extends DataSection {
  const _EditorSection();

  @override
  String get name => 'editor';

  @override
  Object read(DataSectionRead step) {
    final written = step.written;
    final context = step.context;
    if (written is! Map) {
      throw DocumentFormatException(
        'plugin "${context.plugin}": "editor" is a map of components, '
        'entityKinds and materials, not $written',
      );
    }
    List<T> rows<T>(String key, T Function(Object?) read) =>
        switch (written[key]) {
          null => List<T>.empty(),
          final List<Object?> list => List<T>.unmodifiable(list.map(read)),
          final other => throw DocumentFormatException(
            'plugin "${context.plugin}": "editor.$key" is a list, not $other',
          ),
        };
    return EditorSectionContents(
      components: rows('components', ComponentHints.fromJson),
      entityKinds: rows('entityKinds', EntityKindHints.fromJson),
      materials: rows('materials', MaterialHints.fromJson),
    );
  }

  @override
  Object? write(Object section) {
    final contents = section as EditorSectionContents;
    return <String, Object?>{
      if (contents.components.isNotEmpty)
        'components': <Object?>[
          for (final c in contents.components) c.toJson(),
        ],
      if (contents.entityKinds.isNotEmpty)
        'entityKinds': <Object?>[
          for (final k in contents.entityKinds) k.toJson(),
        ],
      if (contents.materials.isNotEmpty)
        'materials': <Object?>[for (final m in contents.materials) m.toJson()],
    };
  }

  @override
  void install(DataSectionInstall step) {
    final host = step.host;
    final section = step.section;
    final context = step.context;
    final contents = section as EditorSectionContents;
    final hints = host.maybeRegistry<EditorHintRegistry>();
    if (hints == null) {
      context.note(
        'its editor section is not installed: this engine has no editor',
      );
      return;
    }
    for (final component in contents.components) {
      hints.addComponent(component);
    }
    for (final kind in contents.entityKinds) {
      hints.addEntityKind(kind);
    }
    for (final material in contents.materials) {
      hints.addMaterial(material);
    }
  }
}

/// Where a project keeps the data plugins its editor installs, relative to
/// the project's root: beside its other assets, so the game ships the same
/// files the editor read.
const String projectPluginsDirectory = 'assets/plugins';

/// The `.f3dplugin` documents among [files], paths relative to a project's
/// root, that the editor installs: those under [projectPluginsDirectory], in
/// sorted order so two machines install them alike.
List<String> projectPluginPaths(Iterable<String> files) {
  final prefix = '$projectPluginsDirectory/';
  return <String>[
    for (final path in files.map((String p) => p.replaceAll(r'\', '/')))
      if (path.startsWith(prefix) && path.endsWith('.f3dplugin')) path,
  ]..sort();
}
