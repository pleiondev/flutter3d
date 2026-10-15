/// The editor's side of the plugin API: [EditorPieces], through which a plugin
/// brings commands, inspector components and palette entries, gizmos,
/// importers and asset-browser entries, and the hints its inspectors are
/// built from ([EditorHints], which comes along).
library;

import 'package:flutter3d_core/formats.dart' show MaterialHint;
import 'package:flutter3d_plugin_api/editor.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_api/tools.dart' show ToolHints;
import 'package:flutter3d_sim/flutter3d_sim.dart' show Level;
import 'package:vector_math/vector_math.dart';

import 'editing.dart' show Picked;
import 'editor_command.dart';
import 'editor_hints.dart';
import 'gizmos.dart';
import 'inspector_sections.dart';
import 'plugin_assets.dart';
import 'plugin_gizmos.dart';

/// Reads a plugin command back from a call's arguments — everything but the
/// `command` key — or answers null when they are not the shape it needs.
///
/// Null rather than a throw, for the reason [EditorCommand.fromJson] gives.
typedef CommandReader = PluginCommand? Function(Map<String, Object?> arguments);

/// A component: a named group of fields an inspector shows under one heading,
/// and offers, at their defaults, where they are not set.
///
/// **Keyed by [kind]**, which is unique in one editor: two plugins may not both
/// define `buoyancy`, and the refusal names both. The editor's own sections are
/// components too ([builtInComponents]), so a plugin's lands among them by the
/// same rule: after the built-in ones of its [piece], before the last, which
/// takes every key no section names.
///
/// For an entity, [types] narrows it to the entity types it belongs to — a
/// `boat` has buoyancy and a `torch` does not. Empty means every one of
/// [piece].
final class EditorComponent {
  const EditorComponent({
    required this.kind,
    required this.title,
    this.piece = Piece.entity,
    this.keys = const <String>{},
    this.defaults = const <String, Object?>{},
    this.types = const <String>{},
    this.hints = const <FieldHint>[],
  });

  /// Its stable name: `buoyancy`, `brush.collision`.
  final String kind;

  /// The heading the inspector shows.
  final String title;

  /// Which of the document's three lists it belongs to.
  final Piece piece;

  /// Fields it shows that have no default to offer — read, written, never
  /// suggested.
  final Set<String> keys;

  /// Fields it shows and, where the selected thing does not have them, offers
  /// at these values.
  final Map<String, Object?> defaults;

  /// The entity types it belongs to; empty for all of them.
  final Set<String> types;

  /// How its fields are shown, for those a plugin hinted: a component made
  /// from a plugin's [ComponentHints] or [EntityKindHints] carries them.
  final List<FieldHint> hints;

  /// Every field it shows: [keys], the keys of [defaults] and of [hints].
  Set<String> get fields => <String>{
    ...keys,
    ...defaults.keys,
    for (final hint in hints) hint.key,
  };

  /// The hint for [key], or null for a field shown by its value's shape.
  FieldHint? hintFor(String key) {
    for (final hint in hints) {
      if (hint.key == key) return hint;
    }
    return null;
  }

  /// Whether it belongs on a [piece] of entity type [type].
  bool appliesTo(Piece piece, {String? type}) =>
      this.piece == piece &&
      (types.isEmpty || (type != null && types.contains(type)));

  @override
  String toString() => 'EditorComponent($kind)';
}

/// One row a plugin adds to the palette: an entity type to place, and what a
/// placed one starts with.
///
/// A row for [type] is offered whether the level has one yet or not, which is
/// the point: an empty level built for a plugin's game can place that game's
/// things.
final class PaletteEntry {
  const PaletteEntry(
    this.type, {
    this.label,
    this.tint,
    this.properties = const <String, Object?>{},
  });

  /// The entity type a placed one has.
  final String type;

  /// What the row says, or null for [type].
  final String? label;

  /// The colour the row and the gizmo are drawn in, linear, or null for the
  /// colour the type's name picks.
  final LinearColor? tint;

  /// The properties a placed one starts with when the level has none of its
  /// type to copy.
  final Map<String, Object?> properties;

  @override
  String toString() => 'PaletteEntry($type)';
}

