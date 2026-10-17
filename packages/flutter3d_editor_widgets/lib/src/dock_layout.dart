/// Panels docked around a picture: a column down each side and a strip
/// along the bottom, each resizable by its edge, collapsible to a row of
/// icons, and holding its panels as tabs.
///
/// **An editor's panels used to be a `Stack` over the picture.** Every panel
/// was `Positioned` on top of the level, so each one hid part of what was
/// being edited, two of them could not be open on the same side without one
/// pushing the other off the screen, and a panel's width was whatever its
/// author had typed. Docked, a panel takes its room from the picture rather
/// than covering it, and the room is the person's to choose.
///
/// **Controlled, not stateful.** What is where, how wide and what is folded
/// away is a [DockArrangement] the caller holds and is handed back changed
/// through [DockLayout.onChanged]; the caller decides whether and where it is
/// kept, which for an editor is per person, between launches. The
/// arrangement is plain data with a JSON form, so it is tested without a
/// window and read back tolerantly — a file from an older build, with a
/// panel that no longer exists, loses that panel and nothing else.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Where a panel is docked.
///
/// **A class of three constants rather than an enum**, so a fourth side —
/// along the top — can be added without breaking a `switch` somebody wrote
/// against the first three. What differs between the sides is carried here
/// as data rather than decided in switches over them.
final class DockSide {
  const DockSide._(
    this.name, {
    required this.vertical,
    required this.growsWith,
    required this.foldIcon,
  });

  /// What it is written down as in a stored arrangement.
  final String name;

  /// Whether the side is a column down the window rather than a strip
  /// across it — which way it is sized, and which way its grip drags.
  final bool vertical;

  /// Which way a drag of its grip widens it: one when toward the right or
  /// down, minus one when toward the left or up. Toward the picture, always.
  /// A unitless sign, multiplied into the drag's pixels.
  final double growsWith;

  /// The arrow its fold button shows, pointing where it folds to.
  final IconData foldIcon;

  static const DockSide left = DockSide._(
    'left',
    vertical: true,
    growsWith: 1.0,
    foldIcon: Icons.chevron_left,
  );
  static const DockSide right = DockSide._(
    'right',
    vertical: true,
    growsWith: -1.0,
    foldIcon: Icons.chevron_right,
  );
  static const DockSide bottom = DockSide._(
    'bottom',
    vertical: false,
    growsWith: -1.0,
    foldIcon: Icons.expand_more,
  );

  static const List<DockSide> values = <DockSide>[left, right, bottom];

  @override
  String toString() => 'DockSide.$name';
}

/// One panel: what it is called, its icon, where it docks unless moved, and
/// what it shows.
final class DockPanel {
  const DockPanel({
    required this.id,
    required this.title,
    required this.icon,
    required this.side,
    required this.builder,
  });

  /// Stable across launches: what an arrangement remembers it by.
  final String id;
  final String title;
  final IconData icon;

  /// Where it docks until somebody moves it.
  final DockSide side;
  final WidgetBuilder builder;
}

/// What is where: each side's size, which sides are folded away, which tab
/// each side shows, and the panels moved off their own side.
final class DockArrangement {
  const DockArrangement({
    this.sizes = const <DockSide, double>{},
    this.collapsed = const <DockSide>{},
    this.active = const <DockSide, String>{},
    this.moved = const <String, DockSide>{},
  });

  /// The size a side has until it is dragged: a column wide enough for a
  /// field's name and its value, a strip tall enough for a dozen lines.
  static const Map<DockSide, double> defaultSizes = <DockSide, double>{
    DockSide.left: 240.0,
    DockSide.right: 280.0,
    DockSide.bottom: 200.0,
  };

  /// The smallest a side can be dragged to. Below this a panel's rows stop
  /// being readable, and folding it away is what somebody means. In logical
  /// pixels.
  static const double minimumSize = 120.0;

  final Map<DockSide, double> sizes;
  final Set<DockSide> collapsed;
  final Map<DockSide, String> active;
  final Map<String, DockSide> moved;

  double sizeOf(DockSide side) => sizes[side] ?? defaultSizes[side]!;

  bool isCollapsed(DockSide side) => collapsed.contains(side);

  DockSide sideOf(DockPanel panel) => moved[panel.id] ?? panel.side;

