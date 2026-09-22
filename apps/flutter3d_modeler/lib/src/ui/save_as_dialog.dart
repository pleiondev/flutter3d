/// `ui-33d`'s own "Save without history" checkbox, asked once ahead of the
/// native "Save as" panel `_saveFile` opens next.
///
/// **A dialog rather than a setting remembered from last time.** Whether the
/// undo stack rides along in the file is a question about *this* save, the
/// same way `ui-17`'s own "bake node transforms" is about *this* export —
/// asked fresh every time rather than defaulted from whatever the previous
/// save happened to choose. Unticked is the default, because the plain "Save"
/// most people reach for should keep undo working the next time the file is
/// opened; the smaller file is the thing somebody has to ask for.
///
/// Autosave (`ui-18`) never shows this screen at all: `AutosaveController`
/// calls `writeProject` on its own timer, with no dialog and no person to ask.
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// What the person chose, or null from [showSaveAsScreen] when they backed
/// out of the dialog without saving.
final class SaveAsChoice {
  const SaveAsChoice({required this.includeHistory});

  /// `doc-31d`'s own `history` section: written when true, left out of the
  /// file when the "Save without history" checkbox was ticked.
  final bool includeHistory;
}

/// Opens `ui-33d`'s own confirmation ahead of the native "Save as" panel.
Future<SaveAsChoice?> showSaveAsScreen(BuildContext context) =>
    showDialog<SaveAsChoice>(
      context: context,
      builder: (BuildContext context) => const _SaveAsScreen(),
    );

class _SaveAsScreen extends StatefulWidget {
  const _SaveAsScreen();

  @override
  State<_SaveAsScreen> createState() => _SaveAsScreenState();
}

class _SaveAsScreenState extends State<_SaveAsScreen> {
  bool _withoutHistory = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.saveAsTitle),
      content: SizedBox(
        width: 360,
        child: CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(l.saveWithoutHistory),
          subtitle: Text(l.saveWithoutHistoryHelp),
          value: _withoutHistory,
          onChanged: (bool? to) =>
              setState(() => _withoutHistory = to ?? false),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(SaveAsChoice(includeHistory: !_withoutHistory)),
          child: Text(l.save),
        ),
      ],
    );
  }
}
