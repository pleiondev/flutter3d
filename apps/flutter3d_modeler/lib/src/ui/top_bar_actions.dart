/// The top bar's own right-hand side: adding a primitive, opening, saving,
/// exporting, and the small utility icons beside them.
///
/// **A menu rather than five buttons on the rail.** The rail is for the tools
/// a hand rests on; adding a shape is something done once and then not again
/// for an hour, and five of anything on a rail of fifty-two pixels is a rail
/// nobody can read. `A` still adds a box, which is the one people reach for
/// without looking.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

import '../../l10n/app_localizations.dart';
import '../exporting.dart';
import '../play/play_template.dart';
import 'theme.dart';
import 'undo_redo_buttons.dart';

/// What the Add menu calls each of `AddPrimitive.primitiveKinds`, and the
/// icon beside it — `ux-31`.
///
/// **`box` is an argument and "Box" is a word.** The menu printed the command
/// argument verbatim, so a list of five lowercase keys was the first thing
/// somebody new met — the same string an agent passes over MCP, shown to a
/// person as though it were an interface. The ids are still what everything
/// runs on; this is the layer between them and a menu.
///
/// `tools_test.dart`'s own sibling check holds every kind to having one,
/// since a primitive added to the command without an entry here would be a
/// menu row printing a key again.
/// [kind]'s own word in [l]'s language, or null for a kind this build has
/// no entry for — `ux-22`.
///
/// **The icon table stays as it is and the words come out of it.** An icon
/// is the same picture in every language; only the label is not, and
/// splitting the two would leave two tables to add a primitive to.
String? primitiveLabel(AppLocalizations l, String kind) => switch (kind) {
  'box' => l.primitiveBox,
  'plane' => l.primitivePlane,
  'sphere' => l.primitiveSphere,
  'cylinder' => l.primitiveCylinder,
  'torus' => l.primitiveTorus,
  _ => kPrimitiveLabels[kind]?.label,
};

const Map<String, ({String label, IconData icon})> kPrimitiveLabels =
    <String, ({String label, IconData icon})>{
      'box': (label: 'Box', icon: Icons.check_box_outline_blank),
      'plane': (label: 'Plane', icon: Icons.crop_square_outlined),
      'sphere': (label: 'Sphere', icon: Icons.circle_outlined),
      'cylinder': (label: 'Cylinder', icon: Icons.local_drink_outlined),
      'torus': (label: 'Torus', icon: Icons.donut_large_outlined),
    };

/// What sits at the right of the top bar: adding a shape, opening, saving,
/// exporting, and the small utility icons beside them.
class TopBarActions extends StatelessWidget {
  const TopBarActions({
    super.key,
    required this.canUndo,
    required this.canRedo,
    required this.undoSays,
    required this.redoSays,
    required this.onUndo,
    required this.onRedo,
    required this.onAddPrimitive,
    required this.onOpen,
    required this.onImport,
    required this.onSave,
    this.isDirty = false,
    this.onSaveToCabinet,
    required this.onExport,
    required this.onMaterialStudio,
    required this.onPreview,
    required this.onPlay,
    this.playBlocked,
    this.splitViewport = false,
    this.onSplitViewport,
    required this.onShortcutHelp,
    this.onSettings,
    this.agentClient,
    this.agentCallCount = 0,
    this.onToggleAgentPanel,
    required this.onStartScreen,
    required this.onReportProblem,
  });

  final bool canUndo;
  final bool canRedo;

  /// What ⌘Z would take back, or null when there is nothing to.
  final String? undoSays;

  /// What ⇧⌘Z would put back, or null when there is nothing to.
  final String? redoSays;

  final VoidCallback onUndo;
  final VoidCallback onRedo;

  /// One of [AddPrimitive.primitiveKinds] was picked from the "Add" menu.
  final ValueChanged<String> onAddPrimitive;

  final VoidCallback onOpen;

  /// `tut-08`'s own entry: brings a second file in beside what is already
  /// open, through `ImportInto`, rather than [onOpen]'s own wholesale
  /// replacement.
  final VoidCallback onImport;

  final VoidCallback onSave;

  /// Whether the open document has unsaved changes — `ux-30`, which is what
  /// decides how loud the Save button is. False by default, so a caller that
  /// has not been told about it shows the quieter of the two.
  final bool isDirty;

  /// `tut-20`'s own write-back — null hides the button rather than showing
  /// it disabled, since a cabinet id and a mode that is not `view` are what
  /// decide whether this could ever succeed at all, not something a person
  /// picks in the interface. See `CabinetLink.canSaveBack`'s own doc
  /// comment for why that gate is UX only, never the real one.
  final VoidCallback? onSaveToCabinet;

  final ValueChanged<ExportFormat> onExport;
  final VoidCallback onMaterialStudio;

