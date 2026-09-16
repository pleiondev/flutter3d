/// The in-app shortcut table — `ui-32n`'s own "без второго источника правды
/// для клавиш", now read through whichever preset is live (`ux-10`).
///
/// **One row per key, not per tool.** Several modes arm the same family of
/// operation on the same letter — `G`/`R`/`S` move, rotate and scale in both
/// object and mesh mode — and a help screen listing `G` twice with the same
/// answer both times is a longer table saying the same thing, not a more
/// complete one. The first mode to use a key names the row; every later
/// mode that reaches for the same key is folded into it rather than
/// appended beside it.
///
/// **Sections, since `ux-10`.** The review found the help screen teaching
/// the tools and nothing else: not how to move the camera, not how to save,
/// not how to select everything — the three things somebody in their first
/// hour is actually looking for. The camera section is the one that is not
/// a keyboard binding at all, and is written down here because a help screen
/// that answers "how do I turn the model" is worth more than one that is
/// only about keys.
library;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show ShortcutActivator, SingleActivator;

import '../settings.dart' show NavigationScheme;
import 'keymap.dart';
import 'tools.dart';

/// Which part of the application a row belongs to.
enum ShortcutSection {
  /// Moving the camera — gestures rather than keys, mostly.
  camera,

  /// Save, undo, export, help: the things that are true in every mode.
  application,

  /// Selecting, and moving between modes.
  selection,

  /// What the rail arms.
  tools,

  /// What a finger and a pen do — `ux-42`.
  ///
  /// **Its own section because none of it is a key.** A person on a tablet
  /// has no keyboard to read the rest of this screen against, and until this
  /// row the help screen had nothing at all to say to them; what a finger
  /// does, what a long press opens and what the inverted end of a stylus
  /// means are all decided by `InputPolicy` and were written down nowhere a
  /// person could read.
  touch,
}

/// One row of the shortcut table: the key, and what it does.
final class ShortcutEntry {
  const ShortcutEntry({
    required this.label,
    required this.keys,
    required this.section,
  });

  /// What it does, in the words the rail or the design already uses.
  final String label;

  /// How it is reached, already written out — "⌘S", "Delete or Backspace",
  /// "two fingers on a trackpad". A string rather than an activator because
  /// a camera row has no activator at all and a help screen that could not
  /// mention the camera would be missing the first question people ask.
  final String keys;

  final ShortcutSection section;
}

/// Every shortcut [keymap] hands out, each key once, in sections.
List<ShortcutEntry> shortcutTable(
  Keymap keymap, {
  NavigationScheme navigation = NavigationScheme.middleMouseOrbit,
}) => <ShortcutEntry>[
  ..._cameraRows(navigation),
  ..._actionRows(keymap),
  ..._pointerRows,
  ..._touchRows,
  ..._toolRows(keymap),
];

/// `ux-28`: what a click inside a mesh means with a modifier held.
///
/// **Written out rather than built from the keymap, because none of these is
/// a keyboard shortcut.** They are modifiers on a pointer, the same kind of
/// thing the camera rows already describe in words — and the help screen is
/// the one place a person goes to find out that alt-click does anything at
/// all, since a modifier leaves no mark on the interface until it is held.
const List<ShortcutEntry> _pointerRows = <ShortcutEntry>[
  ShortcutEntry(
    label: 'Select the edge loop',
    keys: 'Alt and a click, in mesh mode',
    section: ShortcutSection.selection,
  ),
  ShortcutEntry(
    label: 'Select the edge ring',
    keys: 'Ctrl or ⌘, with Alt and a click',
    section: ShortcutSection.selection,
  ),
];

/// `ux-42`: what a finger and a pen do, from `InputPolicy.classify`'s own
/// answers rather than from a second account of them.
///
/// **Written as sentences, not read off the policy at runtime.** `classify`
/// answers per pointer, per armed tool, and turning the cross product of that
/// into rows would be a table nobody reads; these four are what the policy
/// actually decides, said the way a person would ask about it. The test holds
/// them to it.
const List<ShortcutEntry> _touchRows = <ShortcutEntry>[
  ShortcutEntry(
    label: 'A finger',
    keys: 'Moves the camera, whatever tool is armed',
    section: ShortcutSection.touch,
  ),
  ShortcutEntry(
    label: 'A finger held still',
    keys: 'Opens the menu, without nudging the camera first',
    section: ShortcutSection.touch,
  ),
  ShortcutEntry(
    label: 'A pen',
    keys: 'Draws on the model, harder for a stronger stroke',
    section: ShortcutSection.touch,
  ),
  ShortcutEntry(
    label: 'The other end of the pen',
    keys: 'The same stroke, erasing',
    section: ShortcutSection.touch,
  ),
];

List<ShortcutEntry> _cameraRows(NavigationScheme navigation) => <ShortcutEntry>[
  ShortcutEntry(
    label: 'Orbit',
    keys: switch (navigation) {
      NavigationScheme.middleMouseOrbit =>
        'Middle button, Alt and the left button, or two fingers on a '
            'trackpad',
      NavigationScheme.leftDragOrbit =>
        'Left button on empty space, the middle button, or two fingers on a '
            'trackpad',
    },
    section: ShortcutSection.camera,
  ),
  const ShortcutEntry(
    label: 'Pan',
    keys: 'Shift and whatever orbits',
    section: ShortcutSection.camera,
  ),
  const ShortcutEntry(
    label: 'Zoom',
    keys: 'The wheel, or Ctrl with two fingers',
    section: ShortcutSection.camera,
  ),
];

