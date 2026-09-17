/// Asks whether to export a model that will not load cleanly.
///
/// A dialog rather than a refusal, because the alternative is this
/// application deciding what somebody's model is for. It names what will be
/// wrong rather than counting it: "3 problems" is a number nobody can act on.
///
/// **Stays English.** There is no ARB entry for this one yet — that is a
/// separate line, not this one.
///
/// **Its own file so a test can build it**, the same reason [RecoveryDialog]
/// left `main.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import '../../../l10n/app_localizations.dart';

class ExportAnywayDialog extends StatelessWidget {
  const ExportAnywayDialog({
    required this.blocked,
    required this.issues,
    super.key,
  });

  final ExportBlocked blocked;
  final List<ExportIssue> issues;

  /// Shows the dialog and answers whether to export anyway. `false` for a
  /// dismissal without a choice, the same as tapping "Cancel".
  static Future<bool> show(
    BuildContext context, {
    required ExportBlocked blocked,
    required List<ExportIssue> issues,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext context) =>
            ExportAnywayDialog(blocked: blocked, issues: issues),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.exportAnywayTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(blocked.says),
          const SizedBox(height: 12),
          for (final ExportIssue issue in issues.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                issue.message,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          if (issues.length > 5)
            Text(
              l.exportAnywayMore(issues.length - 5),
              style: const TextStyle(fontSize: 12.5),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.exportAnyway),
        ),
      ],
    );
  }
}
