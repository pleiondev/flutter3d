/// Picks which of `ui-05`'s three shells a width draws as, and builds it.
///
/// **Replaces a `LayoutBuilder` that used to sit inline in `main.dart`.**
/// [ScreenParts] (`screen_parts.dart`) is the four widgets built once; this
/// reads `LayoutClass.of` off the incoming width and hands them to
/// `ModelerShell`, `ModelerTabletShell` or `ModelerPhoneShell` — the same
/// three constructors the old inline `switch` already called, now behind
/// one name a screen can hand its parts to without knowing the three shells
/// exist.
library;

import 'package:flutter/material.dart';

import '../settings.dart' show Workspace;
import 'keymap.dart';
import 'layout_class.dart';
import 'screen_parts.dart';
import 'shell.dart';
import 'shell_phone.dart';
import 'shell_tablet.dart';
import 'theme.dart' show withTouchTargets;
import 'tools.dart';

/// [parts], drawn through whichever of the three shells fits
/// `constraints.maxWidth`.
class ShellForWidth extends StatelessWidget {
  /// The picker over [parts]; which shell it builds is decided by the width
  /// it is laid out in, on every layout.
  const ShellForWidth({
    super.key,
    required this.parts,
    required this.mode,
    required this.onMode,
    this.workspace = Workspace.full,
    required this.submode,
    required this.onSubmode,
    required this.animationSubmode,
    required this.onAnimationSubmode,
    required this.activeTool,
    required this.onTool,
    required this.documentName,
    required this.isDirty,
    this.bottom,
    this.bottomHeight,
    this.agentPanel,
    this.keymap,
    this.propertiesWidth,
    this.onPropertiesWidth,
    this.foldedPanel = false,
    this.foldedRail = false,
    this.railExtras = const <RailEntry>[],
  });

  /// `ux-23`: what the desktop rail lists under its tools. The touch shells
  /// draw a palette rather than a rail and have no place for it.
  final List<RailEntry> railExtras;

  /// `ux-27`'s own three: how wide the properties panel is, what a drag on
  /// its splitter reports, and whether either it or the rail is folded away.
  /// The desktop shell alone — the touch shells put the panel in a sheet,
  /// which has no splitter to drag and nothing to fold it out of the way of.
  final double? propertiesWidth;

  /// The splitter was dragged, with the new panel width in logical pixels.
  /// Desktop only.
  final ValueChanged<double>? onPropertiesWidth;

  /// Whether the properties panel is folded away. Desktop only.
  final bool foldedPanel;

  /// Whether the tool rail is folded away. Desktop only.
  final bool foldedRail;

  /// Which keys the desktop rail's own tooltips name — `ux-10`. The touch
  /// shells have no tooltips of their own to carry it into.
  final Keymap? keymap;

  /// The four widgets of the screen, built once and handed to whichever
  /// shell is drawn.
  final ScreenParts parts;

  /// The mode on screen, handed to all three shells.
  final ModelerMode mode;

  /// A mode was picked, from whichever shell is drawn.
  final ValueChanged<ModelerMode> onMode;

  /// Which set of modes the switcher offers — `ux-37`. Full by default, so a
  /// caller that has not been told about workspaces shows what it always did.
  final Workspace workspace;

  /// The element level mesh mode edits at, handed to all three shells.
  final MeshSubmode submode;

  /// An element level was picked.
  final ValueChanged<MeshSubmode> onSubmode;

  /// `ui-40d`'s own row, handed to the desktop shell alone: the tablet and
  /// phone branches below do not yet wire the animation mode's own
  /// switcher, the same as `ModelerModeSwitcher`'s own two nullable fields.
  final AnimationSubmode animationSubmode;

  /// An animation sub-mode was picked. Only the desktop shell can call it.
  final ValueChanged<AnimationSubmode> onAnimationSubmode;

  /// The id of the armed tool, from `ModelerTool.id`. Null is the pointer.
  final String? activeTool;

  /// A tool was pressed, by its `ModelerTool.id`, from the rail, the
  /// palette or the phone's tool sheet.
  final ValueChanged<String> onTool;

  /// What the open document is called, for the top bar's leading label —
  /// handed to all three shells, since `ux-21` made the tablet and the phone
  /// draw it too.
  final String documentName;

  /// Whether [documentName] carries unsaved changes, for the same label.
  final bool isDirty;

  /// `ui-41d`'s own slot, handed to the desktop shell alone — see
  /// [ModelerShell.bottom]'s own doc comment for why the tablet and phone
  /// branches below have no equivalent to hand it to.
  final Widget? bottom;

  /// [bottom]'s height, in logical pixels; given with [bottom] or not at
  /// all.
  final double? bottomHeight;

  /// `tut-16`'s own slot, handed to the desktop shell alone — see
  /// [ModelerShell.agentPanel]'s own doc comment for why the tablet and
  /// phone branches below have no equivalent to hand it to.
  final Widget? agentPanel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) =>
        switch (LayoutClass.of(constraints.maxWidth)) {
          LayoutClass.desktop => ModelerShell(
            mode: mode,
            onMode: onMode,
            workspace: workspace,
            submode: submode,
            onSubmode: onSubmode,
            animationSubmode: animationSubmode,
            onAnimationSubmode: onAnimationSubmode,
            activeTool: activeTool,
            onTool: onTool,
            actions: parts.actions,
            status: parts.status,
            properties: parts.properties,
            viewport: parts.viewport,
            documentName: documentName,
            isDirty: isDirty,
            bottom: bottom,
            bottomHeight: bottomHeight,
            agentPanel: agentPanel,
            keymap: keymap,
            propertiesWidth: propertiesWidth,
            onPropertiesWidth: onPropertiesWidth,
            foldedPanel: foldedPanel,
            foldedRail: foldedRail,
            railExtras: railExtras,
          ),
          // `ux-21`: on both touch shells the panel is a sheet under a thumb
          // rather than a column under a cursor, so everything in it is
          // grown to a finger's own size. The viewport and the status line
          // are left alone — one is a picture and the other is a sentence.
          LayoutClass.tablet => ModelerTabletShell(
            mode: mode,
            onMode: onMode,
            workspace: workspace,
            submode: submode,
            onSubmode: onSubmode,
            activeTool: activeTool,
            onTool: onTool,
            actions: parts.actions,
            status: parts.status,
            properties: withTouchTargets(context, parts.properties),
            viewport: parts.viewport,
            documentName: documentName,
            isDirty: isDirty,
          ),
          LayoutClass.phone => ModelerPhoneShell(
            mode: mode,
            onMode: onMode,
            workspace: workspace,
            submode: submode,
            onSubmode: onSubmode,
            activeTool: activeTool,
            onTool: onTool,
            actions: parts.actions,
            status: parts.status,
            properties: withTouchTargets(context, parts.properties),
            viewport: parts.viewport,
            documentName: documentName,
            isDirty: isDirty,
          ),
        },
  );
}
