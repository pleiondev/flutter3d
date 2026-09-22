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

import '../../l10n/app_localizations.dart';
import '../settings.dart' show NavigationScheme;
import 'keymap.dart';
import 'tool_strings.dart';
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
  required AppLocalizations l,
  NavigationScheme navigation = NavigationScheme.middleMouseOrbit,
}) => <ShortcutEntry>[
  ..._cameraRows(l, navigation),
  ..._actionRows(l, keymap),
  ..._pointerRows(l),
  ..._touchRows(l),
  ..._toolRows(l, keymap),
];

/// `ux-28`: what a click inside a mesh means with a modifier held.
///
/// **Written out rather than built from the keymap, because none of these is
/// a keyboard shortcut.** They are modifiers on a pointer, the same kind of
/// thing the camera rows already describe in words — and the help screen is
/// the one place a person goes to find out that alt-click does anything at
/// all, since a modifier leaves no mark on the interface until it is held.
List<ShortcutEntry> _pointerRows(AppLocalizations l) => <ShortcutEntry>[
  ShortcutEntry(
    label: l.shortcutEdgeLoop,
    keys: l.shortcutEdgeLoopKeys,
    section: ShortcutSection.selection,
  ),
  ShortcutEntry(
    label: l.shortcutEdgeRing,
    keys: l.shortcutEdgeRingKeys,
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
List<ShortcutEntry> _touchRows(AppLocalizations l) => <ShortcutEntry>[
  ShortcutEntry(
    label: l.shortcutFinger,
    keys: l.shortcutFingerKeys,
    section: ShortcutSection.touch,
  ),
  ShortcutEntry(
    label: l.shortcutFingerHeld,
    keys: l.shortcutFingerHeldKeys,
    section: ShortcutSection.touch,
  ),
  ShortcutEntry(
    label: l.shortcutPen,
    keys: l.shortcutPenKeys,
    section: ShortcutSection.touch,
  ),
  ShortcutEntry(
    label: l.shortcutPenOtherEnd,
    keys: l.shortcutPenOtherEndKeys,
    section: ShortcutSection.touch,
  ),
];

List<ShortcutEntry> _cameraRows(
  AppLocalizations l,
  NavigationScheme navigation,
) => <ShortcutEntry>[
  ShortcutEntry(
    label: l.shortcutOrbit,
    keys: switch (navigation) {
      NavigationScheme.middleMouseOrbit => l.shortcutOrbitMiddle,
      NavigationScheme.leftDragOrbit => l.shortcutOrbitLeft,
    },
    section: ShortcutSection.camera,
  ),
  ShortcutEntry(
    label: l.shortcutPan,
    keys: l.shortcutPanKeys,
    section: ShortcutSection.camera,
  ),
  ShortcutEntry(
    label: l.shortcutZoom,
    keys: l.shortcutZoomKeys,
    section: ShortcutSection.camera,
  ),
];

/// Which section each action's row belongs in.
///
/// **The section here and the words in the ARB files.** A section is a fact
/// about the application — saving is not selecting — and stays where the
/// reader of this file can see it; the label is language and lives with
/// every other string a person reads. Pairing them in one map was what made
/// this file the last one in `ux-22` with English in it.
const Map<ModelerAction, ShortcutSection> _actionSections =
    <ModelerAction, ShortcutSection>{
      ModelerAction.save: ShortcutSection.application,
      ModelerAction.export: ShortcutSection.application,
      ModelerAction.undo: ShortcutSection.application,
      ModelerAction.redo: ShortcutSection.application,
      ModelerAction.shortcutHelp: ShortcutSection.application,
      ModelerAction.commandPalette: ShortcutSection.application,
      ModelerAction.foldPanel: ShortcutSection.application,
      ModelerAction.foldRail: ShortcutSection.application,
      ModelerAction.growSelection: ShortcutSection.application,
      ModelerAction.shrinkSelection: ShortcutSection.application,
      ModelerAction.brushNarrower: ShortcutSection.tools,
      ModelerAction.brushWider: ShortcutSection.tools,
      ModelerAction.frameSelection: ShortcutSection.application,
      ModelerAction.frameAll: ShortcutSection.application,
      ModelerAction.viewFront: ShortcutSection.application,
      ModelerAction.viewSide: ShortcutSection.application,
      ModelerAction.viewTop: ShortcutSection.application,
      ModelerAction.playPause: ShortcutSection.application,
      ModelerAction.selectAll: ShortcutSection.selection,
      ModelerAction.selectNone: ShortcutSection.selection,
      ModelerAction.invertSelection: ShortcutSection.selection,
      ModelerAction.toggleObjectMesh: ShortcutSection.selection,
      ModelerAction.delete: ShortcutSection.selection,
    };

/// What each action is called, in the language the application is in.
///
/// A switch rather than a map for `tool_strings.dart`'s own reason: a
/// generated getter cannot be reached by a string, and a map would build all
/// twenty-three answers to give one.
String _actionLabel(AppLocalizations l, ModelerAction action) =>
    switch (action) {
      ModelerAction.save => l.actionSave,
      ModelerAction.export => l.actionExport,
      ModelerAction.undo => l.actionUndo,
      ModelerAction.redo => l.actionRedo,
      ModelerAction.shortcutHelp => l.actionThisScreen,
      ModelerAction.commandPalette => l.actionCommandPalette,
      ModelerAction.foldPanel => l.actionFoldPanel,
      ModelerAction.foldRail => l.actionFoldRail,
      ModelerAction.growSelection => l.actionGrowSelection,
      ModelerAction.shrinkSelection => l.actionShrinkSelection,
      ModelerAction.brushNarrower => l.actionBrushNarrower,
      ModelerAction.brushWider => l.actionBrushWider,
      ModelerAction.frameSelection => l.actionFrameSelection,
      ModelerAction.frameAll => l.actionFrameAll,
      ModelerAction.viewFront => l.actionViewFront,
      ModelerAction.viewSide => l.actionViewSide,
      ModelerAction.viewTop => l.actionViewTop,
      ModelerAction.playPause => l.actionPlayPause,
      ModelerAction.selectAll => l.actionSelectAll,
      ModelerAction.selectNone => l.actionSelectNone,
      ModelerAction.invertSelection => l.actionInvertSelection,
      ModelerAction.toggleObjectMesh => l.actionToggleObjectMesh,
      ModelerAction.delete => l.actionDelete,
    };

List<ShortcutEntry> _actionRows(AppLocalizations l, Keymap keymap) =>
    <ShortcutEntry>[
      for (final MapEntry<ModelerAction, ShortcutSection> each
          in _actionSections.entries)
        if (keymap.forAction(each.key) case final List<ShortcutActivator> keys)
          if (keys.isNotEmpty)
            ShortcutEntry(
              label: _actionLabel(l, each.key),
              keys: keys.map(describeShortcut).join(' or '),
              section: each.value,
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
List<ShortcutEntry> _toolRows(AppLocalizations l, Keymap keymap) {
  final seen = <String>{};
  return <ShortcutEntry>[
    for (final ModelerMode mode in ModelerMode.values)
      for (final AnimationSubmode? animation in <AnimationSubmode?>[
        null,
        ...AnimationSubmode.values,
      ])
        for (final ModelerTool tool in toolsFor(mode, animation: animation))
          if (keymap.forTool(tool.id) case final ShortcutActivator key)
            if (seen.add('${describeShortcut(key)}|${toolLabel(l, tool)}'))
              ShortcutEntry(
                label: toolLabel(l, tool),
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
