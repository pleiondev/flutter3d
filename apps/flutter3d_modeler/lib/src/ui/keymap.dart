/// Which key does what, per preset — `ux-10`.
///
/// **One table per preset over the same tool ids, not three copies of the
/// tool table.** `tools.dart` is the one place a tool is written down: its
/// id, its label, its icon, the rail it sits on. What a preset changes is
/// only which key reaches it, so a preset here is a map from tool id to
/// activator and nothing else — and the help screen, the tooltips and the
/// command palette all read whichever preset is live rather than reading
/// `ModelerTool.shortcut` directly.
///
/// **Named for what they are rather than after another product.** The
/// review's own §4.3 lays the conflict out as "this key means move in one
/// school and scale in the other", and the two schools are real; naming a
/// preset after the program somebody last used asks them which program they
/// used rather than which behaviour they want, and tells somebody who has
/// used neither nothing at all. [KeymapPreset.modalKeys] is the school where
/// `G`/`R`/`S` start a modal transform; [KeymapPreset.toolKeys] is the one
/// where `W`/`E`/`R` arm a tool and `Q` goes back to selecting.
///
/// **The application's own actions are here too**, because they are where
/// the review found the real holes: no ⌘S at all, `Delete` and `Backspace`
/// bound to nothing, no `Tab` between object and mesh, no way to frame the
/// selection from the keyboard, and `F` spent on "flip normals" — the letter
/// every other package in the field spends on framing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../settings.dart' show KeymapPreset;
import 'tools.dart';

/// Something the application does that is not a tool on the rail.
enum ModelerAction {
  save,
  undo,
  redo,
  export,

  /// Put the camera on what is selected, or on everything.
  frameSelection,
  frameAll,

  /// Object ⇄ Mesh, the one switch a modeller makes most.
  toggleObjectMesh,

  /// Delete what is selected — the key a person reaches for without
  /// thinking, which was bound to nothing at all.
  delete,

  selectAll,
  selectNone,
  invertSelection,

  /// Play and pause the timeline.
  playPause,

  viewFront,
  viewSide,
  viewTop,

  shortcutHelp,

  /// `ux-25`'s own palette: everything the editor can do, by name.
  commandPalette,
}

/// What a key means in one preset.
@immutable
final class Keymap {
  const Keymap({
    required this.preset,
    required this.tools,
    required this.actions,
  });

  final KeymapPreset preset;

  /// Tool id to the key that arms it. A tool with no entry has no key in
  /// this preset, which is a real answer: `toolKeys` deliberately leaves the
  /// mesh operations on their own letters and moves only the four a hand
  /// rests on.
  final Map<String, ShortcutActivator> tools;

  /// What else a key does. A list, because several keys can mean one thing —
  /// `Delete` and `Backspace` both delete, and `.` and the numpad's own
  /// decimal both frame.
  final Map<ModelerAction, List<ShortcutActivator>> actions;

  /// The key that arms [toolId] here, or null when this preset gives it
  /// none.
  ShortcutActivator? forTool(String toolId) => tools[toolId];

  /// Every key that means [action] here.
  List<ShortcutActivator> forAction(ModelerAction action) =>
      actions[action] ?? const <ShortcutActivator>[];
}

/// The keymap for [preset], on a platform where the command key is
/// [apple]'s own meta rather than control.
Keymap keymapFor(KeymapPreset preset, {required bool apple}) {
  final Map<String, ShortcutActivator> tools = <String, ShortcutActivator>{
    ..._defaultToolKeys(),
    ...switch (preset) {
      KeymapPreset.standard => const <String, ShortcutActivator>{},
      KeymapPreset.modalKeys => _modalToolKeys,
      KeymapPreset.toolKeys => _toolSchoolKeys,
    },
  };
  return Keymap(
    preset: preset,
    tools: tools,
    actions: _actions(preset, apple: apple),
  );
}