  /// [side] at [size], no smaller than [minimumSize].
  DockArrangement withSize(DockSide side, double size) => _copy(
    sizes: <DockSide, double>{...sizes, side: math.max(minimumSize, size)},
  );

  /// [side] folded away, or opened out again.
  DockArrangement withCollapsed(DockSide side, {required bool folded}) => _copy(
    collapsed: <DockSide>{
      for (final it in collapsed)
        if (it != side) it,
      if (folded) side,
    },
  );

  /// [panel] on screen: its side opened out and its tab the one shown —
  /// what a toolbar button or a command for a panel means.
  DockArrangement shown(DockPanel panel) {
    final side = sideOf(panel);
    return withCollapsed(
      side,
      folded: false,
    )._copy(active: <DockSide, String>{...active, side: panel.id});
  }

  /// [panel] moved to [side], and shown there.
  DockArrangement movedTo(DockPanel panel, DockSide side) => _copy(
    moved: <String, DockSide>{
      for (final entry in moved.entries)
        if (entry.key != panel.id) entry.key: entry.value,
      if (side != panel.side) panel.id: side,
    },
  ).shown(panel);

  /// Whether [panel] is the tab its side shows, with the side open.
  bool isShowing(DockPanel panel, List<DockPanel> all) {
    final side = sideOf(panel);
    return !isCollapsed(side) && activeOn(side, all)?.id == panel.id;
  }

  /// The panel [side] shows: the one last chosen there, or the first panel
  /// docked there when that one has gone elsewhere or never was.
  DockPanel? activeOn(DockSide side, List<DockPanel> all) {
    final here = <DockPanel>[
      for (final panel in all)
        if (sideOf(panel) == side) panel,
    ];
    if (here.isEmpty) return null;
    final chosen = active[side];
    return here.firstWhere(
      (DockPanel panel) => panel.id == chosen,
      orElse: () => here.first,
    );
  }

  DockArrangement _copy({
    Map<DockSide, double>? sizes,
    Set<DockSide>? collapsed,
    Map<DockSide, String>? active,
    Map<String, DockSide>? moved,
  }) => DockArrangement(
    sizes: sizes ?? this.sizes,
    collapsed: collapsed ?? this.collapsed,
    active: active ?? this.active,
    moved: moved ?? this.moved,
  );

  /// The stored arrangement's version, in the envelope every flutter3d
  /// document carries (`"format": "f3d.dock-layout"`). A file without it is
  /// version 1; a newer one is read as the default layout, never misread.
  static const int formatVersion = 1;

  Map<String, Object?> toJson() => <String, Object?>{
    'format': 'f3d.dock-layout',
    'version': formatVersion,
    'requires': const <String>[],
    'generator': 'flutter3d',
    'sizes': <String, double>{
      for (final entry in sizes.entries) entry.key.name: entry.value,
    },
    'collapsed': <String>[for (final side in collapsed) side.name],
    'active': <String, String>{
      for (final entry in active.entries) entry.key.name: entry.value,
    },
    'moved': <String, String>{
      for (final entry in moved.entries) entry.key: entry.value.name,
    },
  };

  /// Reads what [toJson] wrote, keeping what it can.
  ///
  /// **Never throws.** This is read on every launch from a file nobody looks
  /// at, and an editor that would not open because a convenience file lost a
  /// brace would be trading the work for the layout. A side it does not know,
  /// a size that is not a number, a whole document that is not a map: each
  /// is dropped, and what is left is used.
  static DockArrangement fromJson(Object? json) {
    if (json is! Map) return const DockArrangement();
    final format = json['format'];
    final version = json['version'];
    if ((format != null && format != 'f3d.dock-layout') ||
        (version is num && version > formatVersion)) {
      return const DockArrangement();
    }
    DockSide? side(Object? name) =>
        DockSide.values.where((DockSide it) => it.name == name).firstOrNull;
    final sizes = json['sizes'];
    final collapsed = json['collapsed'];
    final active = json['active'];
    final moved = json['moved'];
    return DockArrangement(
      sizes: <DockSide, double>{
        if (sizes is Map)
          for (final entry in sizes.entries)
            if ((side(entry.key), entry.value) case (
              final DockSide at,
              final num size,
            ))
              at: math.max(minimumSize, size.toDouble()),
      },
      collapsed: <DockSide>{
        if (collapsed is List)
          for (final name in collapsed) ?side(name),
      },
      active: <DockSide, String>{
        if (active is Map)
          for (final entry in active.entries)
            if ((side(entry.key), entry.value) case (
              final DockSide at,
              final String id,
            ))
              at: id,
      },
      moved: <String, DockSide>{
        if (moved is Map)
          for (final entry in moved.entries)
            if ((entry.key, side(entry.value)) case (
              final String id,
              final DockSide at,
            ))
              id: at,
      },
    );
  }
}

