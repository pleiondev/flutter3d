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

import 'console_log.dart';
import 'display_modes.dart';
import 'mcp_ui_actions.dart';
import 'modeler_cubit.dart';
import 'play/play_template.dart';
import 'ui/tools.dart';

final class ModelerUiActions implements UiActions {
  ModelerUiActions({
    required this.cubit,
    required this.openExportDialog,
    required this.openLatheDialog,
    required this.openAutorigDialog,
    required this.openGamePreview,
    required this.openPlay,
    required this.runTool,
    this.captureWindow,
  });

  final ModelerCubit cubit;

  /// `_ModelerScreenState._showExportDialog`, handed in rather than reached
  /// for directly — the one piece of this that genuinely needs a live
  /// screen, kept to exactly the one call [openDialog] makes so a test can
  /// stub it out instead of pumping one.
  final Future<void> Function() openExportDialog;

  /// `_ModelerScreenState._openLatheDialog`, the same deal.
  final Future<void> Function() openLatheDialog;

  /// `_ModelerScreenState._openAutorigDialog` and `._openGamePreview` —
  /// `ux-36`.
  ///
  /// **Both used to be a refusal here.** `ui.openDialog` said "not built in
  /// this app yet" for autorig and for preview, which was true when the
  /// sentence was written and stopped being true when `S8` built
  /// `autorig_dialog.dart` and `S9` built the game preview. A refusal that
  /// has outlived its reason is worse than no tool: a screenshot script
  /// reads it as a thing the application cannot do.
  final Future<void> Function() openAutorigDialog;
  final Future<void> Function() openGamePreview;

  /// `ux-50`: `_ModelerScreenState._openPlay` — the document walked in
  /// rather than looked at, which is what separates this from the preview
  /// above.
  final Future<void> Function(PlayTemplate template) openPlay;

  /// `ux-44`: the window as PNG bytes, or null when there is no laid-out
  /// window to capture. Handed in for the same reason the two dialogs above
  /// are — it needs a live `RenderRepaintBoundary`, which is exactly the
  /// thing a test of the rest of this file does not want to pump.
  final Future<List<int>?> Function()? captureWindow;

  /// `_ModelerScreenState._ranTool` — the one door a rail button, the
  /// command palette and `ux-25`'s own `run_command` all go through, so a
  /// tool reached any of those three ways arms, opens or lands identically.
  final void Function(String id) runTool;

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
  UiAnswer runCommand(String id) {
    if (_ready == null) return (did: false, says: 'no document open');
    final bool known = ModelerMode.values.any(
      (ModelerMode mode) =>
          mode.ready &&
          AnimationSubmode.values.any(
            (AnimationSubmode submode) => toolsFor(
              mode,
              animation: submode,
            ).any((ModelerTool tool) => tool.id == id),
          ),
    );
    if (!known) return (did: false, says: 'no such command: $id');
    runTool(id);
    return (did: true, says: 'ran $id');
  }

  /// `ux-26`. **`says` is the log itself, as one line per entry**, rather
  /// than a structured answer: every other tool in this file answers with a
  /// sentence, the transport is text, and an agent reading "14:03:22 you
  /// refused: nothing is selected to extrude" needs no parser to act on it.
  /// The machine-readable shape is `ConsoleEntry.toJson`, and it is there
  /// for whatever wants it next.
  @override
  UiAnswer console({DateTime? since}) {
    final List<ConsoleEntry> entries = cubit.console.since(since);
    if (entries.isEmpty) {
      return (
        did: true,
        says: since == null
            ? 'nothing has been said this session'
            : 'nothing since ${since.toIso8601String()}',
      );
    }
    return (
      did: true,
      says: entries
          .map(
            (ConsoleEntry it) =>
                '${it.at.toIso8601String()} '
                '${it.author.name}'
                '${it.kind == ConsoleKind.report ? '' : ' (${it.kind.name})'}'
                '${it.tool == null ? '' : ' ${it.tool}'}: ${it.text}',
          )
          .join('\n'),
    );
  }

  @override
  List<({String id, String label, String mode})> commands() {
    final seen = <String>{};
    final out = <({String id, String label, String mode})>[];
    for (final ModelerMode mode in ModelerMode.values) {
      if (!mode.ready) continue;
      for (final AnimationSubmode submode in AnimationSubmode.values) {
        for (final ModelerTool tool in toolsFor(mode, animation: submode)) {
          if (!seen.add(tool.id)) continue;
          out.add((id: tool.id, label: tool.label, mode: mode.name));
        }
        if (mode != ModelerMode.animation) break;
      }
    }
    return out;
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
      // `ux-36`: both of these exist now — `S8`'s own autorig dialog and
      // `S9`'s own game preview — and this answered "not built in this app
      // yet" for as long as nobody re-read it.
      case 'autorig':
        unawaited(openAutorigDialog());
        return (did: true, says: 'opened the auto-rig dialog');
      case 'preview':
        unawaited(openGamePreview());
        return (did: true, says: 'opened the game preview');
      // `ux-50`: one name per template, because "play" with no template is
      // a question rather than a command — the three answer different ones.
      case 'play':
      case 'play.character':
        unawaited(openPlay(PlayTemplate.character));
        return (did: true, says: 'started Play on the character template');
      case 'play.prop':
        unawaited(openPlay(PlayTemplate.prop));
        return (did: true, says: 'started Play on the prop template');
      case 'play.walkthrough':
        unawaited(openPlay(PlayTemplate.walkthrough));
        return (did: true, says: 'started Play on the walkthrough template');
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

  @override
  Future<UiPicture> screenshot() async {
    final Future<List<int>?> Function()? capture = captureWindow;
    if (capture == null) {
      return (
        did: false,
        says: 'this server has no window to capture',
        png: null,
      );
    }
    final List<int>? png = await capture();
    if (png == null) {
      return (
        did: false,
        says: 'the window has not been laid out yet',
        png: null,
      );
    }
    return (did: true, says: 'the window, ${png.length} bytes', png: png);
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
