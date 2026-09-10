/// The frame everything else is put into: a bar of modes, a rail of tools, the
/// picture, a panel of properties and a line of status.
///
/// **The frame is here and the contents are not, which is the whole shape of
/// it.** `ui-04` says the content of each region is replaced wholesale when the
/// mode changes; that only works if the frame knows nothing about what is in
/// it. So this takes four widgets and puts them in four places, and the panels
/// that read a document live with the document.
///
/// **Why the sizes are constants and not `Expanded`.** A modeller is measured:
/// the design gives a top bar of 52, a rail of 52, a properties panel between
/// 250 and 330 and a status line of 30, and those numbers are what makes two
/// screenshots of two builds comparable. `ui-04`'s acceptance measures the real
/// `RenderBox` at 1440×900, which is why nothing here is left to a flex factor.
library;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'tools.dart';

/// The desktop layout. The tablet and phone ones are `ui-05`; they show the
/// same tools, from the same table, in a palette and a sheet.
class ModelerShell extends StatelessWidget {
  const ModelerShell({
    super.key,
    required this.mode,
    required this.onMode,
    required this.submode,
    required this.onSubmode,
    required this.activeTool,
    required this.onTool,
    required this.viewport,
    required this.properties,
    required this.status,
    this.actions = const <Widget>[],
  });

  final ModelerMode mode;
  final ValueChanged<ModelerMode> onMode;

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
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: <Widget>[
          _TopBar(
            mode: mode,
            onMode: onMode,
            submode: submode,
            onSubmode: onSubmode,
            actions: actions,
          ),
          const Divider(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Rail(mode: mode, active: activeTool, onTool: onTool),
                const VerticalDivider(width: 1, thickness: 1),
                // The picture takes whatever is left, and takes it last: the
                // panels are the fixed things and the viewport is what a wider
                // window gives more of.
                Expanded(
                  child: ColoredBox(color: colours.viewport, child: viewport),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: ModelerMetrics.propertiesMin,
                    maxWidth: ModelerMetrics.propertiesMax,
                  ),
                  child: SizedBox(
                    width: ModelerMetrics.propertiesMin,
                    child: ColoredBox(
                      color: theme.colorScheme.surfaceContainerLow,
                      child: properties,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          SizedBox(
            height: ModelerMetrics.statusBar,
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainer,
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.mode,
    required this.onMode,
    required this.submode,
    required this.onSubmode,
    required this.actions,
  });

  final ModelerMode mode;
  final ValueChanged<ModelerMode> onMode;
  final MeshSubmode submode;
  final ValueChanged<MeshSubmode> onSubmode;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: ModelerMetrics.topBar,
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: <Widget>[
              // **The modes and the level take what is left after the actions,
              // and scroll inside it.** A top bar that overflows is not a
              // cosmetic fault: Flutter paints the striped banner over the
              // controls at the end of the row, so the thing that becomes
              // unusable is whatever was last — here, the element level, in the
              // one mode that has one. Eight modes and three levels do not fit
              // beside two buttons under about 1100 logical pixels, which is an
              // ordinary window on a laptop.
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _Modes(
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
    );
  }
}

/// The two segmented buttons, as one row.
class _Modes extends StatelessWidget {
  const _Modes({
    required this.mode,
    required this.onMode,
    required this.submode,
    required this.onSubmode,
  });

  final ModelerMode mode;
  final ValueChanged<ModelerMode> onMode;
  final MeshSubmode submode;
  final ValueChanged<MeshSubmode> onSubmode;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      SegmentedButton<ModelerMode>(
        showSelectedIcon: false,
        segments: <ButtonSegment<ModelerMode>>[
          for (final ModelerMode each in ModelerMode.values)
            ButtonSegment<ModelerMode>(
              value: each,
              icon: Icon(each.icon, size: 15),
              // Only phase one answers. The rest are drawn and
              // refused, so that what the modeller is going to be is
              // visible from the first build rather than arriving as a
              // surprise — and so a person who presses one is told it
              // is coming rather than left wondering whether they
              // missed a setting.
              enabled: each.isReady,
              tooltip: each.isReady
                  ? each.label
                  : '${each.label} — phase ${each.phase}',
            ),
        ],
        selected: <ModelerMode>{mode},
        onSelectionChanged: (Set<ModelerMode> picked) => onMode(picked.first),
      ),
      const SizedBox(width: 12),
      // The sub-mode belongs to the mesh mode and to nothing else, so
      // it is absent rather than disabled elsewhere: a control that is
      // permanently grey in seven modes out of eight is a control
      // people stop seeing.
      if (mode == ModelerMode.mesh)
        SegmentedButton<MeshSubmode>(
          showSelectedIcon: false,
          segments: <ButtonSegment<MeshSubmode>>[
            for (final MeshSubmode each in MeshSubmode.values)
              ButtonSegment<MeshSubmode>(
                value: each,
                icon: Icon(each.icon, size: 15),
                label: Text(each.label),
              ),
          ],
          selected: <MeshSubmode>{submode},
          onSelectionChanged: (Set<MeshSubmode> picked) =>
              onSubmode(picked.first),
        ),
    ],
  );
}

class _Rail extends StatelessWidget {
  const _Rail({required this.mode, required this.active, required this.onTool});

  final ModelerMode mode;
  final String? active;
  final ValueChanged<String> onTool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tools = toolsFor(mode);
    return SizedBox(
      width: ModelerMetrics.rail,
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
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Divider(height: 1),
                  ),
                Tooltip(
                  message:
                      '${tool.label}  ·  '
                      '${tool.shortcut.keyLabel.toUpperCase()}',
                  child: IconButton(
                    onPressed: () => onTool(tool.id),
                    icon: Icon(tool.icon, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: armed
                          ? theme.colorScheme.primaryContainer
                          : null,
                      foregroundColor: armed
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
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