/// [center] with [panels] docked around it as [arrangement] says.
///
/// **The picture keeps its place in the tree whatever the panels do.**
/// Folding a side away, opening the bottom strip or moving a tab changes
/// what is around [center] and never where it is, so a stateful picture —
/// a 3D view holding a renderer — is not torn down and rebuilt because
/// somebody tidied a panel.
final class DockLayout extends StatelessWidget {
  const DockLayout({
    super.key,
    required this.center,
    required this.panels,
    required this.arrangement,
    required this.onChanged,
  });

  final Widget center;
  final List<DockPanel> panels;
  final DockArrangement arrangement;
  final ValueChanged<DockArrangement> onChanged;

  /// How wide a folded side is: one icon per panel, and room to hit it. In
  /// logical pixels.
  static const double strip = 32.0;

  /// The grip between a side and the picture, in logical pixels.
  static const double grip = 5.0;

  /// The most of the window [side] may take: a column three tenths of the
  /// width, the strip two fifths of the height.
  static double share(DockSide side) => side.vertical ? 0.3 : 0.4;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      // A side may take at most [share] of the window, so no drag can push
      // the picture off the screen — two columns at most three tenths each
      // leave it two fifths of the width, the strip at most two fifths of
      // the height. The stored sizes are clamped here rather than rewritten,
      // so a window made smaller for a minute gives the person back their
      // layout when it grows again.
      double limit(DockSide side, double extent) => math.max(
        DockArrangement.minimumSize,
        math.min(arrangement.sizeOf(side), extent * share(side)),
      );
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;

      Widget side(DockSide at) {
        final here = <DockPanel>[
          for (final panel in panels)
            if (arrangement.sideOf(panel) == at) panel,
        ];
        if (here.isEmpty) return const SizedBox.shrink();
        final vertical = at.vertical;
        if (arrangement.isCollapsed(at)) {
          return SizedBox(
            width: vertical ? strip : null,
            height: vertical ? null : strip,
            child: _Strip(
              side: at,
              panels: here,
              onShow: (DockPanel panel) => onChanged(arrangement.shown(panel)),
            ),
          );
        }
        final size = limit(at, vertical ? width : height);
        return SizedBox(
          width: vertical ? size : null,
          height: vertical ? null : size,
          child: _Region(
            side: at,
            panels: here,
            showing: arrangement.activeOn(at, panels)!,
            onShow: (DockPanel panel) => onChanged(arrangement.shown(panel)),
            onCollapse: () =>
                onChanged(arrangement.withCollapsed(at, folded: true)),
            onMove: (DockPanel panel, DockSide to) =>
                onChanged(arrangement.movedTo(panel, to)),
          ),
        );
      }

      // A grip only beside a side that is open: a folded side has no edge
      // to drag, and a grip there would be a sliver of nothing to hit.
      Widget gripFor(DockSide at) {
        final open =
            !arrangement.isCollapsed(at) &&
            panels.any((DockPanel panel) => arrangement.sideOf(panel) == at);
        if (!open) return const SizedBox.shrink();
        final vertical = at.vertical;
        return _Grip(
          key: ValueKey<String>('dock.grip.${at.name}'),
          vertical: vertical,
          onDrag: (double by) {
            // Dragging toward the picture widens the side, whichever side
            // it is on.
            final now = limit(at, vertical ? width : height);
            onChanged(arrangement.withSize(at, now + by * at.growsWith));
          },
        );
      }

      // **The middle is keyed, and that is what keeps the picture.** Flutter
      // matches a row's unkeyed children by walking in from both ends until
      // the types disagree; folding both sides at once turns a grip into an
      // empty box at each end, both walks stop there, and an unkeyed middle
      // would be made again with the picture inside it. A key is matched
      // wherever it lands. The column below holds the picture first, where
      // the walk from the top always reaches it.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          side(DockSide.left),
          gripFor(DockSide.left),
          Expanded(
            key: const ValueKey<String>('dock.middle'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey<String>('dock.center'),
                    child: center,
                  ),
                ),
                gripFor(DockSide.bottom),
                side(DockSide.bottom),
              ],
            ),
          ),
          gripFor(DockSide.right),
          side(DockSide.right),
        ],
      );
    },
  );
}

