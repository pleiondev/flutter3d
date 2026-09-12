/// The phone layout — `ui-05`'s own row, the other half `shell.dart`'s
/// desktop `ModelerShell` left unbuilt.
///
/// **A `NavigationBar` for modes, a FAB for the armed tool, a shorter sheet
/// for properties.** A phone's own width has no room for a top bar of modes
/// and a rail of tools side by side, so the mode switch moves to the bottom
/// as a [ModelerMetrics.phoneNavBar]-tall `NavigationBar`, and the tool rail
/// — which needs the width, not the height, a phone least has to spare —
/// becomes a single [ModelerMetrics.phoneFab]-wide FAB that opens the same
/// [toolsFor] table as a sheet of its own. Same table, same ids, same
/// shortcuts: `ui-05`'s own acceptance is that a tool reachable on a desktop
/// is reachable here too, not that a phone gets a smaller version of one.
library;

import 'package:flutter/material.dart';

import 'shell.dart';
import 'shell_tablet.dart';
import 'theme.dart';
import 'tools.dart';

/// The phone shell: a bottom `NavigationBar` for modes, a FAB for tools.
class ModelerPhoneShell extends StatelessWidget {
  const ModelerPhoneShell({
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

  /// What a desktop puts at the right of its top bar. A phone has no top bar
  /// of its own to put them in, so they collect into one overflow menu
  /// instead of vanishing.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.extension<ModelerColors>() ?? ModelerColors.dark;
    final modeReady = ModelerMode.values.where((m) => m.isReady).toList();
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: actions.isEmpty
          ? null
          : AppBar(
              toolbarHeight: ModelerMetrics.statusBar + 22,
              actions: <Widget>[
                // **A bottom sheet, not a `PopupMenuItem`.** A menu item's
                // own `enabled: false` blocks taps to whatever it wraps —
                // the review found this made Save/Open/Export dead buttons
                // on phone width, the only width without a top bar to put
                // them in directly. `_openToolSheet` below already opens an
                // interactive bottom sheet for the same reason a menu won't
                // do; this reuses that same shape for the top-bar actions.
                IconButton(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _openActionsSheet(context),
                ),
              ],
            ),
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              // **Declared, but never placed until now.** `status` was
              // already a required parameter here — the review found phone
              // width was the one place a save/open/export message, or the
              // crash-adjacent selection status, had nowhere to appear at
              // all.
              SizedBox(
                height: ModelerMetrics.statusBar,
                child: ColoredBox(
                  color: colours.viewport,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Align(alignment: Alignment.centerLeft, child: status),
                  ),
                ),
              ),
              if (mode == ModelerMode.mesh)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  // Scrolls rather than shrinks, the same overflow guard
                  // `shell.dart`'s own top bar already needs — the mode
                  // switch inside `ModelerModeSwitcher` is drawn too, even
                  // though the `NavigationBar` below already offers it, since
                  // there is no public way here to ask for the submode row
                  // alone; a phone narrow enough to overflow scrolls it
                  // instead of losing the one control this mode needs.
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ModelerModeSwitcher(
                      mode: mode,
                      onMode: onMode,
                      submode: submode,
                      onSubmode: onSubmode,
                    ),
                  ),
                ),
              Expanded(
                child: ColoredBox(color: colours.viewport, child: viewport),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: ModelerMetrics.phoneNavBar,
            child: ModelerPropertiesSheet(
              height: ModelerMetrics.phonePropertiesSheet,
              child: properties,
            ),
          ),
        ],
      ),
      floatingActionButton: SizedBox(
        width: ModelerMetrics.phoneFab,
        height: ModelerMetrics.phoneFab,
        child: FloatingActionButton(
          onPressed: () => _openToolSheet(context),
          child: Icon(_armedIcon(mode, activeTool)),
        ),
      ),
      bottomNavigationBar: SizedBox(
        height: ModelerMetrics.phoneNavBar,
        child: NavigationBar(
          selectedIndex: modeReady.indexOf(mode).clamp(0, modeReady.length - 1),
          onDestinationSelected: (int index) => onMode(modeReady[index]),
          destinations: <NavigationDestination>[
            for (final ModelerMode each in modeReady)
              NavigationDestination(icon: Icon(each.icon), label: each.label),
          ],
        ),
      ),
    );
  }

  /// The FAB's own icon: the armed tool's, or the mode's first tool when the
  /// pointer itself is armed — a phone has no cursor to leave idle, so the
  /// FAB always shows the thing a tap would do next.
  IconData _armedIcon(ModelerMode mode, String? active) {
    final tools = toolsFor(mode);
    if (tools.isEmpty) return Icons.touch_app_outlined;
    final armed = tools.where((t) => t.id == active);
    return armed.isNotEmpty ? armed.first.icon : tools.first.icon;
  }

  /// [actions] laid out where a thumb can reach and a tap actually lands —
  /// the fix for the same disabled-`PopupMenuItem` bug `_openToolSheet`
  /// never had, since it always opened a real sheet instead.
  void _openActionsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: actions,
          ),
        ),
      ),
    );
  }

  /// Every tool [toolsFor] gives this mode, in a sheet a thumb can reach —
  /// the phone's own stand-in for the desktop rail and the tablet's own
  /// palette, reading the identical table both of them do.
  void _openToolSheet(BuildContext context) {
    final tools = toolsFor(mode);
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final ModelerTool tool in tools)
              ListTile(
                leading: Icon(tool.icon),
                title: Text(tool.label),
                trailing: Text(tool.shortcut.keyLabel.toUpperCase()),
                selected: tool.id == activeTool,
                onTap: () {
                  onTool(tool.id);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}
