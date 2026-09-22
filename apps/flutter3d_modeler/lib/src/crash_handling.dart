/// `ui-30n`'s own answer to an exception nobody caught: an emergency
/// autosave, a "what happened" dialog, and a local log of the commands that
/// led up to it.
///
/// **Nothing here is telemetry.** The emergency write goes to the same
/// `BinaryStorage` `ui-18`'s own `AutosaveController` already writes to, the
/// dialog opens in this process only, and the one network request either of
/// them can cause is the one `report_problem.dart`'s own [reportProblemUrl]
/// opens in a browser — and only once a person presses the button.
///
/// **Gathered once, not read twice.** [buildCrashReport] takes a snapshot of
/// [lastAttemptedCommand] and the open document's journal at the moment a
/// crash is caught, so the emergency autosave and the dialog agree on what
/// happened even if the cubit moves on before the dialog is dismissed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import 'autosaving.dart';
import 'modeler_cubit.dart';
import 'report_problem.dart';

/// How many of the journal's own commands the crash log carries — enough to
/// read what led up to a crash without pasting a whole session's editing
/// history into a bug report.
const int kCrashLogCommandCount = 20;

/// Everything about a crash worth writing down, gathered once at the moment
/// it is caught.
final class CrashReport {
  const CrashReport({
    required this.error,
    required this.stackTrace,
    this.commandThatThrew,
    this.recentCommands = const <String>[],
  });

  final Object error;
  final StackTrace stackTrace;

  /// [ModelCommand.name] of whatever [ModelerCubit.ran] was running when
  /// this was caught — null when nothing was, or there was no open document.
  final String? commandThatThrew;

  /// The journal's own last [kCrashLogCommandCount] commands, oldest first,
  /// by name — everything that landed before the one that did not.
  final List<String> recentCommands;

  /// What "Report a problem" prefills the "what happened" field with — the
  /// error, the command it broke on, and the trail before it, all in one
  /// paragraph a person can edit before it opens a browser.
  String describe() {
    final lines = <String>['$error'];
    if (commandThatThrew case final String name) lines.add('Command: $name');
    if (recentCommands.isNotEmpty) {
      lines.add('Recent commands: ${recentCommands.join(', ')}');
    }
    return lines.join('\n\n');
  }
}

/// Reads a [CrashReport] out of whatever [cubit] holds right now.
CrashReport buildCrashReport(
  Object error,
  StackTrace stackTrace, {
  required ModelerCubit? cubit,
}) {
  final ModelerState? state = cubit?.state;
  final List<String> journal = state is ModelerReady
      ? <String>[for (final ModelCommand c in state.history.journal) c.name]
      : const <String>[];
  final List<String> recent = journal.length > kCrashLogCommandCount
      ? journal.sublist(journal.length - kCrashLogCommandCount)
      : journal;
  return CrashReport(
    error: error,
    stackTrace: stackTrace,
    commandThatThrew: lastAttemptedCommand?.name,
    recentCommands: recent,
  );
}

/// `ui-30n`'s own whole response to an exception nobody caught: an emergency
/// autosave written before anything is shown, then the dialog. `main`'s own
/// `FlutterError.onError` and `runZonedGuarded` handler both call this with
/// the same two arguments, so a crash reached through either door gets the
/// same treatment.
///
/// [dialogContext] is a function rather than a `BuildContext` because the
/// caller — a top-level error handler with no widget of its own — may have
/// none yet (nothing has built), or none any more (the tree that had one was
/// itself the thing that crashed). It is read only after the autosave has
/// already been attempted, and a null or unmounted answer skips the dialog
/// rather than throwing a second exception on top of the first.
Future<void> handleCrash({
  required Object error,
  required StackTrace stackTrace,
  required ModelerCubit? cubit,
  required BinaryStorage? storage,
  required String sessionId,
  required String environment,
  required BuildContext? Function() dialogContext,
}) async {
  final CrashReport report = buildCrashReport(error, stackTrace, cubit: cubit);
  final bool autosaved = cubit != null && storage != null
      ? await emergencyAutosave(cubit, storage, sessionId)
      : false;
  final BuildContext? context = dialogContext();
  if (context == null || !context.mounted) return;
  // `ux-08`: one dialog at a time, and one per distinct error.
  //
  // **An assert thrown from a build throws again on the next build**, and
  // the next, because nothing about the tree has changed — the live run got
  // a `CrashDialog` per frame stacked over a black window, and "Dismiss"
  // could not keep up with them. The emergency autosave above still runs for
  // every one of them, which is the part that must not be folded: the
  // hundredth copy of an error is as good a reason to write the document as
  // the first.
  if (_dialogIsUp || !_firstSightOf(report)) return;
  _dialogIsUp = true;
  try {
    await CrashDialog.show(
      context,
      report: report,
      environment: environment,
      autosaved: autosaved,
    );
  } finally {
    _dialogIsUp = false;
  }
}

