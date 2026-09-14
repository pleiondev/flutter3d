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
    required this.onLevel,
    required this.onSelectAll,
    required this.onSelectNone,
    required this.onInvertSelection,
    required this.onShortcutHelp,
    required this.tools,
    required this.child,
  });

  /// A key that a transform in progress may want. Answers whether it took it,
  /// so the shortcuts below only see the ones it did not.
  final bool Function(LogicalKeyboardKey key, String? character) onKey;

  final VoidCallback onUndo;
  final VoidCallback onRedo;

  /// ⌘E. Bound to the container rather than to a menu, because it is the
  /// export a person repeats: the one that goes back into the game.
  final VoidCallback onExport;
  final ValueChanged<String> onTool;
  final ValueChanged<MeshSubmode> onLevel;
  final VoidCallback onSelectAll;
  final VoidCallback onSelectNone;
  final VoidCallback onInvertSelection;

  /// `?`. `ui-32n`'s own way in, beside the Help button in the top bar.
  final VoidCallback onShortcutHelp;
  final List<ModelerTool> tools;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Meta on a Mac and control everywhere else, which is what people's hands
    // already know. `Platform` is not reachable on the web, so this asks the
    // framework rather than the operating system.
    final bool apple =
        Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.iOS;
    final undo = apple
        ? const SingleActivator(LogicalKeyboardKey.keyZ, meta: true)
        : const SingleActivator(LogicalKeyboardKey.keyZ, control: true);
    final redo = apple
        ? const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          )
        : const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          );
    final export = apple
        ? const SingleActivator(LogicalKeyboardKey.keyE, meta: true)
        : const SingleActivator(LogicalKeyboardKey.keyE, control: true);
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
          undo: onUndo,
          redo: onRedo,
          export: onExport,
          for (final MeshSubmode level in MeshSubmode.values)
            SingleActivator(level.shortcut): _typingSafe(() => onLevel(level)),
          for (final ModelerTool tool in tools)
            SingleActivator(tool.shortcut): _typingSafe(() => onTool(tool.id)),
          for (final MapEntry<ShortcutActivator, VoidCallback> entry
              in selectionKeyBindings(
                tools: tools,
                onSelectAll: onSelectAll,
                onSelectNone: onSelectNone,
                onInvertSelection: onInvertSelection,
              ).entries)
            entry.key: _typingSafe(entry.value),
          const SingleActivator(LogicalKeyboardKey.slash, shift: true):
              _typingSafe(onShortcutHelp),
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
