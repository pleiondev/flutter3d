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
  /// The shortcuts of the live keymap over [child]; each key calls the matching
  /// callback, and one whose callback is null is not bound.
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
    this.onFoldPanel,
    this.onFoldRail,
    this.onGrowSelection,
    this.onShrinkSelection,
    this.onBrushNarrower,
    this.onBrushWider,
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

  /// `Delete` or `Backspace`: delete what is selected.
  final VoidCallback? onDelete;

  /// `Tab`: switch between object and mesh mode.
  final VoidCallback? onToggleObjectMesh;

  /// `.` (and `F` outside the modal-keys preset): put the camera on what is
  /// selected.
  final VoidCallback? onFrameSelection;

  /// `Home`: put the camera on everything.
  final VoidCallback? onFrameAll;

  /// `Space`: play or pause the timeline.
  final VoidCallback? onPlayPause;

  /// Numpad 1, 3 or 7: look from the front, side or top, handed the
  /// [ModelerAction] of the view.
  final ValueChanged<ModelerAction>? onStandardView;

  /// A key that a transform in progress may want. Answers whether it took it,
  /// so the shortcuts below only see the ones it did not.
  final bool Function(LogicalKeyboardKey key, String? character) onKey;

  /// The command key with `Z`: undo.
  final VoidCallback onUndo;

  /// The command key with shift and `Z`, or control and `Y` off Apple
  /// platforms: redo.
  final VoidCallback onRedo;

  /// ⌘E. Bound to the container rather than to a menu, because it is the
  /// export a person repeats: the one that goes back into the game.
  final VoidCallback onExport;

  /// A rail tool's key in the live keymap was pressed, with the tool's id.
  final ValueChanged<String> onTool;

  /// Which sub-mode's own digit keys are live — `ui-40d`'s own row.
  /// [MeshSubmode]'s three and [AnimationSubmode]'s four both start at
  /// `digit1`, so binding both at once regardless of [mode] would leave one
  /// of [onLevel]/[onAnimationLevel] shadowed in the `Shortcuts` map built
  /// below; gating each set on the mode it belongs to is what keeps a
  /// digit key meaning one thing at a time, the same "a shortcut means one
  /// thing within a mode" rule the tool table itself already keeps.
  final ModelerMode mode;

  /// A digit key in mesh or UV mode: switch to that element level.
  final ValueChanged<MeshSubmode> onLevel;

  /// A digit key in animation mode: switch to that sub-mode.
  final ValueChanged<AnimationSubmode> onAnimationLevel;

  /// Select everything, on the select-all key of the live keymap.
  final VoidCallback onSelectAll;

  /// `Alt` with `A`: clear the selection.
  final VoidCallback onSelectNone;

  /// The command key with `I`: select what is not selected and nothing that
  /// is.
  final VoidCallback onInvertSelection;

  /// `?`. `ui-32n`'s own way in, beside the Help button in the top bar.
  final VoidCallback onShortcutHelp;

  /// `ux-25`'s own palette. Null in a caller that has no screen to open one
  /// over — a preview, a test — and the keys then mean nothing rather than
  /// throwing.
  final VoidCallback? onCommandPalette;

  /// `ux-27`'s own two folds. Null where there is no shell to fold.
  final VoidCallback? onFoldPanel;

  /// Shift with `T`: fold the tool rail away, or back.
  final VoidCallback? onFoldRail;

  /// `ux-28`'s own two: one ring of neighbours more, and one less.
  final VoidCallback? onGrowSelection;

  /// The command key with minus: one ring of neighbours less.
  final VoidCallback? onShrinkSelection;

  /// `ux-24`'s own two: the weight brush narrower and wider. Null outside
  /// the weights sub-mode, where the keys mean nothing rather than moving a
  /// brush nobody can see.
  final VoidCallback? onBrushNarrower;

  /// `]`: the weight brush wider. Null outside the weights sub-mode, like
  /// [onBrushNarrower].
  final VoidCallback? onBrushWider;

  /// The rail's tools in the current mode; only these get their keys bound.
  final List<ModelerTool> tools;

  /// The shell the keys are bound over.
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
                ModelerAction.foldPanel: onFoldPanel,
                ModelerAction.foldRail: onFoldRail,
                ModelerAction.growSelection: onGrowSelection,
                ModelerAction.shrinkSelection: onShrinkSelection,
                ModelerAction.brushNarrower: onBrushNarrower,
                ModelerAction.brushWider: onBrushWider,
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
          // `pro-uv-07`: the UV mode too, which shows the same level switch
          // — see `ModelerModeSwitcher`.
          if (mode == ModelerMode.mesh || mode == ModelerMode.uv)
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