/// One open side: its tabs along the top, and the panel shown.
final class _Region extends StatelessWidget {
  const _Region({
    required this.side,
    required this.panels,
    required this.showing,
    required this.onShow,
    required this.onCollapse,
    required this.onMove,
  });

  final DockSide side;
  final List<DockPanel> panels;
  final DockPanel showing;
  final ValueChanged<DockPanel> onShow;
  final VoidCallback onCollapse;
  final void Function(DockPanel panel, DockSide to) onMove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: 30,
            color: scheme.surfaceContainerHighest,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (final panel in panels)
                          _Tab(
                            panel: panel,
                            selected: panel.id == showing.id,
                            onTap: () => onShow(panel),
                          ),
                      ],
                    ),
                  ),
                ),
                // Moving a panel is something done once and kept, so it is a
                // menu rather than a drag: a tab that moved when somebody
                // only meant to click it would be a layout that rearranges
                // itself under their hand.
                PopupMenuButton<DockSide>(
                  key: ValueKey<String>('dock.move.${side.name}'),
                  tooltip: 'Move ${showing.title}',
                  // A child of a fixed size rather than an icon, which would
                  // bring a 48-pixel tap target into a 30-pixel strip and
                  // push the tabs off a narrow side.
                  child: SizedBox(
                    width: 26,
                    height: 30,
                    child: Icon(
                      Icons.more_vert,
                      color: scheme.onSurfaceVariant,
                      size: 16,
                    ),
                  ),
                  onSelected: (DockSide to) => onMove(showing, to),
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<DockSide>>[
                        for (final to in DockSide.values)
                          if (to != side)
                            PopupMenuItem<DockSide>(
                              key: ValueKey<String>('dock.moveTo.${to.name}'),
                              value: to,
                              child: Text(
                                'Move ${showing.title} to the ${to.name}',
                              ),
                            ),
                      ],
                ),
                Tooltip(
                  message: 'Fold this side away',
                  child: InkWell(
                    key: ValueKey<String>('dock.collapse.${side.name}'),
                    onTap: onCollapse,
                    child: SizedBox(
                      width: 26,
                      height: 30,
                      child: Icon(
                        side.foldIcon,
                        color: scheme.onSurfaceVariant,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey<String>('dock.panel.${showing.id}'),
              child: Builder(builder: showing.builder),
            ),
          ),
        ],
      ),
    );
  }
}

final class _Tab extends StatelessWidget {
  const _Tab({
    required this.panel,
    required this.selected,
    required this.onTap,
  });

  final DockPanel panel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return InkWell(
      key: ValueKey<String>('dock.tab.${panel.id}'),
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(panel.icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(panel.title, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// A folded side: an icon per panel, any of which opens it out on that tab.
final class _Strip extends StatelessWidget {
  const _Strip({
    required this.side,
    required this.panels,
    required this.onShow,
  });

  final DockSide side;
  final List<DockPanel> panels;
  final ValueChanged<DockPanel> onShow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final buttons = <Widget>[
      for (final panel in panels)
        IconButton(
          key: ValueKey<String>('dock.strip.${panel.id}'),
          tooltip: panel.title,
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          icon: Icon(panel.icon, color: scheme.onSurfaceVariant),
          onPressed: () => onShow(panel),
        ),
    ];
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: side.vertical ? Column(children: buttons) : Row(children: buttons),
    );
  }
}

/// The edge a side is resized by.
final class _Grip extends StatelessWidget {
  const _Grip({super.key, required this.vertical, required this.onDrag});

  final bool vertical;

  /// How far the pointer moved across the grip, in logical pixels.
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: vertical
        ? SystemMouseCursors.resizeColumn
        : SystemMouseCursors.resizeRow,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: vertical
          ? (DragUpdateDetails it) => onDrag(it.delta.dx)
          : null,
      onVerticalDragUpdate: vertical
          ? null
          : (DragUpdateDetails it) => onDrag(it.delta.dy),
      child: SizedBox(
        width: vertical ? DockLayout.grip : null,
        height: vertical ? null : DockLayout.grip,
        child: ColoredBox(color: Theme.of(context).colorScheme.outline),
      ),
    ),
  );
}
