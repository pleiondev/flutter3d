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

import '../settings.dart' show Workspace;
import 'keymap.dart';
import 'shortcut_help.dart' show describeShortcut;
import 'theme.dart';
import 'tool_strings.dart';
import 'tools.dart';

/// The desktop layout. The tablet and phone ones are `ui-05`; they show the
/// same tools, from the same table, in a palette and a sheet.
///
/// What the open document is called, with its unsaved marker — one spelling
/// for all three shells, `ux-21`.
///
/// **The marker leads, the same way `windowTitleFor` puts it in the window
/// title.** A dot after the name reads as punctuation at the end of a word
/// and is lost against a panel edge; in front of it, at the start of a line,
/// it is the first thing in the bar. The row asked for "name •" and this is
/// the deviation: what matters is that a person can see the document is
/// unsaved without opening anything, and one spelling in three shells and a
/// title bar is worth more than either order.
String documentLabel(String name, {required bool isDirty}) =>
    isDirty ? '• $name' : name;

/// The desktop shell.
class ModelerShell extends StatelessWidget {
  const ModelerShell({
    super.key,
    required this.mode,
    required this.onMode,
    this.workspace = Workspace.full,
    required this.submode,
    required this.onSubmode,
    required this.animationSubmode,
    required this.onAnimationSubmode,
    required this.activeTool,
    required this.onTool,
    required this.viewport,
    required this.properties,
    required this.status,
    this.actions = const <Widget>[],
    this.documentName = 'untitled',
    this.isDirty = false,
    this.bottom,
    this.bottomHeight,
    this.agentPanel,
    this.keymap,
    this.propertiesWidth,
    this.onPropertiesWidth,
    this.foldedPanel = false,
    this.foldedRail = false,
    this.railExtras = const <RailEntry>[],
  }) : assert(
         (bottom == null) == (bottomHeight == null),
         'bottom and bottomHeight are given together or not at all',
       );

  final ModelerMode mode;
  final ValueChanged<ModelerMode> onMode;

  /// Which set of modes the switcher offers — `ux-37`. Full by default, so a
  /// caller that has not been told about workspaces shows what it always did.
  final Workspace workspace;

  final MeshSubmode submode;
  final ValueChanged<MeshSubmode> onSubmode;

  /// `ui-40d`'s own row: [submode]'s counterpart for [ModelerMode.animation],
  /// read by both the top bar's second switcher and the rail — the two
  /// places [submode] already reaches.
  final AnimationSubmode animationSubmode;
  final ValueChanged<AnimationSubmode> onAnimationSubmode;

  /// The id of the armed tool, from [ModelerTool.id]. Null is the pointer.
  final String? activeTool;
  final ValueChanged<String> onTool;

  final Widget viewport;
  final Widget properties;
  final Widget status;

  /// What sits at the right of the top bar: opening, saving, exporting.
  final List<Widget> actions;

  /// What is open, for the top bar's own leading label — the review found
  /// nothing in the running app showed this anywhere but the OS window
  /// title, invisible maximized, in a webview, or on phone.
  final String documentName;

  /// Whether [documentName] carries unsaved changes, for the same leading
  /// label — the marker `windowTitleFor` already puts in the window title,
  /// read here off the same source rather than a second one.
  final bool isDirty;

  /// `ui-41d`'s own slot: the mode's own lower area, under the viewport and
  /// between the rail and the properties panel — the animation mode's
  /// timeline (`S2`), the weights sub-mode's bend bar (`S5`), and nothing at
  /// all for every mode that has no lower area of its own. Desktop only:
  /// `ModelerTabletShell` and `ModelerPhoneShell` keep today's sheet-based
  /// layout, which has no equivalent slot.
  final Widget? bottom;

  /// [bottom]'s own height. Given together with [bottom] or not at all —
  /// see the constructor's assert — so a caller that fills the slot cannot
  /// forget to size it and leave it to whatever [bottom] happens to want.
  final double? bottomHeight;

  /// `tut-16`'s own slot: screen 26's own agent-session panel, appended
  /// after [properties] rather than replacing it — a person keeps every
  /// ordinary control while `--mcp-port` is open, and this is what shows
  /// beside them what an agent connected to it is doing. Null draws
  /// nothing extra, the same "nothing at all" [bottom]'s own doc comment
  /// already promises every mode with no lower area of its own.
  final Widget? agentPanel;