  /// `S9`'s own entry: opens screen 19's full-screen "preview like in the
  /// game" route — a route, not a mode, which is why it sits beside Export
  /// rather than on the mode switcher.
  final VoidCallback onPreview;

  /// `ux-51`: Play on one of `PlayTemplate`'s three.
  final ValueChanged<PlayTemplate> onPlay;

  /// Why Play cannot start, or null when it can — `ExportReadiness.says`
  /// for a document that will not export.
  ///
  /// **The same gate Export keeps, and the same words.** Play hands the
  /// document over exactly as an export does, so a project that cannot be
  /// exported cannot be played either; saying so in Export's own sentence
  /// rather than a second one written for this button means a person fixes
  /// one problem rather than learning two names for it.
  final String? playBlocked;

  /// `ux-38`: whether the viewport is drawn as two views of the document.
  final bool splitViewport;

  /// Turns the second view on and off. Null leaves the button out, which is
  /// what a shell with no layout to remember — a test pumping this widget on
  /// its own — gets.
  final ValueChanged<bool>? onSplitViewport;

  final VoidCallback onShortcutHelp;
  final VoidCallback onStartScreen;
  final VoidCallback onReportProblem;

  /// Opens `ux-09`'s own settings screen. Null in a test that has no
  /// settings store behind it, which is what keeps the button out of every
  /// shell test that never asked about it.
  final VoidCallback? onSettings;

  /// What the connected agent called itself, or null while nobody has
  /// connected — `ux-05`. Non-null puts a badge here and nothing else on
  /// screen; the panel opens from it.
  final String? agentClient;

  /// How many tool calls that agent has made, for the badge to count.
  final int agentCallCount;