/// Editor commands, inspector components and palette entries: the slot
/// [EditorPieces] fills, `host.registry<EditorPieces>()`.
///
/// **Declared by the package that fills it.** It was a marker in
/// `flutter3d_plugin_api` until 1.0.0-rc.1, which named a slot nothing in
/// the contract used.
abstract base class EditorRegistry extends PluginRegistry {
  const EditorRegistry();
}

/// The [EditorRegistry] an editor fills: commands, inspector components and
/// palette entries that plugins bring.
///
/// **What an editor plugin is handed.** Its `install` asks the host for this
/// type, `host.registry<EditorPieces>()`, and gets a view scoped to the
/// plugin: everything added through it is withdrawn when the plugin is switched
/// off, and ranked by the plugin's place in the install order. An application
/// without plugins uses an [EditorPieces] directly.
///
/// ```dart
/// void install(PluginHost host) {
///   host.registry<EditorPieces>()
///     ..addCommand('sink', SinkCommand.read)
///     ..addComponent(const EditorComponent(
///       kind: 'buoyancy',
///       title: 'Buoyancy',
///       defaults: {'buoyancy': 1.0, 'drag': 0.4},
///       types: {'boat'},
///     ))
///     ..addPaletteEntry(const PaletteEntry('boat', properties: {'buoyancy': 1.0}));
/// }
/// ```
///
/// What is added comes back out in order: the application's first, then each
/// plugin's in install order, and within one owner as it was added.
///
/// **A plugin's pieces are published under its namespace**
/// (`PluginManifest.namespace`, D23), as its MCP tools, quantities, fields
/// and render steps are: `addCommand('sink', …)` through the view of the
/// `boats.editor` plugin is the command `boats.sink`, and its component
/// `buoyancy` is `boats.buoyancy`. A name given whole, `boats.sink`, is
/// taken as it is; one in another namespace is refused with a
/// `PluginException`. A palette row is the exception: it is keyed by the
/// entity type it places, which is the level format's word and not the
/// plugin's. So a command or component the editor adds in a later minor
/// never collides with a plugin's, and two packages may each have a `sink`.
/// The application, adding through the root, names its pieces as it likes —
/// without a dot, so its names cannot pass for a plugin's.
///
/// **The rest of the editor's plugin contract is here too**: [addGizmo],
/// [addImporter] and [addAssetEntry], each published under the plugin's
/// namespace as a command is; and [hints], the [EditorHints] a plugin finds
/// with `host.maybeRegistry<EditorHintRegistry>()` without depending on this
/// package, which an inspector section, a palette row and a material
/// panel's controls are built from. Panels and docks are widgets, and so
/// `flutter3d_editor_widgets`' `EditorPanels`.
final class EditorPieces extends EditorRegistry {
  /// An editor's registry, empty.
  EditorPieces() : _store = _PieceStore(), _scope = null;

  EditorPieces._scoped(EditorPieces root, PluginScope scope)
    : _store = root._store,
      _scope = scope;

  final _PieceStore _store;
  final PluginScope? _scope;

  /// The hints plugins gave for their components, entity kinds and lit
  /// models: through a plugin's view, that plugin's view of them.
  late final EditorHints hints = switch (_scope) {
    final PluginScope scope => _store.hints.forPlugin(scope),
    null => _store.hints,
  };

  /// [hints], so a host handed this registry finds the hint slot as well:
  /// `host.maybeRegistry<EditorHintRegistry>()`.
  @override
  Iterable<PluginRegistry> get companions => <PluginRegistry>[_store.hints];

  /// Calls [onChange] whenever anything is added or withdrawn, hints
  /// included, until the registration it returns is cancelled. What a tool
  /// server listens with to keep the commands it offers in step; not
  /// tracked by a plugin's scope.
  Registration listen(void Function() onChange) {
    final entry = _Listener(onChange);
    _store.listeners.add(entry);
    final hearing = _store.hints.listen(onChange);
    return Registration(() {
      _store.listeners.remove(entry);
      hearing.cancel();
    });
  }

  String get _owner =>
      _scope == null ? 'the application' : 'plugin "${_scope.manifest.id}"';

