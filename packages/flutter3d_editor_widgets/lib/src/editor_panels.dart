/// Panels a plugin brings to an editor: docked beside the picture, or on the
/// main screen in its place.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'dock_layout.dart';

/// One selected thing of the open document, in the words a level writes:
/// the list it is in (`brush`, `light`, `entity`) and its index there.
final class PanelSelection {
  const PanelSelection({required this.piece, required this.index});

  final String piece;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is PanelSelection && other.piece == piece && other.index == index;

  @override
  int get hashCode => Object.hash(piece, index);

  @override
  String toString() => '$piece $index';
}

/// What a plugin's panel is built with: the open document, the selection,
/// and the one way to change the document, a command.
///
/// **A command, as the editor's MCP server takes it**: `{"command":
/// "boats.sink", "depth": 2}`. A panel changes the document by the route a
/// key, a menu and an agent take, so its edit is one step of undo and is
/// said on the bar like any other.
///
/// **In plain values** (the document as its JSON, the selection by list and
/// index), because this package stands below the editor's document layer;
/// a panel that wants a `Level` reads one from [document].
///
/// Made by the editor for each build, never by a plugin. **One object, so
/// it can grow.**
final class EditorPanelContext {
  const EditorPanelContext({
    required this.context,
    required this.document,
    required this._run,
    this.selection = const <PanelSelection>[],
    this.path,
    this._say,
  });

  /// Where in the widget tree the panel is built.
  final BuildContext context;

  /// The open document, as it would be written now.
  final Map<String, Object?> document;

  /// What is selected, in order.
  final List<PanelSelection> selection;

  /// Where the document lives, or null for one not saved yet.
  final String? path;

  final bool Function(Map<String, Object?> command) _run;
  final void Function(String says)? _say;

  /// Runs [command], a command's JSON with its name under `command`, as one
  /// step of undo. False, having changed nothing, for a command the editor
  /// does not know, cannot read, or that does not apply.
  bool run(Map<String, Object?> command) => _run(command);

  /// Says [says] on the editor's bar and in its console.
  void say(String says) => _say?.call(says);
}

/// A panel a plugin adds: its id, its title and icon, where it goes, and
/// what it shows.
final class EditorPanel {
  const EditorPanel({
    required this.id,
    required this.title,
    required this.builder,
    this.icon = Icons.extension_outlined,
    this.dock,
  });

  /// Its id, published as `<pluginId>.<id>`: what a stored arrangement
  /// remembers it by.
  final String id;

  final String title;
  final IconData icon;

  /// The side it docks to until somebody moves it, or null for a panel of
  /// the main screen, shown in the picture's place when chosen.
  final DockSide? dock;

  /// What it shows.
  final Widget Function(EditorPanelContext panel) builder;
}

/// The panels plugins bring to an editor: the registry a plugin finds with
/// `host.registry<EditorPanels>()`, and the editor hands its plugin host.
///
/// **Published under the plugin's id**, as its commands and tools are: a
/// panel `tide` of the `boats` plugin is `boats.tide`, so a panel the editor
/// adds in a minor never takes a plugin's place in a stored arrangement.
/// Through the root the application names its panels as it likes, without
/// a dot. Switching a plugin off withdraws its panels; [listen] hears it.
///
/// What is added comes back out in order: the application's first, then
/// each plugin's in install order, and within one owner as added.
final class EditorPanels extends PluginRegistry {
  /// An editor's registry, empty.
  EditorPanels() : _store = _PanelStore(), _scope = null;

  EditorPanels._scoped(EditorPanels root, PluginScope scope)
    : _store = root._store,
      _scope = scope;

  final _PanelStore _store;
  final PluginScope? _scope;