  /// Shows or hides the agent panel.
  final VoidCallback? onToggleAgentPanel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UndoRedoButtons(
          canUndo: canUndo,
          canRedo: canRedo,
          undoSays: undoSays,
          redoSays: redoSays,
          onUndo: onUndo,
          onRedo: onRedo,
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: l.addPrimitiveTooltip,
          onSelected: onAddPrimitive,
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            for (final String kind in AddPrimitive.primitiveKinds)
              PopupMenuItem<String>(
                value: kind,
                height: ModelerMetrics.row,
                // `ux-31`: the word and its picture, not the command's own
                // argument. A kind with no entry falls back to the key, which
                // is worse than a label and better than an empty row — and
                // `top_bar_actions_test.dart` refuses one either way.
                child: Row(
                  children: <Widget>[
                    Icon(
                      kPrimitiveLabels[kind]?.icon ?? Icons.category_outlined,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      primitiveLabel(l, kind) ?? kind,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(l.add, style: const TextStyle(fontSize: 13)),
          ),
        ),
        // **Two buttons a word apart that do opposite things** — `ux-30`. The
        // review watched somebody press Open meaning Import and lose the scene
        // they had been building; the words themselves cannot be made to say
        // which is which, so the tooltips do.
        Tooltip(
          message: l.openTooltip,
          child: TextButton(onPressed: onOpen, child: Text(l.open)),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: l.importTooltip,
          child: TextButton(onPressed: onImport, child: Text(l.import)),
        ),
        const SizedBox(width: 4),
        // `ux-30`: filled only while there is something to save. A button that
        // is always the loudest thing on the bar says nothing by being loud,
        // and "have I saved this" is the one question the bar can answer
        // without being asked.
        Tooltip(
          message: isDirty ? l.saveTooltipDirty : l.saveTooltipClean,
          child: isDirty
              ? FilledButton(onPressed: onSave, child: Text(l.save))
              : FilledButton.tonal(onPressed: onSave, child: Text(l.save)),
        ),
        const SizedBox(width: 4),
        if (onSaveToCabinet case final VoidCallback onSaveToCabinet) ...[
          FilledButton.tonal(
            onPressed: onSaveToCabinet,
            child: Text(l.saveToCabinet),
          ),
          const SizedBox(width: 4),
        ],
        PopupMenuButton<ExportFormat>(
          tooltip: l.exportCopyTooltip,
          onSelected: onExport,
          itemBuilder: (BuildContext context) => <PopupMenuEntry<ExportFormat>>[
            for (final ExportFormat format in ExportFormat.values)
              PopupMenuItem<ExportFormat>(
                value: format,
                height: ModelerMetrics.row,
                child: Text(
                  // `ux-18`: `label` rather than `suffix`, because binary and
                  // ASCII STL write the same extension and this menu would
                  // otherwise offer `.stl` twice.
                  '${format.label}  ${format.says}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(l.export, style: const TextStyle(fontSize: 13)),
          ),
        ),
        // `mat-15`'s own entry: a preview tool rather than a command, so it
        // sits beside Export rather than on the object tool rail — nothing it
        // opens is a shape to add to the document.
        MergeSemantics(
          child: Semantics(
            label: l.materialStudioSemanticsLabel,
            button: true,
            child: IconButton(
              tooltip: l.materialStudioTooltip,
              onPressed: onMaterialStudio,
              icon: const Icon(Icons.tonality_outlined, size: 20),
            ),
          ),
        ),
        // `S9`'s own entry: screen 19's full-screen preview, beside Export for
        // the same reason Material Studio already sits here — a route, not a
        // shape to add and not a mode the switcher would otherwise offer.
        MergeSemantics(
          child: Semantics(
            label: l.preview,
            button: true,
            child: IconButton(
              tooltip: l.previewTooltip,
              onPressed: onPreview,
              icon: const Icon(Icons.play_circle_outline, size: 20),
            ),
          ),
        ),
        // `ux-38`: one document, two cameras. Beside the two preview buttons
        // because it answers the same family of question — what does this look
        // like from somewhere that is not here — and because it is a thing
        // about the window rather than about the document.
        if (onSplitViewport case final ValueChanged<bool> toggle)
          MergeSemantics(
            child: Semantics(
              label: l.splitViewportSemanticsLabel,
              button: true,
              toggled: splitViewport,
              child: IconButton(
                tooltip: splitViewport ? l.splitViewportOff : l.splitViewportOn,
                isSelected: splitViewport,
                onPressed: () => toggle(!splitViewport),
                icon: const Icon(Icons.splitscreen_outlined, size: 20),
              ),
            ),
          ),
        // `ux-51`: Play, beside Preview because the two are the same question
        // asked differently — Preview looks at the document the way a game
        // would draw it, Play walks around inside it. A menu rather than a
        // button, because the three templates answer three different
        // questions and picking one afterwards would mean stopping first.
        PopupMenuButton<PlayTemplate>(
          tooltip: playBlocked == null
              ? l.playTooltip
              : l.playBlockedTooltip(playBlocked!),
          enabled: playBlocked == null,
          onSelected: onPlay,
          itemBuilder: (BuildContext context) => <PopupMenuEntry<PlayTemplate>>[
            for (final PlayTemplate template in PlayTemplate.values)
              PopupMenuItem<PlayTemplate>(
                value: template,
                height: ModelerMetrics.row,
                child: Text(
                  '${template.label}  ${template.about}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
          child: MergeSemantics(
            child: Semantics(
              label: l.play,
              button: true,
              enabled: playBlocked == null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  l.play,
                  style: TextStyle(
                    fontSize: 13,
                    // The same grey a disabled `TextButton` takes, so a Play
                    // an export error is holding back reads as held back
                    // rather than as a button that swallowed the press.
                    color: playBlocked == null
                        ? null
                        : Theme.of(context).disabledColor,
                  ),
                ),
              ),
            ),
          ),
        ),
        // `ui-23`'s own pass: `IconButton.tooltip` sets
        // `SemanticsNode.tooltip`, not `.label`. `MergeSemantics` folds the
        // label below down onto the button's own inner, actually-tappable
        // node.
        MergeSemantics(
          child: Semantics(
            label: l.keyboardShortcuts,
            button: true,
            child: IconButton(
              tooltip: l.keyboardShortcutsTooltip,
              onPressed: onShortcutHelp,
              icon: const Icon(Icons.help_outline, size: 20),
            ),
          ),
        ),
        MergeSemantics(
          child: Semantics(
            label: l.startScreenSemanticsLabel,
            button: true,
            child: IconButton(
              tooltip: l.startScreenTooltip,
              onPressed: onStartScreen,
              icon: const Icon(Icons.home_outlined, size: 20),
            ),
          ),
        ),
        MergeSemantics(
          child: Semantics(
            label: l.reportProblem,
            button: true,
            child: IconButton(
              tooltip: l.reportProblemTooltip,
              onPressed: onReportProblem,
              icon: const Icon(Icons.bug_report_outlined, size: 20),
            ),
          ),
        ),
        // `ux-05`: an agent is on the document. A badge rather than a column
        // and a contact sheet taking a third of the window from the first
        // frame, which is what the live run found with nobody connected.
        if (agentClient case final String client)
          MergeSemantics(
            child: Semantics(
              label: l.agentSessionSemanticsLabel(agentCallCount),
              button: true,
              child: IconButton(
                tooltip: l.agentSessionTooltip(client, agentCallCount),
                onPressed: onToggleAgentPanel,
                icon: Badge(
                  isLabelVisible: agentCallCount > 0,
                  label: Text('$agentCallCount'),
                  child: const Icon(Icons.smart_toy, size: 20),
                ),
              ),
            ),
          ),
        if (onSettings case final VoidCallback open)
          MergeSemantics(
            child: Semantics(
              label: l.settings,
              button: true,
              child: IconButton(
                tooltip: l.settingsTooltip,
                onPressed: open,
                icon: const Icon(Icons.settings_outlined, size: 20),
              ),
            ),
          ),
      ],
    );
  }
}