/// The rows in the order a person meets them, one per action.
const Map<ModelerAction, (String, ShortcutSection)> _actionLabels =
    <ModelerAction, (String, ShortcutSection)>{
      ModelerAction.save: ('Save', ShortcutSection.application),
      ModelerAction.export: ('Export', ShortcutSection.application),
      ModelerAction.undo: ('Undo', ShortcutSection.application),
      ModelerAction.redo: ('Redo', ShortcutSection.application),
      ModelerAction.shortcutHelp: ('This screen', ShortcutSection.application),
      ModelerAction.commandPalette: (
        'Command palette',
        ShortcutSection.application,
      ),
      ModelerAction.foldPanel: (
        'Fold the properties panel',
        ShortcutSection.application,
      ),
      ModelerAction.foldRail: (
        'Fold the tool rail',
        ShortcutSection.application,
      ),
      ModelerAction.growSelection: (
        'Grow the selection',
        ShortcutSection.application,
      ),
      ModelerAction.shrinkSelection: (
        'Shrink the selection',
        ShortcutSection.application,
      ),
      ModelerAction.brushNarrower: (
        'Narrower brush',
        ShortcutSection.tools,
      ),
      ModelerAction.brushWider: ('Wider brush', ShortcutSection.tools),
      ModelerAction.frameSelection: (
        'Frame what is selected',
        ShortcutSection.application,
      ),
      ModelerAction.frameAll: ('Frame everything', ShortcutSection.application),
      ModelerAction.viewFront: ('Front view', ShortcutSection.application),
      ModelerAction.viewSide: ('Side view', ShortcutSection.application),
      ModelerAction.viewTop: ('Top view', ShortcutSection.application),
      ModelerAction.playPause: ('Play and pause', ShortcutSection.application),
      ModelerAction.selectAll: ('Select everything', ShortcutSection.selection),
      ModelerAction.selectNone: ('Select nothing', ShortcutSection.selection),
      ModelerAction.invertSelection: (
        'Invert the selection',
        ShortcutSection.selection,
      ),
      ModelerAction.toggleObjectMesh: (
        'Object and mesh',
        ShortcutSection.selection,
      ),
      ModelerAction.delete: ('Delete', ShortcutSection.selection),
    };

List<ShortcutEntry> _actionRows(Keymap keymap) => <ShortcutEntry>[
  for (final MapEntry<ModelerAction, (String, ShortcutSection)> each
      in _actionLabels.entries)
    if (keymap.forAction(each.key) case final List<ShortcutActivator> keys)
      if (keys.isNotEmpty)
        ShortcutEntry(
          label: each.value.$1,
          keys: keys.map(describeShortcut).join(' or '),
          section: each.value.$2,
        ),
];

/// One row per thing a key does, not one per key.
///
/// **The difference matters and used to be got wrong.** `G` moves in both
/// object and mesh mode, which is one answer given twice and belongs on one
/// row; `B` is "bake to mesh" in object mode and "bevel" in mesh mode, which
/// is two answers and was being folded into whichever came first — so the
/// help screen simply did not mention bevel at all. Keying the fold on the
/// pair rather than the key alone is what tells those two cases apart.
List<ShortcutEntry> _toolRows(Keymap keymap) {
  final seen = <String>{};
  return <ShortcutEntry>[
    for (final ModelerMode mode in ModelerMode.values)
      for (final AnimationSubmode? animation in <AnimationSubmode?>[
        null,
        ...AnimationSubmode.values,
      ])
        for (final ModelerTool tool in toolsFor(mode, animation: animation))
          if (keymap.forTool(tool.id) case final ShortcutActivator key)
            if (seen.add('${describeShortcut(key)}|${tool.label}'))
              ShortcutEntry(
                label: tool.label,
                keys: describeShortcut(key),
                section: ShortcutSection.tools,
              ),
  ];
}

/// A key as a person reads it — "⌘S", "Alt+N", "Delete".
String describeShortcut(ShortcutActivator key) {
  if (key is! SingleActivator) return key.toString();
  final String name = _keyName(key.trigger);
  return <String>[
    if (key.control) 'Ctrl',
    if (key.meta) '⌘',
    if (key.alt) 'Alt',
    if (key.shift) 'Shift',
    name,
  ].join(key.meta && !key.control && !key.alt && !key.shift ? '' : '+');
}

String _keyName(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.delete => 'Delete',
  LogicalKeyboardKey.backspace => 'Backspace',
  LogicalKeyboardKey.tab => 'Tab',
  LogicalKeyboardKey.space => 'Space',
  LogicalKeyboardKey.home => 'Home',
  LogicalKeyboardKey.period => '.',
  LogicalKeyboardKey.numpadDecimal => 'Numpad .',
  // `ux-28`. Without these two the fallback below reads them as their own
  // `keyLabel`, which is the shouted "NUMPAD ADD" — a key nobody has ever
  // seen written on a keyboard.
  LogicalKeyboardKey.numpadAdd => 'Numpad +',
  LogicalKeyboardKey.numpadSubtract => 'Numpad −',
  LogicalKeyboardKey.numpad1 => 'Numpad 1',
  LogicalKeyboardKey.numpad3 => 'Numpad 3',
  LogicalKeyboardKey.numpad7 => 'Numpad 7',
  LogicalKeyboardKey.slash => '/',
  _ => key.keyLabel.toUpperCase(),
};