  /// [name] as this view publishes it: through a plugin's view,
  /// `<namespace>.<name>` for a bare name and [name] itself when it is
  /// already in the plugin's namespace (`PluginManifest.qualify`); through
  /// the root, [name] itself.
  ///
  /// Throws an [ArgumentError] for an empty name, for a dotted one through
  /// the root, and for one with a dot of its own after the namespace's: the
  /// dot is the namespace's. Throws a [PluginException] for a name in
  /// another namespace than the plugin's, naming both.
  String published(String name, {String what = 'name'}) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, what, 'needs a name');
    }
    final scope = _scope;
    if (scope == null) {
      if (name.contains('.') && !builtInComponentKind(name)) {
        throw ArgumentError.value(
          name,
          what,
          'has a dot, which is the namespace\'s: the application names its '
          'pieces without one, so they cannot pass for a plugin\'s',
        );
      }
      return name;
    }
    final whole = scope.manifest.qualify(name, what: 'the $what');
    if (whole.indexOf('.') != whole.lastIndexOf('.')) {
      throw ArgumentError.value(
        name,
        what,
        'has a dot of its own: a plugin\'s pieces are published as '
        '`<namespace>.<name>`, one dot, the namespace\'s',
      );
    }
    return whole;
  }

  /// Whether [kind] is one of the editor's own component kinds, some of
  /// which are dotted (`brush.collision`).
  static bool builtInComponentKind(String kind) =>
      builtInComponents.any((EditorComponent c) => c.kind == kind);

  // ---------------------------------------------------------------- commands

  /// Every command name: the editor's own [editorCommandNames], then the
  /// plugins' in order.
  List<String> get commandNames => List<String>.unmodifiable(<String>[
    ...editorCommandNames,
    for (final added in _store.ordered(_store.commands)) added.name,
  ]);

  /// What the plugin command [name] was registered with as its description,
  /// or null. For a tool that lists the commands, or an editor's menu that
  /// offers them.
  String? descriptionOf(String name) => _store.commands
      .where((_Command c) => c.name == name)
      .firstOrNull
      ?.description;

  /// The arguments the plugin command [name] was registered with, empty for
  /// one registered without them or for a name nobody registered.
  List<FieldHint> argumentsOf(String name) =>
      _store.commands
          .where((_Command c) => c.name == name)
          .firstOrNull
          ?.arguments ??
      const <FieldHint>[];

  /// Every command the plugins added, in order, with what a tool server
  /// offers each as: its published name, the plugin it came from, its
  /// description, its arguments, its hints and whether its plugin may offer
  /// tools to an agent at all.
  List<PluginCommandInfo> get pluginCommands => <PluginCommandInfo>[
    for (final added in _store.ordered(_store.commands))
      PluginCommandInfo(
        name: added.name,
        plugin: added.scope?.manifest.id,
        description: added.description,
        arguments: added.arguments,
        hints: added.hints,
        offersTools:
            added.scope?.manifest.permissions.contains(
              PluginPermission.tools,
            ) ??
            false,
      ),
  ];

  /// Reads a command back from [json], whichever family it belongs to: the
  /// editor's own through [EditorCommand.fromJson], a plugin's through the
  /// reader registered for its name. Null for a name nobody registered and
  /// for arguments the reader refused.
  DocumentCommand? readCommand(Map<String, Object?> json) {
    final name = json['command'];
    if (name is! String) return null;
    if (editorCommandNames.contains(name)) return EditorCommand.fromJson(json);
    final added = _store.commands
        .where((_Command c) => c.name == name)
        .firstOrNull;
    if (added == null) return null;
    return added.read(<String, Object?>{
      for (final entry in json.entries)
        if (entry.key != 'command') entry.key: entry.value,
    });
  }

  /// Makes [name] a command, read back by [read], and answers the name it
  /// is published as: `<namespace>.<name>` through a plugin's view.
  ///
  /// [arguments] say what [read] takes, as an inspector field says what a
  /// property is: the editor's MCP server offers the command as a tool of
  /// its own, `<namespace>.<name>`, with these as its input schema, and an
  /// editor's menu can ask for them. Empty for a command that takes none,
  /// or whose arguments only `command.run` passes.
  ///
  /// [hints] say what the command does to the document, as an MCP tool's
  /// say what the tool does (`ToolHints.reads`, `writes`, `destroys`): what
  /// an agent is told before it calls the tool the command is offered as.
  /// **A command without them counts as destructive**, since nothing says
  /// it is not. And it is offered to agents at all only when its plugin
  /// declares `PluginPermission.tools`; without it the command stays the
  /// editor's, reachable through its menu and `command.run`.
  ///
  /// Throws an [ArgumentError] for an empty or dotted name, for one of the
  /// editor's own, and for a name another owner already registered, naming
  /// it.
  Registration addCommand(
    String written,
    CommandReader read, {
    String? description,
    List<FieldHint> arguments = const <FieldHint>[],
    ToolHints? hints,
  }) {
    if (written.isEmpty) {
      throw ArgumentError.value(written, 'name', 'a command needs a name');
    }
    final name = published(written, what: 'command');
    if (editorCommandNames.contains(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'is one of the editor\'s own commands',
      );
    }
    for (final existing in _store.commands) {
      if (existing.name != name) continue;
      throw ArgumentError.value(
        name,
        'name',
        'the command "$name" is already added, by ${existing.owner}',
      );
    }
    return _store.add(
      _store.commands,
      _Command(
        name,
        read,
        description,
        List<FieldHint>.unmodifiable(arguments),
        hints,
        _owner,
        _scope,
        _store.sequence++,
      ),
      _scope,
    );
  }

  // -------------------------------------------------------------- components

  /// The components added, in order.
  List<EditorComponent> get components =>
      List<EditorComponent>.unmodifiable(<EditorComponent>[
        for (final added in _store.ordered(_store.components)) added.component,
      ]);

  /// The components that belong on a [piece] of entity type [type]: those
  /// added, then for an entity those its type's [hints] build — the kind's
  /// own fields, kind `type:<type>`, and every [ComponentHints] that names
  /// the type or that the kind names.
  List<EditorComponent> componentsFor(Piece piece, {String? type}) =>
      <EditorComponent>[
        for (final component in components)
          if (component.appliesTo(piece, type: type)) component,
        if (piece == Piece.entity && type != null) ...[
          if (_store.hints.entityKind(type) case final EntityKindHints kind
              when kind.fields.isNotEmpty)
            _hinted('type:$type', kind.title, kind.fields, type),
          for (final hinted in _store.hints.componentsOf(type))
            _hinted(hinted.id, hinted.title, hinted.fields, type),
        ],
      ];

  static EditorComponent _hinted(
    String kind,
    String title,
    List<FieldHint> fields,
    String type,
  ) => EditorComponent(
    kind: kind,
    title: title,
    keys: <String>{
      for (final field in fields)
        if (field.defaultValue == null) field.key,
    },
    defaults: <String, Object?>{
      for (final field in fields)
        if (field.defaultValue != null) field.key: field.defaultValue,
    },
    types: <String>{type},
    hints: fields,
  );

  /// The hint for the field [key] of a [piece] of entity type [type], from
  /// the first component that hints it; null for a field shown by its
  /// value's shape.
  FieldHint? fieldHint(Piece piece, String key, {String? type}) {
    for (final component in componentsFor(piece, type: type)) {
      if (component.hintFor(key) case final FieldHint hint) return hint;
    }
    return null;
  }

  /// Why [value] cannot be the field [key] of a [piece] of entity type
  /// [type], by its hint, or null when it can or nothing hints it.
  String? refusalOf(Piece piece, String key, Object? value, {String? type}) =>
      fieldHint(piece, key, type: type)?.refusalOf(value);

  /// The material panel's control for the parameter [key] of a material
  /// whose lighting model is [model], from the hints a plugin gave that
  /// model; null when none did. See [materialHintOf].
  MaterialHint? materialHint(String? model, String key) {
    if (model == null) return null;
    final field = _store.hints.material(model)?[key];
    return field == null ? null : materialHintOf(field);
  }

  /// The fields the components of [piece] (of entity type [type]) offer that
  /// [present] does not hold, at their defaults — what an inspector lists as
  /// not set, beside the format's own.
  Map<String, Object?> offersFor(
    Piece piece,
    Iterable<String> present, {
    String? type,
  }) {
    final has = present.toSet();
    return <String, Object?>{
      for (final component in componentsFor(piece, type: type))
        for (final entry in component.defaults.entries)
          if (!has.contains(entry.key)) entry.key: entry.value,
    };
  }

  /// Adds [written] to the inspector, its kind published as
  /// `<namespace>.<kind>` through a plugin's view.
  ///
  /// Throws an [ArgumentError] for a kind one of the editor's own components
  /// has, and for a kind another owner already added, naming it.
  Registration addComponent(EditorComponent written) {
    final kind = published(written.kind, what: 'component');
    if (builtInComponentKind(kind)) {
      throw ArgumentError.value(
        kind,
        'component',
        'is one of the editor\'s own components',
      );
    }
    final component = kind == written.kind
        ? written
        : EditorComponent(
            kind: kind,
            title: written.title,
            piece: written.piece,
            keys: written.keys,
            defaults: written.defaults,
            types: written.types,
          );
    for (final existing in _store.components) {
      if (existing.component.kind != kind) continue;
      throw ArgumentError.value(
        kind,
        'component',
        'the component "$kind" is already added, by ${existing.owner}',
      );
    }
    return _store.add(
      _store.components,
      _Component(component, _owner, _scope, _store.sequence++),
      _scope,
    );
  }

  // ----------------------------------------------------------------- palette

  /// The palette entries added, in order, then a row for every entity kind
  /// the [hints] name that no entry added offers: its label, its tint, and
  /// its fields' and its components' defaults as what a placed one starts
  /// with.
  List<PaletteEntry> get paletteEntries {
    final added = <PaletteEntry>[
      for (final added in _store.ordered(_store.palette)) added.entry,
    ];
    final offered = <String>{for (final entry in added) entry.type};
    return List<PaletteEntry>.unmodifiable(<PaletteEntry>[
      ...added,
      for (final kind in _store.hints.entityKinds)
        if (!offered.contains(kind.type))
          PaletteEntry(
            kind.type,
            label: kind.label,
            tint: kind.tint,
            properties: <String, Object?>{
              for (final component in _store.hints.componentsOf(kind.type))
                for (final field in component.fields)
                  if (field.defaultValue != null) field.key: field.defaultValue,
              ...kind.defaults,
            },
          ),
    ]);
  }

  /// Adds [entry] to the palette.
  ///
  /// **Keyed by the entity type it places, not namespaced**: a type is the
  /// level format's word, read by every genre that speaks it, as
  /// `EntityKinds` keys its kinds. Throws an [ArgumentError] for a type
  /// another owner already offers, naming it.
  Registration addPaletteEntry(PaletteEntry entry) {
    for (final existing in _store.palette) {
      if (existing.entry.type != entry.type) continue;
      throw ArgumentError.value(
        entry.type,
        'entry',
        'the palette already offers "${entry.type}", added by '
            '${existing.owner}',
      );
    }
    return _store.add(
      _store.palette,
      _Entry(entry, _owner, _scope, _store.sequence++),
      _scope,
    );
  }

  // ------------------------------------------------------------------ gizmos

  /// Draws [gizmo] over every thing of a level it applies to, its name
  /// published as `<namespace>.<name>` through a plugin's view.
  ///
  /// Throws an [ArgumentError] for an empty or dotted name, and for a name
  /// another owner already added, naming it.
  Registration addGizmo(String written, EditorGizmo gizmo) {
    final name = published(written, what: 'gizmo');
    _refuseTaken(_store.gizmos, name, 'gizmo');
    return _store.add(
      _store.gizmos,
      _Gizmo(name, gizmo, _owner, _scope, _store.sequence++),
      _scope,
    );
  }

  /// The gizmos added, in order, by published name.
  List<String> get gizmoNames => <String>[
    for (final added in _store.ordered(_store.gizmos)) added.name,
  ];

  /// What every gizmo draws over [level]: for each thing it applies to, its
  /// marks, in the order the gizmos were added and the level lists things.
  /// [selected] says which things are selected.
  ///
  /// **A gizmo that throws draws nothing**, and the others still draw: a
  /// plugin's mistake costs its own marks, not the viewport.
  List<DrawnMark> marksFor(
    Level level, {
    Iterable<Picked> selected = const <Picked>[],
  }) {
    final chosen = selected.toSet();
    final things = <(Piece, int)>[
      for (var i = 0; i < level.brushes.length; i++) (Piece.brush, i),
      for (var i = 0; i < level.lights.length; i++) (Piece.light, i),
      for (var i = 0; i < level.entities.length; i++) (Piece.entity, i),
    ];
    return <DrawnMark>[
      for (final added in _store.ordered(_store.gizmos))
        for (final (kind, index) in things)
          ..._marksOf(
            added,
            GizmoContext(
              level: level,
              kind: kind,
              index: index,
              selected: chosen.contains((kind: kind, index: index)),
            ),
          ),
    ];
  }

  static List<DrawnMark> _marksOf(_Gizmo added, GizmoContext context) {
    try {
      if (!added.gizmo.appliesTo(context)) return const <DrawnMark>[];
      return <DrawnMark>[
        for (final mark in added.gizmo.marksFor(context))
          DrawnMark(
            gizmo: added.name,
            kind: context.kind,
            index: context.index,
            mark: mark,
          ),
      ];
    } on Object {
      return const <DrawnMark>[];
    }
  }

  /// The command a drag of [drawn]'s handle from [from] to [to] is, as its
  /// gizmo answers; null for a mark without a handle, a gizmo no longer
  /// added, or a gizmo that leaves the document alone.
  DocumentCommand? dragged(
    DrawnMark drawn,
    Level level, {
    required Vector3 from,
    required Vector3 to,
  }) {
    final handle = drawn.mark.handle;
    if (handle == null) return null;
    final added = _store.gizmos
        .where((_Gizmo g) => g.name == drawn.gizmo)
        .firstOrNull;
    return added?.gizmo.dragged(
      GizmoDrag(
        target: GizmoContext(
          level: level,
          kind: drawn.kind,
          index: drawn.index,
          selected: true,
        ),
        handle: handle,
        from: from,
        to: to,
      ),
    );
  }

  // --------------------------------------------------------------- importers

  /// Lets [importer] bring its kind of file into a project, its name
  /// published as `<namespace>.<name>` through a plugin's view.
  ///
  /// Throws an [ArgumentError] for an empty or dotted name, and for a name
  /// another owner already added, naming it.
  Registration addImporter(String written, EditorImporter importer) {
    final name = published(written, what: 'importer');
    _refuseTaken(_store.importers, name, 'importer');
    return _store.add(
      _store.importers,
      _Importer(name, importer, _owner, _scope, _store.sequence++),
      _scope,
    );
  }

  /// The importers added, in order.
  List<AddedImporter> get importers => <AddedImporter>[
    for (final added in _store.ordered(_store.importers))
      AddedImporter(added.name, added.importer),
  ];

  /// The first importer that reads [path], by its suffix without case, or
  /// null.
  AddedImporter? importerFor(String path) {
    final lower = path.toLowerCase();
    for (final added in importers) {
      if (added.importer.suffixes.any(
        (String s) => lower.endsWith(s.toLowerCase()),
      )) {
        return added;
      }
    }
    return null;
  }

  // ----------------------------------------------------------- asset browser

  /// Lists [entry]'s kind of file in the asset browser, its name published
  /// as `<namespace>.<name>` through a plugin's view.
  ///
  /// Throws an [ArgumentError] for an empty or dotted name, and for a name
  /// another owner already added, naming it.
  Registration addAssetEntry(String written, AssetBrowserEntry entry) {
    final name = published(written, what: 'asset entry');
    _refuseTaken(_store.assets, name, 'asset entry');
    return _store.add(
      _store.assets,
      _Asset(name, entry, _owner, _scope, _store.sequence++),
      _scope,
    );
  }

  /// Every asset-browser entry: those added, in order, then
  /// [builtInAssetEntries]. Asked in this order, so a plugin may claim a
  /// suffix the editor lists too.
  List<AddedAssetEntry> get assetEntries => <AddedAssetEntry>[
    for (final added in _store.ordered(_store.assets))
      AddedAssetEntry(added.name, added.entry),
    ...builtInAssetEntries,
  ];

  /// The first entry of [assetEntries] that [path] matches, or null for a
  /// file the browser does not list.
  AddedAssetEntry? assetEntryFor(String path) {
    for (final added in assetEntries) {
      if (added.entry.matches(path)) return added;
    }
    return null;
  }

  void _refuseTaken(List<_Named> taken, String name, String what) {
    for (final existing in taken) {
      if (existing.name != name) continue;
      throw ArgumentError.value(
        name,
        what,
        'the $what "$name" is already added, by ${existing.owner}',
      );
    }
  }

  @override
  EditorPieces forPlugin(PluginScope scope) =>
      EditorPieces._scoped(this, scope);
}