/// Every tool's own key from `tools.dart`, with `ux-10`'s own corrections.
///
/// Read from the one table rather than restated, so a tool added there
/// arrives here with its key already on it.
Map<String, ShortcutActivator> _defaultToolKeys() {
  final out = <String, ShortcutActivator>{};
  for (final ModelerMode mode in ModelerMode.values) {
    for (final AnimationSubmode? animation in <AnimationSubmode?>[
      null,
      ...AnimationSubmode.values,
    ]) {
      for (final ModelerTool tool in toolsFor(mode, animation: animation)) {
        out[tool.id] = SingleActivator(tool.shortcut);
      }
    }
  }
  // **`F` belongs to framing.** It is the letter every package in the field
  // spends on "put the camera on what I selected", and this application
  // spent it on flipping normals — an operation somebody runs a handful of
  // times a model, against one somebody runs a hundred times an hour. Alt+N
  // keeps it next to "recalculate normals" on `N`, which is where a hand
  // looking for it would go.
  out['mesh.flip'] = const SingleActivator(LogicalKeyboardKey.keyN, alt: true);
  return out;
}

/// The modal school keeps `G`/`R`/`S` where this application already had
/// them; what it has to move is whatever stands on plain `A`.
///
/// **`A` is select-all in this school, and the review found it bound
/// nowhere in object mode because "add a box" was sitting on it.** Adding is
/// a menu in the top bar and a thing somebody does a few times a session;
/// selecting everything is a thing they do constantly, and in this school
/// their hand is already on `A` for it. So adding takes `Shift+A`, which is
/// the same school's own answer for an add menu, in each of the three rails
/// where something was standing on the letter.
const Map<String, ShortcutActivator> _modalToolKeys =
    <String, ShortcutActivator>{
      'object.add': SingleActivator(LogicalKeyboardKey.keyA, shift: true),
      'weights.assign': SingleActivator(LogicalKeyboardKey.keyA, shift: true),
      'morphs.add': SingleActivator(LogicalKeyboardKey.keyA, shift: true),
    };

/// The other school: `W`/`E`/`R` for move, rotate and scale, `Q` to select.
///
/// `E` is extrude in the modal school and rotate here, which is exactly the
/// collision the review's own table describes; a preset is how both can be
/// true without either being wrong.
const Map<String, ShortcutActivator> _toolSchoolKeys =
    <String, ShortcutActivator>{
      'object.select': SingleActivator(LogicalKeyboardKey.keyQ),
      'object.move': SingleActivator(LogicalKeyboardKey.keyW),
      'object.rotate': SingleActivator(LogicalKeyboardKey.keyE),
      'object.scale': SingleActivator(LogicalKeyboardKey.keyR),
      'mesh.select': SingleActivator(LogicalKeyboardKey.keyQ),
      'mesh.move': SingleActivator(LogicalKeyboardKey.keyW),
      'mesh.rotate': SingleActivator(LogicalKeyboardKey.keyE),
      'mesh.scale': SingleActivator(LogicalKeyboardKey.keyR),
      // Extrude loses `E` to rotate here. `Shift+E` rather than the
      // control combination this school usually offers, because control-E
      // is already export on a machine whose command key is control — a
      // collision the check below names rather than a rule anybody has to
      // remember.
      'mesh.extrude': SingleActivator(LogicalKeyboardKey.keyE, shift: true),
    };

