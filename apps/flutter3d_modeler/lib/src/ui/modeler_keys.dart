/// The keyboard, over the whole shell.
///
/// **`Shortcuts` and `Actions` rather than a `RawKeyboardListener`**, because
/// this has to lose to a text field: a person typing 1.5 into a number field is
/// not asking for vertex level, and the focus system is what already knows the
/// difference. The tools come from the same table the rail reads, so a key
/// that arms nothing is a key nobody wrote down twice.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'keymap.dart';
import 'selection_key_bindings.dart';
import 'tools.dart';

/// The keyboard, over the whole shell.
class ModelerKeys extends StatelessWidget {
  const ModelerKeys({
    super.key,
    required this.onKey,
    required this.onUndo,
    required this.onRedo,
    required this.onExport,
    required this.onTool,
    required this.mode,
    required this.onLevel,
    required this.onAnimationLevel,
    required this.onSelectAll,
    required this.onSelectNone,
    required this.onInvertSelection,
    required this.onShortcutHelp,
    this.onCommandPalette,
    required this.tools,
    required this.child,
    required this.keymap,
    this.onSave,
    this.onDelete,
    this.onToggleObjectMesh,
    this.onFrameSelection,
    this.onFrameAll,
    this.onPlayPause,
    this.onStandardView,
  });

  /// Which keys are live — `ux-10`'s own preset, read off the settings.
  ///
  /// **Every binding below comes from here, including the ones that used to
  /// be written into this widget.** Undo, redo and export were built from
  /// `Theme.of(context).platform` a few lines down and the tools from their
  /// own `ModelerTool.shortcut`; a preset that could change one and not the
  /// other would be a preset that half works.
  final Keymap keymap;

  /// The application's own actions, each null where the caller has none to
  /// give — a preview viewport with no document to save, a test.
  final VoidCallback? onSave;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleObjectMesh;
  final VoidCallback? onFrameSelection;
  final VoidCallback? onFrameAll;
  final VoidCallback? onPlayPause;
  final ValueChanged<ModelerAction>? onStandardView;

  /// A key that a transform in progress may want. Answers whether it took it,
  /// so the shortcuts below only see the ones it did not.
  final bool Function(LogicalKeyboardKey key, String? character) onKey;

  final VoidCallback onUndo;
  final VoidCallback onRedo;

  /// ⌘E. Bound to the container rather than to a menu, because it is the
  /// export a person repeats: the one that goes back into the game.
  final VoidCallback onExport;
  final ValueChanged<String> onTool;

  /// Which sub-mode's own digit keys are live — `ui-40d`'s own row.
  /// [MeshSubmode]'s three and [AnimationSubmode]'s four both start at
  /// `digit1`, so binding both at once regardless of [mode] would leave one
  /// of [onLevel]/[onAnimationLevel] shadowed in the `Shortcuts` map built
  /// below; gating each set on the mode it belongs to is what keeps a
  /// digit key meaning one thing at a time, the same "a shortcut means one
  /// thing within a mode" rule the tool table itself already keeps.
  final ModelerMode mode;
  final ValueChanged<MeshSubmode> onLevel;
  final ValueChanged<AnimationSubmode> onAnimationLevel;
  final VoidCallback onSelectAll;
  final VoidCallback onSelectNone;
  final VoidCallback onInvertSelection;

  /// `?`. `ui-32n`'s own way in, beside the Help button in the top bar.
  final VoidCallback onShortcutHelp;

  /// `ux-25`'s own palette. Null in a caller that has no screen to open one
  /// over — a preview, a test — and the keys then mean nothing rather than
  /// throwing.
  final VoidCallback? onCommandPalette;
  final List<ModelerTool> tools;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // **A `Focus` with an `onKeyEvent` outside the shortcuts, because a
    // transform in progress has to see keys before they mean what they usually
    // mean.** `X` arms nothing while a move is going on — it constrains the
    // move — and `5` is a number rather than whatever `5` will one day be.
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        return onKey(event.logicalKey, event.character)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          // Every application-wide action the live preset binds, and only
          // the ones this caller has something to do about.
          for (final MapEntry<ModelerAction, VoidCallback?> each
              in <ModelerAction, VoidCallback?>{
                ModelerAction.undo: onUndo,
                ModelerAction.redo: onRedo,
                ModelerAction.export: onExport,
                ModelerAction.save: onSave,
                ModelerAction.delete: onDelete,
                ModelerAction.toggleObjectMesh: onToggleObjectMesh,
                ModelerAction.frameSelection: onFrameSelection,
                ModelerAction.frameAll: onFrameAll,
                ModelerAction.playPause: onPlayPause,
                ModelerAction.shortcutHelp: onShortcutHelp,
                ModelerAction.commandPalette: onCommandPalette,
              }.entries)
            if (each.value case final VoidCallback run)
              for (final ShortcutActivator key in keymap.forAction(each.key))
                key: _typingSafe(run),
          if (onStandardView case final ValueChanged<ModelerAction> look)
            for (final ModelerAction view in const <ModelerAction>[
              ModelerAction.viewFront,
              ModelerAction.viewSide,
              ModelerAction.viewTop,
            ])
              for (final ShortcutActivator key in keymap.forAction(view))
                key: _typingSafe(() => look(view)),
          if (mode == ModelerMode.mesh)
            for (final MeshSubmode level in MeshSubmode.values)
              SingleActivator(level.shortcut): _typingSafe(
                () => onLevel(level),
              ),
          if (mode == ModelerMode.animation)
            for (final AnimationSubmode level in AnimationSubmode.values)
              SingleActivator(level.shortcut): _typingSafe(
                () => onAnimationLevel(level),
              ),
          // The rail's own keys, from the preset rather than from
          // `ModelerTool.shortcut` — which is what makes a preset reach the
          // rail at all.
          for (final ModelerTool tool in tools)
            if (keymap.forTool(tool.id) case final ShortcutActivator key)
              key: _typingSafe(() => onTool(tool.id)),
          for (final MapEntry<ShortcutActivator, VoidCallback> entry
              in selectionKeyBindings(
                tools: tools,
                onSelectAll: onSelectAll,
                onSelectNone: onSelectNone,
                onInvertSelection: onInvertSelection,
              ).entries)
            entry.key: _typingSafe(entry.value),
        },
        child: child,
      ),
    );
  }

  /// [action], unless a text field currently holds the keyboard focus.
  ///
  /// **`ui-12`'s own "фокус в `NumberField` перехватывает."** A bare letter or
  /// digit reaches this widget's own `CallbackShortcuts` whether or not a
  /// `TextField` further down the tree is focused — Flutter delivers the
  /// character to the field through the text-input channel, a path separate
  /// from the raw key event this binding sees, so nothing here stops a
  /// keystroke from doing both at once unless it is told to. Checked against
  /// the currently focused element's own ancestry rather than one field's
  /// `FocusNode`, since any `NumberField` anywhere in the panel needs the
  /// same protection, not just one.
  static VoidCallback _typingSafe(VoidCallback action) => () {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null &&
        context.findAncestorWidgetOfExactType<EditableText>() != null) {
      return;
    }
    action();
  };
}