/// One command a plugin added, as a tool server offers it.
final class PluginCommandInfo {
  const PluginCommandInfo({
    required this.name,
    required this.plugin,
    required this.description,
    required this.arguments,
    this.hints,
    this.offersTools = false,
  });

  /// What the command does to the document, as its plugin said with
  /// `EditorPieces.addCommand(hints:)`, or null where it said nothing:
  /// then a tool server offers it as [ToolHints.destroys], since nothing
  /// says it is safer ([toolHints]).
  final ToolHints? hints;

  /// Whether its plugin declares `PluginPermission.tools`: the one way a
  /// command reaches an agent as a tool of its own. False for one the
  /// application added.
  final bool offersTools;

  /// The hints a tool server offers the command with: [hints], or
  /// [ToolHints.destroys] when it gave none.
  ToolHints get toolHints => hints ?? ToolHints.destroys;

  /// Its published name, `<namespace>.<name>`.
  final String name;

  /// The plugin's id, or null for a command the application added.
  final String? plugin;

  /// What it was registered with as its description, or null.
  final String? description;

  /// What it takes, as hints; empty when it was registered without them.
  final List<FieldHint> arguments;

  /// The namespace it is published under, `PluginManifest.namespace` of its
  /// plugin, or null for a command the application added.
  String? get namespace {
    if (plugin == null) return null;
    final dot = name.indexOf('.');
    return dot < 0 ? null : name.substring(0, dot);
  }