Map<ModelerAction, List<ShortcutActivator>> _actions(
  KeymapPreset preset, {
  required bool apple,
}) {
  SingleActivator command(LogicalKeyboardKey key, {bool shift = false}) => apple
      ? SingleActivator(key, meta: true, shift: shift)
      : SingleActivator(key, control: true, shift: shift);

  return <ModelerAction, List<ShortcutActivator>>{
    // Missing entirely before this row, on every preset. A modeller without
    // a save key is one people lose work in.
    ModelerAction.save: <ShortcutActivator>[command(LogicalKeyboardKey.keyS)],
    ModelerAction.undo: <ShortcutActivator>[command(LogicalKeyboardKey.keyZ)],
    ModelerAction.redo: <ShortcutActivator>[
      command(LogicalKeyboardKey.keyZ, shift: true),
      // The other school's own redo, offered on every preset rather than
      // one: a key that does the right thing costs nothing, and a hand that
      // reaches for it and gets silence has to go and look it up.
      if (!apple) const SingleActivator(LogicalKeyboardKey.keyY, control: true),
    ],
    ModelerAction.export: <ShortcutActivator>[command(LogicalKeyboardKey.keyE)],
    // **Both keys, because both mean it.** `Delete` on a full keyboard and
    // `Backspace` on a laptop are the same intention, and the review found
    // neither bound: the only way to delete was `X`, which is one school's
    // answer and nobody else's.
    ModelerAction.delete: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.delete),
      SingleActivator(LogicalKeyboardKey.backspace),
    ],
    ModelerAction.toggleObjectMesh: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.tab),
    ],
    ModelerAction.frameSelection: <ShortcutActivator>[
      const SingleActivator(LogicalKeyboardKey.period),
      const SingleActivator(LogicalKeyboardKey.numpadDecimal),
      // The tool school frames on `F`, which the default preset now leaves
      // free for exactly this.
      if (preset != KeymapPreset.modalKeys)
        const SingleActivator(LogicalKeyboardKey.keyF),
    ],
    ModelerAction.frameAll: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.home),
    ],
    ModelerAction.selectAll: <ShortcutActivator>[
      // `A` in the modal school; the other one takes the command key, which
      // is also what the operating system's own menus use.
      if (preset == KeymapPreset.modalKeys)
        const SingleActivator(LogicalKeyboardKey.keyA)
      else
        command(LogicalKeyboardKey.keyA),
    ],
    ModelerAction.selectNone: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.keyA, alt: true),
    ],
    ModelerAction.invertSelection: <ShortcutActivator>[
      command(LogicalKeyboardKey.keyI),
    ],
    ModelerAction.playPause: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.space),
    ],
    // The numpad views every package in the field agrees on: front, side,
    // top. Bound on the numpad only — the digit row already means the
    // element level in mesh mode and the sub-mode in animation mode.
    ModelerAction.viewFront: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.numpad1),
    ],
    ModelerAction.viewSide: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.numpad3),
    ],
    ModelerAction.viewTop: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.numpad7),
    ],
    ModelerAction.shortcutHelp: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.slash, shift: true),
    ],
    // `ux-25`: the command key where there is one, and `F3` everywhere —
    // the second is what a keyboard with no command key reaches for, and
    // neither collides with anything a rail binds.
    ModelerAction.commandPalette: <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.keyP, meta: apple, control: !apple),
      const SingleActivator(LogicalKeyboardKey.f3),
    ],
  };
}

/// Every key in [keymap] that two different things answer to.
///
/// **The acceptance of this row, as a function rather than a document.** A
/// preset is a table somebody edits by hand, and the failure it invites is
/// two entries on one key — which shows up as a tool that mysteriously does
/// something else.
///
/// **A scope is one rail, not one mode.** A key means one thing at a time,
/// and what decides "at a time" is which rail is on screen: `G` arming move
/// in both object and mesh mode is one answer given twice rather than a
/// collision, and the animation mode's four sub-modes are four different
/// workflows that happen to share a mode button (`tools.dart`'s own comment
/// on [AnimationSubmode] says so) — `I` keying a pose and `I` importing a
/// clip are never both reachable. So each rail is checked against itself and
/// against the application-wide actions, which are live under all of them.
List<String> keymapCollisions(Keymap keymap) {
  final out = <String>[];
  for (final ModelerMode mode in ModelerMode.values) {
    final List<AnimationSubmode?> rails = mode == ModelerMode.animation
        ? AnimationSubmode.values
        : <AnimationSubmode?>[null];
    for (final AnimationSubmode? animation in rails) {
      final String where = animation == null
          ? mode.name
          : '${mode.name}/${animation.name}';
      final seen = <String, String>{};
      void claim(String key, String by) {
        final String? already = seen[key];
        if (already != null && already != by) {
          out.add('$where: $key is both $already and $by');
          return;
        }
        seen[key] = by;
      }

      for (final ModelerTool tool in toolsFor(mode, animation: animation)) {
        final ShortcutActivator? key = keymap.forTool(tool.id);
        if (key != null) claim(_describe(key), tool.id);
      }
      for (final ModelerAction action in ModelerAction.values) {
        for (final ShortcutActivator key in keymap.forAction(action)) {
          claim(_describe(key), action.name);
        }
      }
    }
  }
  return out;
}

/// A key as a comparable string — `SingleActivator` has no useful equality
/// for this, and two activators that print the same are the same key.
String _describe(ShortcutActivator key) {
  if (key is! SingleActivator) return key.toString();
  return <String>[
    if (key.control) 'ctrl',
    if (key.meta) 'cmd',
    if (key.alt) 'alt',
    if (key.shift) 'shift',
    key.trigger.keyLabel,
  ].join('+');
}
