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

import '../mouse_hints.dart';

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

/// The project's texture weight against its own export budget — `mat-33d`'s
/// own "N MB of M": [usedBytes] is `measure(project, profile.textures)`'s own
/// `TextureUsage.totalBytes`, [budgetBytes] is that same call's
/// `TextureBudget.maxBytesOnDevice`. A record rather than the two types
/// themselves, so [StatusLine] reads two integers and formats them rather
/// than importing `texture_budget.dart`'s own shapes for a bar that has no
/// use for anything else on them.
typedef TextureBudgetStatus = ({int usedBytes, int budgetBytes});

class StatusLine extends StatelessWidget {
  const StatusLine({
    super.key,
    required this.said,
    required this.readiness,
    required this.triangles,
    required this.vertices,
    required this.materialCount,
    this.texelDensity,
    this.textureBudget,
    this.modeSummary,
    this.micros,
    this.onExport,
    this.onShowFolder,
    this.saidIsRefusal = false,
    this.mouseHints,
    this.onConsole,
  });

  /// What the three buttons do right now — `ux-26`. Null hides the segment,
  /// which is what a touch shell wants: there are no buttons to describe.
  final MouseHints? mouseHints;

  /// Opens the console — `ux-26`. Offered as the message itself, because the
  /// sentence in this strip is the last line of the log and "where did the
  /// rest of it go" is the question this answers. Null leaves the sentence
  /// plain, for a test or a shell with nowhere to put a panel.
  final VoidCallback? onConsole;

  /// What just happened, or what is selected when nothing has.
  final String said;

  /// Whether [said] is a refusal — `ux-17`. A refused command is the one
  /// message in this strip somebody has to notice, and it used to read
  /// exactly like "saved".
  final bool saidIsRefusal;

  /// What the project would refuse to export as, shown beside what just
  /// happened — because the moment to learn that a model has an n-gon in it is
  /// while it is being built rather than at the export dialogue.
  final ExportReadiness readiness;

  /// What the model draws as, which is the number a budget is spent in.
  final int triangles;

  /// Every object's own vertex count, summed — `ModelProject.vertexCount`.
  final int vertices;

  /// How many rows the material panel offers — `project.materials.length`.
  final int materialCount;

  /// The held object's own texel density, in texels/m — `texelDensityOf`'s
  /// own unit. Shown divided by 100, for "tex/cm". Null hides this segment:
  /// nothing selected, or nothing on the selection for that function to
  /// measure — see its own doc comment for the exact silent cases.
  final double? texelDensity;

  /// The project's texture weight against its own budget. Null hides this
  /// segment.
  final TextureBudgetStatus? textureBudget;

  /// `S2`'s own row: the animation mode's "Bones N · actions N · influences
  /// M per vertex" — screen 07's own status line — in place of the ordinary
  /// vertex/material segment [vertices]/[materialCount] would otherwise draw.
  /// Null keeps the ordinary segment, which is every mode but the animation
  /// mode's own pose sub-mode.
  final String? modeSummary;

  /// What the last frame cost. Null before one has been drawn.
  final int? micros;

  /// Called when the readiness sentence is tapped — `ui-10`'s own "клик →
  /// диалог экспорта". Null makes the sentence plain text again, for a test
  /// that has no export flow to hand it.
  final VoidCallback? onExport;

  /// Opens the folder autosave is failing to write into — `ux-01`'s own
  /// "Show folder", offered beside [said] only while
  /// `ModelerReady.autosaveTrouble` holds a folder to show.
  ///
  /// **Beside the sentence rather than inside it.** "Autosave is not working:
  /// no such file or directory" is already the longest thing this bar says,
  /// and it is the one sentence a person is expected to act on rather than
  /// read past; a button is the affordance, and it ellipsises away with the
  /// text it belongs to rather than shoving the counts sideways.
  final VoidCallback? onShowFolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 11/400 — `ui-38d`'s own section-label size and weight, for the status
    // bar's own text to match rather than sit a point larger beside it.
    final small = theme.textTheme.bodySmall?.copyWith(fontSize: 11);
    final tone = StatusTone.of(readiness);
    final Color toneColour = switch (tone) {
      StatusTone.quiet => theme.colorScheme.onSurfaceVariant,
      StatusTone.warn => theme.colorScheme.tertiary,
      StatusTone.refuse => theme.colorScheme.error,
    };
    final TextStyle? figureStyle = small?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      // Tabular figures, so a count does not shove its neighbour sideways
      // while somebody drags a vertex.
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    return Row(
      children: <Widget>[
        Flexible(
          flex: 2,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                // **The whole sentence in a tooltip, because the strip shows
                // one line of it.** A refusal naming an object and what is
                // wrong with it runs to a couple of hundred characters and
                // this line is a fraction of a window wide, so the part that
                // says what to do about it is exactly the part the ellipsis
                // eats — `ux-17`. `ux-26`: and a click on it opens the
                // console, where the whole of it is, along with everything
                // this line has already said and forgotten.
                child: Tooltip(
                  message: onConsole == null
                      ? said
                      : '$said\n(click to open the console)',
                  child: GestureDetector(
                    onTap: onConsole,
                    behavior: HitTestBehavior.translucent,
                    child: Text(
                      said,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: saidIsRefusal
                          ? small?.copyWith(
                              color: theme.colorScheme.tertiary,
                              fontWeight: FontWeight.w500,
                            )
                          : small,
                    ),
                  ),
                ),
              ),
              if (onShowFolder case final VoidCallback show)
                TextButton(
                  onPressed: show,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: small,
                  ),
                  child: const Text('Show folder'),
                ),
            ],
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
        // `ux-26`: what the three buttons do right now, between the sentence
        // and the counts. **Before the numbers rather than after them**: it
        // is the segment that changes as somebody works and the one they are
        // looking for, and the counts are what a glance at the far end of a
        // strip is for.
        if (mouseHints case final MouseHints hints)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              mouseHintLine(hints),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text('${grouped(triangles)} △', style: figureStyle),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text(
            modeSummary ??
                '${grouped(vertices)} vertices · ${grouped(materialCount)} '
                    'materials',
            style: small?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        if (texelDensity case final double density)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            // Stored in texels/m; a metre of texture is a hundred centimetres
            // of it, so this is the same number a hundredth as large.
            child: Text(
              '${(density / 100).toStringAsFixed(1)} tex/cm',
              style: figureStyle,
            ),
          ),
        if (textureBudget case final TextureBudgetStatus budget)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              '${_mebibytes(budget.usedBytes)} MB of '
              '${_mebibytes(budget.budgetBytes)}',
              style: figureStyle,
            ),
          ),
        if (micros case final int spent)
          Text('${(spent / 1000).toStringAsFixed(1)} ms', style: figureStyle),
      ],
    );
  }
}

/// [bytes] rounded to the nearest whole mebibyte — the unit `mat-33d`'s own
/// "N MB of M" reads in, the same binary megabyte `TextureBudget`'s own
/// desktop/mobile/web presets are already stated in (`256 * 1024 * 1024`
/// among them).
int _mebibytes(int bytes) => (bytes / (1024 * 1024)).round();