  /// Adds [panel], its id published as `<pluginId>.<id>` through a plugin's
  /// view.
  ///
  /// Throws an [ArgumentError] for an empty or dotted id, and for an id
  /// another owner already added, naming it.
  Registration addPanel(EditorPanel panel) {
    final written = panel.id;
    if (written.isEmpty) {
      throw ArgumentError.value(written, 'id', 'a panel needs an id');
    }
    if (written.contains('.')) {
      throw ArgumentError.value(
        written,
        'id',
        'has a dot, which is the namespace\'s: a plugin\'s panels are '
            'published as `<plugin id>.<id>` for it',
      );
    }
    final scope = _scope;
    final id = scope == null ? written : '${scope.manifest.id}.$written';
    final owner = scope == null
        ? 'the application'
        : 'plugin "${scope.manifest.id}"';
    for (final existing in _store.panels) {
      if (existing.panel.id != id) continue;
      throw ArgumentError.value(
        id,
        'id',
        'the panel "$id" is already added, by ${existing.owner}',
      );
    }
    final added = _Added(
      EditorPanel(
        id: id,
        title: panel.title,
        icon: panel.icon,
        dock: panel.dock,
        builder: panel.builder,
      ),
      owner,
      scope,
      _store.sequence++,
    );
    _store.panels.add(added);
    _store.changed();
    final registration = Registration(() {
      if (_store.panels.remove(added)) _store.changed();
    });
    scope?.track(registration);
    return registration;
  }

  /// Every panel added, in order.
  List<EditorPanel> get panels => <EditorPanel>[
    for (final added in List<_Added>.of(_store.panels)..sort(_Added.compare))
      added.panel,
  ];

  /// The panels that dock to a side.
  List<EditorPanel> get docked => <EditorPanel>[
    for (final panel in panels)
      if (panel.dock != null) panel,
  ];

  /// The panels of the main screen.
  List<EditorPanel> get mainScreen => <EditorPanel>[
    for (final panel in panels)
      if (panel.dock == null) panel,
  ];

  /// [docked] as a [DockLayout]'s panels, each built with the context
  /// [contextOf] makes for it.
  ///
  /// **A panel that throws shows why** in its own place, with the plugin's
  /// error, rather than taking the editor's window down: it is somebody
  /// else's code in the middle of somebody's work.
  List<DockPanel> dockPanels(
    EditorPanelContext Function(BuildContext context) contextOf,
  ) => <DockPanel>[
    for (final panel in docked)
      DockPanel(
        id: panel.id,
        title: panel.title,
        icon: panel.icon,
        side: panel.dock!,
        builder: (BuildContext context) => build(panel, contextOf(context)),
      ),
  ];

  /// [panel]'s contents with [context], or why it could not be built.
  static Widget build(EditorPanel panel, EditorPanelContext context) {
    try {
      return panel.builder(context);
    } on Object catch (error) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          '${panel.title} could not be shown: $error',
          style: TextStyle(color: Theme.of(context.context).colorScheme.error),
        ),
      );
    }
  }

  /// Calls [onChange] whenever a panel is added or withdrawn, until the
  /// registration it returns is cancelled. Not tracked by a plugin's scope.
  Registration listen(void Function() onChange) {
    final entry = _Listener(onChange);
    _store.listeners.add(entry);
    return Registration(() => _store.listeners.remove(entry));
  }

  @override
  EditorPanels forPlugin(PluginScope scope) =>
      EditorPanels._scoped(this, scope);
}

final class _Added {
  _Added(this.panel, this.owner, this.scope, this.sequence);

  final EditorPanel panel;
  final String owner;
  final PluginScope? scope;
  final int sequence;

  int get rank => scope?.rank ?? -1;

  static int compare(_Added a, _Added b) {
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.sequence.compareTo(b.sequence);
  }
}

final class _Listener {
  _Listener(this.onChange);

  final void Function() onChange;
}

final class _PanelStore {
  final List<_Added> panels = <_Added>[];
  final List<_Listener> listeners = <_Listener>[];
  int sequence = 0;

  void changed() {
    for (final listener in List<_Listener>.of(listeners)) {
      listener.onChange();
    }
  }
}
