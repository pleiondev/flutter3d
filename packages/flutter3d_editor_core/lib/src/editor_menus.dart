/// What a plugin adds to an editor's chrome: a menu entry, a toolbar
/// button, a key that runs a command, and a tool mode that takes the
/// viewport's pointer while it is on.
///
/// Each is a value the editor's widgets draw, filed under the plugin's
/// namespace by `EditorPieces` and withdrawn with the plugin; none of them
/// holds a widget, so this package stays below Flutter.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart' show Level;
import 'package:vector_math/vector_math.dart';

import 'editing.dart' show Picked;
import 'editor_command.dart';
import 'plugin_gizmos.dart';

/// A key and the modifiers held with it: what runs a menu entry from the
/// keyboard.
///
/// Written `ctrl+shift+k` ([toString], [parse]): the modifiers in this
/// order, then one key, lower case. `ctrl` is the platform's command key on
/// a Mac, as every editor's own shortcuts are.
final class EditorShortcut {
  const EditorShortcut(
    this.key, {
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  /// [written]: modifiers and a key joined by `+`, a key one word of
  /// letters, digits or a name such as `f5` or `delete`.
  ///
  /// Throws an [ArgumentError] naming [written] for a text that is not a
  /// shortcut, a modifier it does not know or one held twice: a shortcut is
  /// written in a plugin's source, and a misspelled one is a mistake there,
  /// not a menu entry quietly left without its key.
  static EditorShortcut parse(String written) {
    final parts = written.toLowerCase().split('+');
    final key = parts.last;
    final held = parts.sublist(0, parts.length - 1);
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(key) ||
        held.any((String p) => !_modifiers.contains(p)) ||
        held.toSet().length != held.length) {
      throw ArgumentError.value(
        written,
        'written',
        'is not a shortcut: modifiers from ${_modifiers.join(', ')}, each '
            'once, then one key, joined by "+"',
      );
    }
    return EditorShortcut(
      key,
      control: held.contains('ctrl'),
      shift: held.contains('shift'),
      alt: held.contains('alt'),
    );
  }

  static const List<String> _modifiers = <String>['ctrl', 'shift', 'alt'];

  /// The key, lower case: `k`, `f5`, `delete`.
  final String key;

  /// Whether the control key — the command key on a Mac — is held.
  final bool control;

  /// Whether shift is held.
  final bool shift;

  /// Whether alt — option on a Mac — is held.
  final bool alt;

  @override
  bool operator ==(Object other) =>
      other is EditorShortcut &&
      other.key == key &&
      other.control == control &&
      other.shift == shift &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(key, control, shift, alt);

  @override
  String toString() => <String>[
    if (control) 'ctrl',
    if (shift) 'shift',
    if (alt) 'alt',
    key,
  ].join('+');
}

/// An entry a plugin adds to one of the editor's menus: a label, and the
/// command it runs.
///
/// **A command, by name**: one the plugin added with
/// `EditorPieces.addCommand` (a bare name is its own), or one of the
/// editor's own (`editorCommandNames`), run with [arguments] as one step of
/// undo, by the route a key and an agent take.
final class EditorMenuItem {
  const EditorMenuItem({
    required this.name,
    required this.label,
    required this.command,
    this.menu = pluginsMenu,
    this.arguments = const <String, Object?>{},
    this.shortcut,
  });

  /// The menu a plugin's entry goes into when it names none.
  static const String pluginsMenu = 'Plugins';

  /// Its id, published as `<namespace>.<name>`.
  final String name;

  /// What the entry reads.
  final String label;

  /// The menu it is in, by its title: `Plugins`, `Tools`, `Edit`; a path
  /// with `/` for a submenu, `Tools/Terrain`. An editor that has no menu
  /// of the name adds one.
  final String menu;

  /// The command it runs.
  final String command;

  /// What the command is run with.
  final Map<String, Object?> arguments;

