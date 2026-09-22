/// A button that runs a background bake — `ui-25`'s own row, the visible
/// half of `ModelerCubit.bakeInBackground`/`cancelBake`.
///
/// **Presentational only, the same split every other control in this shell
/// keeps.** The running job, its progress and what happens when it finishes
/// all live in `ModelerCubit`; this widget reads [progress] out of
/// `ModelerReady.jobs` and calls back on a tap, the same as
/// `status_line.dart` reads readiness rather than computing it.
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// An ordinary button labelled [label] when idle; a progress indicator with
/// a cancel affordance once [progress] is not null.
final class JobButton extends StatelessWidget {
  const JobButton({
    super.key,
    required this.label,
    required this.progress,
    required this.onStart,
    required this.onCancel,
  });

  /// What the idle button reads.
  final String label;

  /// Null while idle; `Job.progress`'s own 0-to-1 number while a bake runs.
  final double? progress;

  /// Called on a tap while idle.
  final VoidCallback onStart;

  /// Called on a tap while running. See `bakeInBackground`'s own doc comment
  /// for what this can and cannot still catch.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final double? running = progress;
    final AppLocalizations l = AppLocalizations.of(context);
    if (running == null) {
      return ElevatedButton(onPressed: onStart, child: Text(label));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(value: running, strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text('${(running * 100).round()}%'),
        // `ui-23`'s own pass: `tooltip:` alone sets `SemanticsNode.tooltip`,
        // not `.label`. `MergeSemantics` folds the label onto the button's
        // own inner, actually tappable node.
        MergeSemantics(
          child: Semantics(
            label: l.cancel,
            button: true,
            child: IconButton(
              icon: const Icon(Icons.close),
              tooltip: l.cancel,
              onPressed: onCancel,
            ),
          ),
        ),
      ],
    );
  }
}
