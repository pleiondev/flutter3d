/// `ui-18`'s own "предложение восстановить": an autosave from a session
/// that never closed cleanly, offered once, naming how much it would bring
/// back rather than just that something was found.
///
/// **Its own file so a test can build it**, the same reason [RecoveryDialog]
/// left `main.dart`.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class RestoreAutosaveDialog extends StatelessWidget {
  const RestoreAutosaveDialog({required this.objectCount, super.key});

  /// How many objects the autosave would bring back — the number
  /// `restoreUnsavedChangesBody` pluralizes on.
  final int objectCount;

  /// Shows the dialog and answers whether to restore, or `null` if it was
  /// dismissed without a choice.
  static Future<bool?> show(BuildContext context, {required int objectCount}) =>
      showDialog<bool>(
        context: context,
        builder: (BuildContext context) =>
            RestoreAutosaveDialog(objectCount: objectCount),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.restoreUnsavedChangesTitle),
      content: Text(l10n.restoreUnsavedChangesBody(objectCount)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.discard),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.restore),
        ),
      ],
    );
  }
}