  /// The key that runs it from anywhere in the editor, or null.
  final EditorShortcut? shortcut;
}

/// A button a plugin adds to the editor's toolbar: a command to run, or a
/// tool mode to switch on.
final class EditorToolbarItem {
  /// A button that runs [command] with [arguments], as a menu entry does.
  const EditorToolbarItem.command({
    required this.name,
    required this.label,
    required String this.command,
    this.icon,
    this.arguments = const <String, Object?>{},
  }) : toolMode = null;

  /// A button that switches the tool mode [toolMode] on, and off again.
  const EditorToolbarItem.toolMode({
    required this.name,
    required this.label,
    required String this.toolMode,
    this.icon,
  }) : command = null,
       arguments = const <String, Object?>{};

  /// Its id, published as `<namespace>.<name>`.
  final String name;

  /// Its tooltip, and its text where it has no [icon].
  final String label;

  /// The Material icon it is drawn with, by name (`water_drop`), or null
  /// for its [label]. An editor that has no icon of the name draws the
  /// label.
  final String? icon;

  /// The command it runs, or null for a tool mode's button.
  final String? command;

  /// What [command] is run with.
  final Map<String, Object?> arguments;

  /// The tool mode it switches, or null for a command's button.
  final String? toolMode;
}

/// What the pointer did in the viewport, which a tool mode answers.
///
/// A class with constants rather than an enum, so an event added in a
/// minor (a hover, a double press) breaks no `switch`; a mode that meets
/// one it does not know answers nothing.
final class ToolModeEvent {
  const ToolModeEvent._(this.name);

  /// The pointer went down.
  static const ToolModeEvent press = ToolModeEvent._('press');

  /// The pointer moved while down.
  static const ToolModeEvent drag = ToolModeEvent._('drag');

  /// The pointer went up.
  static const ToolModeEvent release = ToolModeEvent._('release');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<ToolModeEvent> values = <ToolModeEvent>[
    press,
    drag,
    release,
  ];

  /// The value called [name], or null for a name this version does not
  /// know.
  static ToolModeEvent? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name. Never renamed within a major.
  final String name;

  @override
  String toString() => 'ToolModeEvent.$name';
}

/// What a tool mode is handed while the pointer is in the viewport: the
/// level, where the pointer meets it, and what is under it.
///
/// Made by the editor for each event, never by a plugin. **One object, so
/// it can grow**: a member added in a minor reaches every mode without
/// changing a signature.
final class ToolModeInput {
  ToolModeInput({
    required this.level,
    required Vector3 point,
    this.picked,
    this.selected = const <Picked>[],
    this.shift = false,
  }) : point = point.clone();

  /// The level being edited.
  final Level level;

  /// Where the pointer meets the level — what is under it, else the ground
  /// plane — in metres.
  final Vector3 point;

  /// The thing under the pointer, or null.
  final Picked? picked;

  /// What is selected, in order.
  final List<Picked> selected;

  /// Whether shift is held.
  final bool shift;
}

/// A way of using the viewport a plugin adds — painting, placing along a
/// path, measuring — which takes the pointer while it is on.
///
/// **Modal, and one at a time.** Switching a tool mode on (its toolbar
/// button, or `EditorPieces.toolModeNamed`) switches the editor's own
/// selection off until it is switched off again; a press, a drag and a
/// release in the viewport go to it, and each may answer a command the
/// editor runs as one step of undo. What it previews is drawn as a gizmo
/// draws.
///
/// **A mode that throws does nothing**, and the editor stays: it is
/// somebody else's code in the middle of somebody's work. Extendable
/// outside this package, and stays so through 1.x.
abstract base class EditorToolMode {
  const EditorToolMode();

  /// What its button and the status bar call it.
  String get label;

  /// The command a press at [input] is, or null for none.
  DocumentCommand? pressed(ToolModeInput input) => null;

  /// The command a drag to [input] is, or null for none.
  DocumentCommand? dragged(ToolModeInput input) => null;

  /// The command letting go at [input] is, or null for none.
  DocumentCommand? released(ToolModeInput input) => null;

  /// What it draws while the pointer is at [input] and nothing is pressed.
  List<GizmoMark> preview(ToolModeInput input) => const <GizmoMark>[];
}
