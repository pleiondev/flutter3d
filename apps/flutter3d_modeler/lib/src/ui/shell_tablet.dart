/// The tablet layout — `ui-05`'s own row, the half of it `shell.dart`'s
/// desktop `ModelerShell` left unbuilt.
///
/// **Same frame, narrower palette, properties moved to a sheet.** A tablet's
/// own hand does not need the desktop's 52-wide rail, and its own screen does
/// not have the width to spare for a fixed side panel — so the rail becomes a
/// [ModelerMetrics.tabletPalette]-wide icon column and the properties panel
/// becomes a bottom sheet with a drag handle, [ModelerMetrics.tabletPropertiesSheet]
/// tall by default. Everything else — the top bar, the mode switch, the
/// viewport, the status line — is unchanged from the desktop shell, because
/// `ui-05`'s own acceptance is that the same tools answer the same keys in
/// every shell, not that a tablet redesigns what a desktop already got right.
library;

import 'package:flutter/material.dart';

import '../settings.dart' show Workspace;
import 'shell.dart';
import 'theme.dart';
import 'tool_strings.dart';
import 'tools.dart';

/// The tablet shell: a palette instead of a rail, a sheet instead of a panel.
class ModelerTabletShell extends StatelessWidget {
  const ModelerTabletShell({
    super.key,
    required this.mode,
    required this.onMode,
    this.workspace = Workspace.full,
    required this.submode,
    required this.onSubmode,
    required this.activeTool,
    required this.onTool,
    required this.viewport,
    required this.properties,
    required this.status,
    this.actions = const <Widget>[],
    this.documentName = 'untitled',
    this.isDirty = false,
  });

  /// What the open document is called, and whether it has unsaved changes —
  /// `ux-21`. Drawn here for the same reason the desktop bar draws it: a
  /// person who cannot see which file is open, or that it is unsaved, has
  /// only the window title to go on, and a web build has no window title.
  final String documentName;
  final bool isDirty;

  final ModelerMode mode;
  final ValueChanged<ModelerMode> onMode;

  /// Which set of modes the switcher offers — `ux-37`. Full by default, so a
  /// caller that has not been told about workspaces shows what it always did.
  final Workspace workspace;

  final MeshSubmode submode;
  final ValueChanged<MeshSubmode> onSubmode;

  /// The id of the armed tool, from [ModelerTool.id]. Null is the pointer.
  final String? activeTool;
  final ValueChanged<String> onTool;

  final Widget viewport;
  final Widget properties;
  final Widget status;

