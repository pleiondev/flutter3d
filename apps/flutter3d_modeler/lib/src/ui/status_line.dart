/// The strip along the bottom: what just happened, what the model would refuse
/// to export as, how big it is and what the last frame cost.
///
/// **Its own file so a test can build it.** It lived inside `main.dart` as a
/// private class, which meant the only way to ask what colour a warning shows
/// in was to pump the whole shell — so the question went unasked, and the
/// answer was "the same as everything else".
///
/// **Three colours, not two, and that is a change of mind worth recording.**
/// This used to colour only a refusal, on the reasoning that a bar which turns
/// orange whenever anything at all is imperfect is a bar people stop reading.
/// That reasoning is right about a bar with two states and wrong about the
/// model: a quad that the exporter will cut and an object that will not load
/// are different news, and flattening them meant the first was invisible until
/// somebody opened the export dialogue. Ready is quiet, a warning is warm, a
/// refusal is the error colour — three levels, each meaning one thing.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// How loudly the bar should say what it is saying.
enum StatusTone {
  /// Nothing is wrong: the sentence is about what just happened.
  quiet,

  /// It will export and somebody will be disappointed by it — a quad cut the
  /// way the writer felt like, a shell wound inside out, a model over budget.
  warn,

  /// It will not export at all.
  refuse;

  /// The tone [readiness] calls for.
  static StatusTone of(ExportReadiness readiness) {
    if (!readiness.canExport) return StatusTone.refuse;
    return readiness.issues.isEmpty ? StatusTone.quiet : StatusTone.warn;
  }
}

/// [count] with its thousands grouped, for a number a person reads rather than
/// computes with.
///
/// **A thin space, and not `NumberFormat`.** Grouping by locale wants `intl`,
/// and `intl` arrives with `ui-22` — the whole interface's strings, not one
/// number's separator. Pulling the package in now for a single call would be a
/// dependency taken for a tenth of what it does, and taken again differently
/// when the real one lands. The thin space is what the rest of this interface
/// already uses and is right in both languages it will ship in; when `ui-22`
/// brings a formatter, this is one call site to change.
/// U+2009, written as an escape rather than as itself: an invisible character
/// in source is one nobody can see is wrong, and this file already lost half an
/// hour to a test that compared it against an ordinary space.
const String thinSpace = '\u2009';

String grouped(int count) {
  final digits = count.abs().toString();
  final out = StringBuffer(count < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(thinSpace);
    out.write(digits[i]);
  }
  return out.toString();
}

class StatusLine extends StatelessWidget {
  const StatusLine({
    super.key,
    required this.said,
    required this.readiness,
    required this.triangles,
    this.micros,
    this.onExport,
  });

  /// What just happened, or what is selected when nothing has.
  final String said;

  /// What the project would refuse to export as, shown beside what just
  /// happened — because the moment to learn that a model has an n-gon in it is
  /// while it is being built rather than at the export dialogue.
  final ExportReadiness readiness;

  /// What the model draws as, which is the number a budget is spent in.
  final int triangles;

  /// What the last frame cost. Null before one has been drawn.
  final int? micros;

  /// Called when the readiness sentence is tapped — `ui-10`'s own "клик →
  /// диалог экспорта". Null makes the sentence plain text again, for a test
  /// that has no export flow to hand it.
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final tone = StatusTone.of(readiness);
    final Color toneColour = switch (tone) {
      StatusTone.quiet => theme.colorScheme.onSurfaceVariant,
      StatusTone.warn => theme.colorScheme.tertiary,
      StatusTone.refuse => theme.colorScheme.error,
    };

    return Row(
      children: <Widget>[
        Flexible(
          flex: 2,
          child: Text(
            said,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: small,
          ),
        ),
        // **Flexible, not fixed, and a test found out why.** A `Text` with
        // `maxLines: 1` still asks for its full intrinsic width inside a `Row`;
        // the ellipsis only appears once something constrains it. A refusal
        // naming an object runs to a couple of hundred characters, so an
        // unconstrained one pushed the triangle count and the frame time off
        // the right-hand edge — 1518 pixels of overflow in an 800-pixel window.
        // It gets the larger share of the flexible room because it is the more
        // important of the two sentences.
        Flexible(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: MouseRegion(
              cursor: onExport == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onExport,
                behavior: HitTestBehavior.translucent,
                child: Text(
                  readiness.says,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small?.copyWith(color: toneColour),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text(
            '${grouped(triangles)} △',
            style: small?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              // Tabular figures, so the count does not shove the frame time
              // sideways while somebody drags a vertex.
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (micros case final int spent)
          Text(
            '${(spent / 1000).toStringAsFixed(1)} ms',
            style: small?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}
