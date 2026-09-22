/// Asks the three answers `close_guard.dart`'s own [UnsavedChoice] names,
/// put in front of a person once — every caller that finds the document
/// dirty on the way out asks through this one dialog rather than each
/// growing a slightly different one.
///
/// **Its own file so a test can build it**, the same reason [RecoveryDialog]
/// left `main.dart`.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../close_guard.dart';

class UnsavedChangesDialog extends StatelessWidget {
  const UnsavedChangesDialog({super.key});

  /// Shows the dialog and answers which of the three choices was made, or
  /// `null` if it was dismissed without one.
  static Future<UnsavedChoice?> show(BuildContext context) =>
      showDialog<UnsavedChoice>(
        context: context,
        builder: (BuildContext context) => const UnsavedChangesDialog(),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.unsavedChangesTitle),
      content: Text(l10n.unsavedChangesBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(UnsavedChoice.keepEditing),
          child: Text(l10n.keepEditing),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(UnsavedChoice.discard),
          child: Text(l10n.discard),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(UnsavedChoice.save),
          child: Text(l10n.saveAndClose),
        ),
      ],
    );
  }
}