  /// What sits at the right of the top bar: opening, saving, exporting.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.extension<ModelerColors>() ?? ModelerColors.dark;
    return Scaffold(
      // `ux-32`: the hand-off's own "фон окна" is `surfaceContainerLowest`,
      // not `surface`. The two differ by five points of lightness, which is
      // exactly enough for the panels drawn on top of it to sit a shade
      // *darker* than the window they are in rather than a shade lighter.
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: Column(
        children: <Widget>[
          SizedBox(
            height: ModelerMetrics.topBar,
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: <Widget>[
                    // `ux-21`, and the same fixed cap the desktop bar uses:
                    // a `Flexible` name steals the width the mode switcher's
                    // own horizontal scroll needs on exactly the widths this
                    // shell is for.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        documentLabel(documentName, isDirty: isDirty),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ModelerModeSwitcher(
                          workspace: workspace,
                          mode: mode,
                          onMode: onMode,
                          submode: submode,
                          onSubmode: onSubmode,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ...actions,
                  ],
                ),
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Outside the viewport's own `Stack` below, and not a fourth
                // element inside it: the sheet overlays the picture, which is
                // what a person reaches past to see more of it, never the
                // palette a thumb still needs while the sheet is open.
                _TabletPalette(mode: mode, active: activeTool, onTool: onTool),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      ColoredBox(color: colours.viewport, child: viewport),
                      // A sheet over the viewport's own bottom edge rather
                      // than a fourth column: the properties panel is
                      // something reached for and put away, not something a
                      // tablet's own narrower width can afford to keep
                      // permanently beside the picture.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ModelerPropertiesSheet(
                          height: ModelerMetrics.tabletPropertiesSheet,
                          child: properties,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          SizedBox(
            height: ModelerMetrics.statusBar,
            child: ColoredBox(
              // `ux-32`: the hand-off puts the status line on
              // `surfaceContainerLow`, the same tone as the tool rail — the
              // two frame the picture, and the top bar above it is the lighter
              // one.
              color: theme.colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(alignment: Alignment.centerLeft, child: status),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The narrow icon column `ui-05`'s own row asks for in place of the
/// desktop's [ModelerMetrics.rail]-wide one — same [toolsFor], same order,
/// same shortcuts, only the column is narrower and the label lives in the
/// tooltip alone.
class _TabletPalette extends StatelessWidget {
  const _TabletPalette({
    required this.mode,
    required this.active,
    required this.onTool,
  });

  final ModelerMode mode;
  final String? active;
  final ValueChanged<String> onTool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tools = toolsFor(mode);
    return SizedBox(
      width: ModelerMetrics.tabletPalette,
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerLow,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: tools.length,
          itemBuilder: (BuildContext context, int index) {
            final tool = tools[index];
            final startsGroup =
                index > 0 && tools[index - 1].group != tool.group;
            final armed = tool.id == active;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (startsGroup)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Divider(height: 1),
                  ),
                // `ui-23`'s own pass: a `Tooltip` labels `SemanticsNode.tooltip`
                // alone, not `.label`. `MergeSemantics` folds this node's
                // label down onto `IconButton`'s own inner, actually-tappable
                // node rather than leaving it on a separate sibling node.
                MergeSemantics(
                  child: Semantics(
                    label: toolLabelIn(context, tool),
                    button: true,
                    child: Tooltip(
                      // `ux-18`: the same second line the desktop rail shows
                      // — `ModelerTool.about`, written once in `tools.dart`.
                      message:
                          '${toolLabelIn(context, tool)}  ·  '
                          '${tool.shortcut.keyLabel.toUpperCase()}\n'
                          '${toolAboutIn(context, tool)}',
                      child: IconButton(
                        onPressed: () => onTool(tool.id),
                        icon: Icon(tool.icon, size: 16),
                        // The shared `iconButtonTheme` sizes a button for a
                        // mouse (`ModelerMetrics.railButton`, 36) — right for
                        // the desktop rail, short of a touch target's own 48 on
                        // the shell a thumb actually uses this on.
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(48),
                          backgroundColor: armed
                              ? theme.colorScheme.primaryContainer
                              : null,
                          foregroundColor: armed
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A bottom sheet with a drag handle at [height] — the tablet's own
/// properties panel and, at a different [height], the phone's
/// (`shell_phone.dart`, which is why this is public rather than private to
/// this file).
///
/// A fixed height with a handle drawn on it rather than a
/// `DraggableScrollableSheet`: `ui-05`'s own acceptance asks for a sheet at a
/// stated height and for the same tools to be reachable through it, not for a
/// person to be able to resize it — that is a real, later refinement this
/// does not need to carry to close honestly.
class ModelerPropertiesSheet extends StatelessWidget {
  const ModelerPropertiesSheet({
    super.key,
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Material(
        // `ux-32`: the hand-off's own "лист" is `surfaceContainer`, the same
        // tone the properties panel takes on a desktop — it is the same
        // panel, laid out for a thumb.
        color: theme.colorScheme.surfaceContainer,
        elevation: 4,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 6),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                // `ux-34`: 40 % of `onSurfaceVariant` over this sheet came
                // out at 2.7:1, and the handle is the only thing saying the
                // sheet can be dragged at all. `ModelerColors.controlTrack`
                // is opaque and clears 3:1 — a handle drawn through an alpha
                // also changes ratio whenever the sheet's own tone does,
                // which is a check nobody would think to redo.
                color: (theme.extension<ModelerColors>() ?? ModelerColors.dark)
                    .controlTrack,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