/// Whether a crash dialog is on screen right now.
bool _dialogIsUp = false;

/// Errors already shown, by the text they print.
///
/// A bounded set: an application throwing a thousand *different* errors is
/// one nobody is going to read the list of anyway, and an unbounded one would
/// be a leak in exactly the situation where memory is already the least of
/// it.
final Set<String> _shown = <String>{};
const int _shownLimit = 32;

/// Whether [report]'s own error has not been shown yet, remembering it.
///
/// Keyed on the error and the command it broke on rather than the stack: the
/// same assert reached through two different builds has two stacks and is one
/// problem as far as a person reading a dialog is concerned.
bool _firstSightOf(CrashReport report) {
  final String key = '${report.error}|${report.commandThatThrew}';
  if (_shown.contains(key)) return false;
  if (_shown.length >= _shownLimit) _shown.clear();
  _shown.add(key);
  return true;
}

/// Forgets which errors have been shown — for a test, which would otherwise
/// have its second case swallowed by its first.
@visibleForTesting
void resetCrashDialogMemory() {
  _shown.clear();
  _dialogIsUp = false;
}

/// "Something went wrong" — shown once the emergency autosave has already
/// been attempted, so the message can promise it happened rather than ask
/// somebody to wait for it. An `AlertDialog`, the same shape every other
/// dialog in this application already uses (`_askUnsavedChoice`, `_askAnyway`
/// in `main.dart`) rather than a fourth look for one more of them.
class CrashDialog extends StatelessWidget {
  const CrashDialog({
    super.key,
    required this.report,
    required this.environment,
    this.autosaved = true,
  });

  final CrashReport report;
  final String environment;

  /// Whether the emergency write actually landed — [handleCrash] passes what
  /// [emergencyAutosave] answered.
  ///
  /// **The sentence changes, not a detail in it.** `ux-01`'s own live run
  /// found this dialog telling a person their last edits were safe at the end
  /// of a session in which not one autosave had been written; a promise made
  /// on a day it is false costs more than no promise at all, so a failed write
  /// says so and names what to do instead.
  final bool autosaved;

  static Future<void> show(
    BuildContext context, {
    required CrashReport report,
    required String environment,
    bool autosaved = true,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => CrashDialog(
      report: report,
      environment: environment,
      autosaved: autosaved,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.crashTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              autosaved
                  ? 'The modeller ran into a problem it did not expect. An '
                        'emergency autosave was written, so the last edits '
                        'should not be lost.'
                  : 'The modeller ran into a problem it did not expect, and the '
                        'emergency autosave could not be written — save your '
                        'work now, before dismissing this.',
            ),
            const SizedBox(height: 12),
            Text('${report.error}'),
            if (report.commandThatThrew case final String name) ...<Widget>[
              const SizedBox(height: 8),
              Text(l.crashCommand(name)),
            ],
            if (report.recentCommands.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(l.crashRecent(report.recentCommands.join(', '))),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.crashDismiss),
        ),
        FilledButton(
          onPressed: () => unawaited(
            launchUrl(
              reportProblemUrl(
                environment: environment,
                whatHappened: report.describe(),
              ),
            ),
          ),
          child: Text(l.crashReport),
        ),
      ],
    );
  }
}