  /// The command's own name, without the namespace.
  String get bareName => switch (namespace) {
    final String space => name.substring(space.length + 1),
    null => name,
  };
}

final class _Listener {
  _Listener(this.onChange);

  final void Function() onChange;
}

/// What an [EditorPieces] and all its scoped views share.
final class _PieceStore {
  final List<_Command> commands = <_Command>[];
  final List<_Component> components = <_Component>[];
  final List<_Entry> palette = <_Entry>[];
  final List<_Gizmo> gizmos = <_Gizmo>[];
  final List<_Importer> importers = <_Importer>[];
  final List<_Asset> assets = <_Asset>[];
  final List<_Listener> listeners = <_Listener>[];
  final EditorHints hints = EditorHints();
  int sequence = 0;

  Registration add<T extends _Added>(
    List<T> into,
    T added,
    PluginScope? scope,
  ) {
    into.add(added);
    changed();
    final registration = Registration(() {
      if (into.remove(added)) changed();
    });
    scope?.track(registration);
    return registration;
  }

  void changed() {
    for (final listener in List<_Listener>.of(listeners)) {
      listener.onChange();
    }
  }

  /// [added] in the application's order first, then each plugin's by rank,
  /// and within one owner as added. The rank is read now, not when added, so
  /// a reorder of the plugins reorders what they brought.
  List<T> ordered<T extends _Added>(List<T> added) =>
      List<T>.of(added)..sort(_Added.compare);
}

