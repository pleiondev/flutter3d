/// [ModelerUiActions]: `mcp-16d`'s own [UiActions], wired to a live
/// [ModelerCubit] and the two dialogs it can open — nothing here that is not
/// already a button, a keyboard shortcut, or a dialog `screen/files.dart`
/// already opens some other way, offered a second way in over MCP.
///
/// **Public and standalone, not a `part of 'main.dart'`.** `modeler_cubit.
/// dart`'s own doc comment gives the reason this follows: every method below
/// is a state transition worth writing down as a sentence, and
/// `modeler_ui_actions_test.dart` is that sentence, reached with a plain
/// `ModelerCubit` and no pumped widget — the same shape
/// `modeler_cubit_test.dart` already uses.
library;

import 'dart:async';

import 'display_modes.dart';
import 'mcp_ui_actions.dart';
import 'modeler_cubit.dart';
import 'ui/tools.dart';

final class ModelerUiActions implements UiActions {
  ModelerUiActions({
    required this.cubit,
    required this.openExportDialog,
    required this.openLatheDialog,
  });

  final ModelerCubit cubit;

  /// `_ModelerScreenState._showExportDialog`, handed in rather than reached
  /// for directly — the one piece of this that genuinely needs a live
  /// screen, kept to exactly the one call [openDialog] makes so a test can
  /// stub it out instead of pumping one.
  final Future<void> Function() openExportDialog;

  /// `_ModelerScreenState._openLatheDialog`, the same deal.
  final Future<void> Function() openLatheDialog;

  ModelerReady? get _ready =>
      cubit.state is ModelerReady ? cubit.state as ModelerReady : null;

  @override
  UiAnswer setMode(String mode) {
    if (_ready == null) return (did: false, says: 'no document open');
    final ModelerMode? target = _enumByName(ModelerMode.values, mode);
    if (target == null) return (did: false, says: 'no such mode: $mode');
    // `ux-07`: the same gate the switcher has. The live run asked for `uv`
    // over MCP and was told "mode set to uv" — the mode did change, the
    // screen showed a mode nothing has built, and an agent driving a
    // screenshot script had no way to know it was looking at nothing. A
    // refusal that names the mode and what it is waiting for is the answer a
    // person pressing a hidden segment would get, if the segment were there.
    if (!target.ready) {
      return (
        did: false,
        says: '$mode is not built yet — it is phase ${target.phase} work',
      );
    }
    cubit.mode(target);
    return (did: true, says: 'mode set to $mode');
  }

  @override
  UiAnswer setSubmode(String submode) {
    if (_ready == null) return (did: false, says: 'no document open');
    // `ui-40d`'s own widening: two submode enums now share this one string
    // argument, `MeshSubmode` tried first since it was here first.
    // `UiActions.setSubmode`'s own shape does not change either day — a
    // third submode enum would widen this the same way.
    final MeshSubmode? mesh = _enumByName(MeshSubmode.values, submode);
    if (mesh != null) {
      cubit.submode(mesh);
      return (did: true, says: 'submode set to $submode');
    }
    final AnimationSubmode? animation = _enumByName(
      AnimationSubmode.values,
      submode,
    );
    if (animation != null) {
      cubit.animationSubmode(animation);
      return (did: true, says: 'submode set to $submode');
    }
    return (did: false, says: 'no such submode: $submode');
  }

  @override
  UiAnswer setTool(String? id) {
    if (_ready == null) return (did: false, says: 'no document open');
    cubit.tool(id);
    return (did: true, says: id == null ? 'tool cleared' : 'tool set to $id');
  }

  @override
  UiAnswer standardView(String view) {
    final ModelerReady? ready = _ready;
    if (ready == null) return (did: false, says: 'no document open');
    final StandardView? target = _enumByName(StandardView.values, view);
    if (target == null) return (did: false, says: 'no such view: $view');
    lookFrom(ready.stage.orbit, target);
    return (did: true, says: 'view set to $view');
  }

  @override
  UiAnswer frameSubject() {
    final ModelerReady? ready = _ready;
    if (ready == null) return (did: false, says: 'no document open');
    ready.stage.frameSubject();
    return (did: true, says: 'framed the subject');
  }

  @override
  UiAnswer openDialog(String dialog) {
    if (_ready == null) return (did: false, says: 'no document open');
    switch (dialog) {
      case 'export':
        unawaited(openExportDialog());
        return (did: true, says: 'opened the export dialog');
      case 'lathe':
        unawaited(openLatheDialog());
        return (did: true, says: 'opened the lathe dialog');
      // `RigBuildOptions` (`anim-33d`) and the game preview (`anim-19`, T5)
      // have no dialog on this branch yet — refusing cleanly here beats
      // duplicating a dialog that does not exist.
      case 'autorig':
      case 'preview':
        return (
          did: false,
          says: 'the $dialog dialog is not built in this app yet',
        );
      default:
        return (did: false, says: 'no such dialog: $dialog');
    }
  }

  @override
  UiAnswer say(String text) {
    if (_ready == null) return (did: false, says: 'no document open');
    cubit.say(text, important: true);
    return (did: true, says: text);
  }
}

/// [name] as one of [values], or null when nothing in [values] is named that
/// — the one lookup every method above needs, since the tools this drives
/// take a plain string rather than this app's own enum (see
/// `mcp_ui_actions.dart`'s own doc comment for why).
T? _enumByName<T extends Enum>(List<T> values, String name) {
  for (final T value in values) {
    if (value.name == name) return value;
  }
  return null;
}