  /// How wide the properties panel is, in logical pixels — `ux-27`.
  ///
  /// Null keeps the fixed width the shell always had, which is what a caller
  /// with no settings behind it wants. A width outside the panel's own range
  /// is clamped rather than refused: the number arrives from a saved
  /// document and from a drag, and neither is a place to argue with.
  final double? propertiesWidth;

  /// A drag on the splitter, in logical pixels of the new width. Null draws
  /// no splitter at all.
  final ValueChanged<double>? onPropertiesWidth;

  /// Whether the properties panel is folded away, giving its width to the
  /// picture — `ux-27`'s own `N`.
  final bool foldedPanel;

  /// The same for the tool rail — `T`.
  final bool foldedRail;

  /// What the rail lists under its tools — `ux-23`'s own lights. Empty in
  /// every mode but Scene, which is the one mode whose whole subject is a
  /// short list of things and the one whose rail was empty.
  final List<RailEntry> railExtras;

  /// Which keys the rail's own tooltips should name — `ux-10`.
  ///
  /// Null falls back to `ModelerTool.shortcut`, which is what every caller
  /// that has no settings behind it wants: a preview shell, a test. A
  /// tooltip naming a key the live preset does not bind is worse than one
  /// naming none, so this is threaded rather than read from a global.
  final Keymap? keymap;

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
      // **A traversal group per region** — `ux-33`. Tab used to walk the
      // whole window in the order the widgets happen to be built in: the top
      // bar, then whichever rail button came first, then a field in the
      // panel, then back. Grouping them means Tab moves inside the region a
      // person is in and leaves it at the end, which is what "Tab moves
      // between regions" asks for and what every other application does.
      body: Column(
        children: <Widget>[
          FocusTraversalGroup(
            child: _TopBar(
              mode: mode,
              workspace: workspace,
              onMode: onMode,
              submode: submode,
              onSubmode: onSubmode,
              animationSubmode: animationSubmode,
              onAnimationSubmode: onAnimationSubmode,
              actions: actions,
              documentName: documentName,
              isDirty: isDirty,
            ),
          ),
          const Divider(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (!foldedRail) ...<Widget>[
                  FocusTraversalGroup(
                    child: _Rail(
                      mode: mode,
                      animationSubmode: animationSubmode,
                      active: activeTool,
                      onTool: onTool,
                      keymap: keymap,
                      extras: railExtras,
                    ),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                ],
                // The picture takes whatever is left, and takes it last: the
                // panels are the fixed things and the viewport is what a wider
                // window gives more of. `bottom`, when given, comes out of
                // this same column rather than the row: the rail and the
                // properties panel keep running the full height regardless,
                // per the handoff's own frame — only the viewport's own
                // column splits.
                Expanded(
                  child: bottom == null
                      ? ColoredBox(color: colours.viewport, child: viewport)
                      : Column(
                          children: <Widget>[
                            Expanded(
                              child: ColoredBox(
                                color: colours.viewport,
                                child: viewport,
                              ),
                            ),
                            const Divider(),
                            SizedBox(height: bottomHeight, child: bottom),
                          ],
                        ),
                ),
                if (!foldedPanel) ...<Widget>[
                  const VerticalDivider(width: 1, thickness: 1),
                  SizedBox(
                    width: (propertiesWidth ?? ModelerMetrics.propertiesMin)
                        .clamp(
                          ModelerMetrics.propertiesMin,
                          ModelerMetrics.propertiesWidest,
                        ),
                    // **A `Material`, not a `ColoredBox`** — `ux-08`. A
                    // `ListTile` asserts in a debug build when it cannot find
                    // a `Material` ancestor to paint its background and its
                    // ink splashes into, and the Scene panels are built out
                    // of `ListTile`/`SwitchListTile`. A `ColoredBox` paints
                    // the same colour and is not one, so entering Scene mode
                    // threw "ListTile background color or ink splashes may be
                    // invisible" on every frame — a crash dialog per frame
                    // over a black window, which Dismiss could not keep up
                    // with. A `Material` is the colour and the ancestor both.
                    child: Material(
                      // `ux-32`: the hand-off's own "панель свойств" is
                      // `surfaceContainer` — the lighter of the two panel
                      // tones, the same one the top bar uses. The rail and
                      // the status line keep `Low`.
                      color: theme.colorScheme.surfaceContainer,
                      // **The splitter lies over the panel's own left edge
                      // rather than between the two** — `ux-27`. A grab zone
                      // wide enough to hit, put in the row, is a gutter: six
                      // pixels the picture loses for good, and every
                      // screenshot in the tutorial moved by six pixels to
                      // pay for it. The panel's first few pixels are its
                      // padding and nothing is drawn there, so the zone
                      // costs nothing and the layout is the one it was.
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: FocusTraversalGroup(child: properties),
                          ),
                          if (onPropertiesWidth
                              case final ValueChanged<double> resize)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: 6,
                              child: _Splitter(
                                width:
                                    propertiesWidth ??
                                    ModelerMetrics.propertiesMin,
                                onWidth: resize,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (agentPanel case final Widget panel) ...<Widget>[
                  const VerticalDivider(width: 1, thickness: 1),
                  SizedBox(
                    width: ModelerMetrics.agentPanel,
                    child: ColoredBox(
                      // The agent panel is not in the hand-off's own table —
                      // nothing there had one — so it takes the tone of the
                      // panel it sits beside rather than a third answer.
                      color: theme.colorScheme.surfaceContainer,
                      child: FocusTraversalGroup(child: panel),
                    ),
                  ),
                ],
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.mode,
    required this.onMode,
    this.workspace = Workspace.full,
    required this.submode,
    required this.onSubmode,
    required this.animationSubmode,
    required this.onAnimationSubmode,
    required this.actions,
    required this.documentName,
    required this.isDirty,
  });

  final ModelerMode mode;
  final ValueChanged<ModelerMode> onMode;

  /// Which set of modes the switcher offers — `ux-37`. Full by default, so a
  /// caller that has not been told about workspaces shows what it always did.
  final Workspace workspace;

  final MeshSubmode submode;
  final ValueChanged<MeshSubmode> onSubmode;
  final AnimationSubmode animationSubmode;
  final ValueChanged<AnimationSubmode> onAnimationSubmode;
  final List<Widget> actions;
  final String documentName;
  final bool isDirty;

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
              // The design spec's own layout reads "filename | mode switcher
              // | undo redo Export" — a fixed-width label rather than
              // Flexible, so it never steals room the mode switcher's own
              // horizontal scroll already needs on a narrow window.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  documentLabel(documentName, isDirty: isDirty),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 12),
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
                  child: ModelerModeSwitcher(
                    workspace: workspace,
                    mode: mode,
                    onMode: onMode,
                    submode: submode,
                    onSubmode: onSubmode,
                    animationSubmode: animationSubmode,
                    onAnimationSubmode: onAnimationSubmode,
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
///
/// Public, and not `_Modes` any more: `ui-05`'s tablet and phone shells show
/// the same mode/submode switch this desktop one does, in `shell_tablet.dart`
/// and `shell_phone.dart`, and a private class in this file could not have
/// been their caller.
class ModelerModeSwitcher extends StatelessWidget {
  const ModelerModeSwitcher({
    super.key,
    required this.mode,
    required this.onMode,
    this.workspace = Workspace.full,
    required this.submode,
    required this.onSubmode,
    this.animationSubmode,
    this.onAnimationSubmode,
  });

  final ModelerMode mode;
  final ValueChanged<ModelerMode> onMode;

  /// Which set of modes the switcher offers — `ux-37`. Full by default, so a
  /// caller that has not been told about workspaces shows what it always did.
  final Workspace workspace;

  final MeshSubmode submode;
  final ValueChanged<MeshSubmode> onSubmode;

  /// `ui-40d`'s own second pair, [submode]'s counterpart for
  /// [ModelerMode.animation] — nullable rather than required so the tablet
  /// and phone shells, which do not yet reach the animation mode's own
  /// switcher, keep calling this constructor exactly as they did before this
  /// row. Left null (or [onAnimationSubmode] left null), the second segmented
  /// button simply does not show for [ModelerMode.animation] either, the same
  /// "nothing" every mode but mesh already answers with.
  final AnimationSubmode? animationSubmode;
  final ValueChanged<AnimationSubmode>? onAnimationSubmode;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      SegmentedButton<ModelerMode>(
        showSelectedIcon: false,
        segments: <ButtonSegment<ModelerMode>>[
          // **`ux-07`: a mode that is not ready is not on the bar at all.**
          // It used to be drawn and disabled, on the reasoning that what the
          // modeller is going to be should be visible from the first build
          // rather than arriving as a surprise. The live run cost that
          // reasoning its case: the switcher reads as eight unlabelled
          // icons, three of them look active, and pressing one of the three
          // does nothing a person can tell from a press that missed. A
          // roadmap belongs on the site, not in the one control a person
          // uses every minute.
          //
          // **`ux-37`: and a mode the open workspace does not offer is not on
          // it either.** Essential is Object, Material and Scene; a person who
          // came to open a model, paint it and export it should not have to
          // decide what Mesh mode is before doing any of that. Settings turns
          // the other two on, and `modesFor` is the one place that decides.
          for (final ModelerMode each in modesFor(workspace))
            ButtonSegment<ModelerMode>(
              value: each,
              // `ui-23`'s own pass: `tooltip:` below sets
              // `SemanticsNode.tooltip`, not `.label` — wrapping the icon
              // is what actually names the segment for a screen reader,
              // since `showSelectedIcon: false` above means there is no
              // visible `Text` label for its semantics to merge from.
              icon: Semantics(
                label: each.label,
                child: Icon(each.icon, size: 15),
              ),
              tooltip: each.label,
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
      // `ui-40d`'s own row: the handoff's own frame rule 2 gives the
      // current mode's sub-mode this same slot — mesh's is above, and
      // animation's four (pose/weights/retarget/morphs) are the only other
      // one built so far. [animationSubmode]/[onAnimationSubmode] are left
      // null by the shells that do not wire this mode's switcher yet
      // (`ModelerTabletShell`, `ModelerPhoneShell`), which is why both are
      // checked rather than just [mode].
      if (mode == ModelerMode.animation &&
          animationSubmode != null &&
          onAnimationSubmode != null)
        SegmentedButton<AnimationSubmode>(
          showSelectedIcon: false,
          segments: <ButtonSegment<AnimationSubmode>>[
            for (final AnimationSubmode each in AnimationSubmode.values)
              ButtonSegment<AnimationSubmode>(
                value: each,
                icon: Icon(each.icon, size: 15),
                label: Text(each.label),
              ),
          ],
          selected: <AnimationSubmode>{animationSubmode!},
          onSelectionChanged: (Set<AnimationSubmode> picked) =>
              onAnimationSubmode!(picked.first),
        ),
    ],
  );
}

/// `ux-27`'s own splitter: the panel's left edge, draggable.
///
/// **A grab zone over the edge rather than a handle in the row.** The
/// divider a hand already reaches for is one pixel wide, which is not
/// something anybody can hit; widening it in the layout would move the
/// picture and everything drawn in it. So the zone lies on top of the
/// panel's own first six pixels, where its padding is and nothing is drawn,
/// and the line stays where it was.
///
/// Nothing is painted here — the cursor over the edge is the whole of the
/// affordance, which is what a splitter looks like everywhere it is not
/// given a grip of its own.
class _Splitter extends StatelessWidget {
  const _Splitter({required this.width, required this.onWidth});

  /// What the panel is now — a drag reports this plus however far it went.
  final double width;

  final ValueChanged<double> onWidth;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeLeftRight,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Leftward is wider: the panel is on the right, so the hand and the
      // panel move the same way.
      onHorizontalDragUpdate: (DragUpdateDetails it) =>
          onWidth(width - it.delta.dx),
    ),
  );
}

/// One thing a rail lists that is not a tool — `ux-23`'s own lights.
///
/// **A record rather than a widget, so the rail goes on drawing every entry
/// the same way.** A slot the caller filled with a widget would be a second
/// answer to what a rail button looks like, and the first thing to drift
/// would be the armed colour.
typedef RailEntry = ({
  String label,
  IconData icon,
  bool armed,
  VoidCallback onPressed,
});

class _Rail extends StatelessWidget {
  const _Rail({
    required this.mode,
    required this.animationSubmode,
    required this.active,
    required this.onTool,
    this.keymap,
    this.extras = const <RailEntry>[],
  });

  /// Listed under the tools, after a divider — `ux-23`. The scene mode's own
  /// lights: every other mode's rail says what the mode has in it, and the
  /// one mode whose whole subject is a short list of things had an empty
  /// rail.
  final List<RailEntry> extras;

  final Keymap? keymap;

  final ModelerMode mode;

  /// `ui-40d`'s own row: which of the four animation tool lists `toolsFor`
  /// answers with, when [mode] is [ModelerMode.animation].
  final AnimationSubmode animationSubmode;
  final String? active;
  final ValueChanged<String> onTool;

  /// "Extrude · E", with the key from the live preset when there is one.
  ///
  /// A tool the preset gives no key at all gets its label alone rather than
  /// a dangling separator — `ux-10`'s own tool-key preset deliberately
  /// leaves some mesh operations where they were and moves only the four a
  /// hand rests on, so "no key here" is a real answer.
  /// The name and its key on the first line, what it does on the second —
  /// `ux-18`.
  ///
  /// **The name alone told somebody who already knew.** "Dissolve edges" and
  /// "Bake" are the two the review watched people press to find out what they
  /// were, and a tooltip that repeats the word on the button is a tooltip that
  /// answers nothing. `ModelerTool.about` is where the sentence lives, so the
  /// rail, the tablet palette and the command palette all read the same one.
  String _tooltipFor(BuildContext context, ModelerTool tool) {
    final ShortcutActivator key =
        keymap?.forTool(tool.id) ?? SingleActivator(tool.shortcut);
    return '${toolLabelIn(context, tool)}  ·  ${describeShortcut(key)}'
        '\n${toolAboutIn(context, tool)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tools = toolsFor(mode, animation: animationSubmode);
    // `ux-23`: the tools first, then whatever else the mode lists. One
    // builder over both, so an entry of either kind is the same button.
    final List<RailEntry> rows = <RailEntry>[
      for (final ModelerTool tool in tools)
        (
          label: toolLabelIn(context, tool),
          icon: tool.icon,
          armed: tool.id == active,
          onPressed: () => onTool(tool.id),
        ),
      ...extras,
    ];
    return SizedBox(
      width: ModelerMetrics.rail,
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerLow,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: rows.length,
          itemBuilder: (BuildContext context, int index) {
            final RailEntry row = rows[index];
            final bool isTool = index < tools.length;
            final startsGroup = isTool
                ? index > 0 && tools[index - 1].group != tools[index].group
                : index == tools.length && tools.isNotEmpty;
            final armed = row.armed;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (startsGroup)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Divider(height: 1),
                  ),
                // `ui-23`'s own pass: `Tooltip.message` lands in
                // `SemanticsNode.tooltip`, not `.label` — the field
                // `labeledTapTargetGuideline` and most screen readers
                // actually read. `MergeSemantics` folds the label down onto
                // `IconButton`'s own inner node, the one that actually
                // carries the tap action; an outer `Semantics` alone would
                // sit beside it as a second, still-unlabelled node.
                MergeSemantics(
                  child: Semantics(
                    label: row.label,
                    button: true,
                    child: Tooltip(
                      message: isTool
                          ? _tooltipFor(context, tools[index])
                          : row.label,
                      child: IconButton(
                        onPressed: row.onPressed,
                        icon: Icon(row.icon, size: 18),
                        // The design's own "кнопка 40 × 36, радиус 10" — the
                        // one button this app widens past the ambient
                        // `iconButtonTheme`'s square 36 (`theme.dart`'s own
                        // doc note on `ModelerMetrics.railButtonWidth` says
                        // why that stays app-wide rather than moving here).
                        style: IconButton.styleFrom(
                          minimumSize: const Size(
                            ModelerMetrics.railButtonWidth,
                            ModelerMetrics.railButtonHeight,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              ModelerMetrics.railButtonRadius,
                            ),
                          ),
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
