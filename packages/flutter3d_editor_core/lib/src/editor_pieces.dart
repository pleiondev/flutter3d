/// The editor's side of the plugin API: [EditorPieces], through which a plugin
/// brings commands, inspector components and palette entries.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:vector_math/vector_math.dart';

import 'editor_command.dart';
import 'gizmos.dart';
import 'inspector_sections.dart';

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

  /// Every field it shows: [keys] and the keys of [defaults].
  Set<String> get fields => <String>{...keys, ...defaults.keys};

  /// Whether it belongs on a [piece] of entity type [type].
  bool appliesTo(Piece piece, [String? type]) =>
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

  /// The colour the row and the gizmo are drawn in, or null for the colour
  /// the type's name picks.
  final Vector3? tint;

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
/// **A plugin's pieces are published under its id**, as its MCP tools are:
/// `addCommand('sink', …)` through the `boats` plugin's view is the command
/// `boats.sink` and its component `buoyancy` is `boats.buoyancy`. A palette
/// row is the exception: it is keyed by the entity type it places, which is
/// the level format's word and not the plugin's. So a command
/// or component the editor adds in a later minor never collides with a
/// plugin's, and two plugins may each have a `sink`. The application, adding
/// through the root, names its pieces as it likes — without a dot, so its
/// names cannot pass for a plugin's.
final class EditorPieces extends EditorRegistry {
  /// An editor's registry, empty.
  EditorPieces() : _store = _PieceStore(), _scope = null;

  EditorPieces._scoped(EditorPieces root, PluginScope scope)
    : _store = root._store,
      _scope = scope;

  final _PieceStore _store;
  final PluginScope? _scope;

  String get _owner =>
      _scope == null ? 'the application' : 'plugin "${_scope.manifest.id}"';

  /// [name] as this view publishes it: `<pluginId>.<name>` through a
  /// plugin's view, [name] itself through the root.
  ///
  /// Throws an [ArgumentError] for an empty name, and for a dotted one
  /// through the root or a plugin's view: the dot is the namespace's.
  String published(String name, {String what = 'name'}) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, what, 'needs a name');
    }
    if (name.contains('.') && !builtInComponentKind(name)) {
      throw ArgumentError.value(
        name,
        what,
        'has a dot, which is the namespace\'s: a plugin\'s pieces are '
        'published as `<plugin id>.<name>` for it',
      );
    }
    final scope = _scope;
    return scope == null ? name : '${scope.manifest.id}.$name';
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
  /// offers them; nothing in this repository lists plugin commands yet.
  String? descriptionOf(String name) => _store.commands
      .where((_Command c) => c.name == name)
      .firstOrNull
      ?.description;

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
  /// is published as: `<pluginId>.<name>` through a plugin's view.
  ///
  /// Throws an [ArgumentError] for an empty or dotted name, for one of the
  /// editor's own, and for a name another owner already registered, naming
  /// it.
  Registration addCommand(
    String written,
    CommandReader read, {
    String? description,
  }) {
    if (written.isEmpty) {
      throw ArgumentError.value(written, 'name', 'a command needs a name');
    }
    final name = published(written);
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
      _Command(name, read, description, _owner, _scope, _store.sequence++),
      _scope,
    );
  }

  // -------------------------------------------------------------- components

  /// The components added, in order.
  List<EditorComponent> get components =>
      List<EditorComponent>.unmodifiable(<EditorComponent>[
        for (final added in _store.ordered(_store.components)) added.component,
      ]);

  /// The components added that belong on a [piece] of entity type [type].
  List<EditorComponent> componentsFor(Piece piece, [String? type]) =>
      <EditorComponent>[
        for (final component in components)
          if (component.appliesTo(piece, type)) component,
      ];

  /// The fields the components of [piece] (of entity type [type]) offer that
  /// [present] does not hold, at their defaults — what an inspector lists as
  /// not set, beside the format's own.
  Map<String, Object?> offersFor(
    Piece piece,
    Iterable<String> present, [
    String? type,
  ]) {
    final has = present.toSet();
    return <String, Object?>{
      for (final component in componentsFor(piece, type))
        for (final entry in component.defaults.entries)
          if (!has.contains(entry.key)) entry.key: entry.value,
    };
  }

  /// Adds [written] to the inspector, its kind published as
  /// `<pluginId>.<kind>` through a plugin's view.
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

  /// The palette entries added, in order.
  List<PaletteEntry> get paletteEntries =>
      List<PaletteEntry>.unmodifiable(<PaletteEntry>[
        for (final added in _store.ordered(_store.palette)) added.entry,
      ]);

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

  @override
  EditorPieces forPlugin(PluginScope scope) =>
      EditorPieces._scoped(this, scope);
}

/// What an [EditorPieces] and all its scoped views share.
final class _PieceStore {
  final List<_Command> commands = <_Command>[];
  final List<_Component> components = <_Component>[];
  final List<_Entry> palette = <_Entry>[];
  int sequence = 0;

  Registration add<T extends _Added>(
    List<T> into,
    T added,
    PluginScope? scope,
  ) {
    into.add(added);
    final registration = Registration(() => into.remove(added));
    scope?.track(registration);
    return registration;
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

final class _Command extends _Added {
  _Command(
    this.name,
    this.read,
    this.description,
    super.owner,
    super.scope,
    super.sequence,
  );

  final String name;
  final CommandReader read;
  final String? description;
}

final class _Component extends _Added {
  _Component(this.component, super.owner, super.scope, super.sequence);

  final EditorComponent component;
}

final class _Entry extends _Added {
  _Entry(this.entry, super.owner, super.scope, super.sequence);

  final PaletteEntry entry;
}