abstract base class _Added {
  _Added(this.owner, this.scope, this.sequence);

  final String owner;
  final PluginScope? scope;
  final int sequence;

  int get rank => scope?.rank ?? -1;

  static int compare(_Added a, _Added b) {
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.sequence.compareTo(b.sequence);
  }
}

/// Something added under a published name.
abstract base class _Named extends _Added {
  _Named(this.name, super.owner, super.scope, super.sequence);

  final String name;
}

final class _Command extends _Named {
  _Command(
    super.name,
    this.read,
    this.description,
    this.arguments,
    this.hints,
    super.owner,
    super.scope,
    super.sequence,
  );

  final CommandReader read;
  final String? description;
  final List<FieldHint> arguments;
  final ToolHints? hints;
}

final class _Gizmo extends _Named {
  _Gizmo(super.name, this.gizmo, super.owner, super.scope, super.sequence);

  final EditorGizmo gizmo;
}

final class _Importer extends _Named {
  _Importer(
    super.name,
    this.importer,
    super.owner,
    super.scope,
    super.sequence,
  );

  final EditorImporter importer;
}

final class _Asset extends _Named {
  _Asset(super.name, this.entry, super.owner, super.scope, super.sequence);

  final AssetBrowserEntry entry;
}

final class _Component extends _Added {
  _Component(this.component, super.owner, super.scope, super.sequence);

  final EditorComponent component;
}

final class _Entry extends _Added {
  _Entry(this.entry, super.owner, super.scope, super.sequence);

  final PaletteEntry entry;
}
