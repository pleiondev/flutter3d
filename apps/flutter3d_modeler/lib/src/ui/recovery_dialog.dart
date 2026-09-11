/// Asks whether to restore an autosave or open the file as it was last
/// saved, for the case `flutter3d_model_core`'s own `decideRecovery` answers
/// `RecoveryDecision.offerAutosave` — an autosave strictly newer than
/// whatever is on disk.
///
/// **Its own file so a test can build it**, the same reason `StatusLine` left
/// `main.dart` — pumping the whole shell to ask what two buttons say would
/// mean the question mostly goes unasked.
///
/// **Presents the choice; does not make it.** `decideRecovery` is what
/// decides an autosave is worth asking about at all, staying a pure function
/// `flutter3d_model_core` can test with no clock and no dialog. This widget
/// only has to be shown when that answer is `offerAutosave`.
library;

import 'package:flutter/material.dart';

class RecoveryDialog extends StatelessWidget {
  const RecoveryDialog({super.key});

  /// Shows the dialog and answers what was chosen: `true` for the autosave,
  /// `false` for the file as saved. Never dismissed without an answer — the
  /// two versions disagree about what the document is, and leaving that
  /// unresolved is not a third option a caller can act on.
  static Future<bool> show(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => const RecoveryDialog(),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Recover unsaved changes?'),
    content: const Text(
      'A more recent autosave was found than the last saved file. Restore '
      'it, or open the file as it was last saved?',
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Open saved file'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Restore autosave'),
      ),
    ],
  );
}
