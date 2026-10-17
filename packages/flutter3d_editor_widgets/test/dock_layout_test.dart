/// `DockLayout` and the `DockArrangement` it is driven by: panels as tabs on
/// a side, a side folded to a strip and opened again, a side dragged wider,
/// a panel moved to another side, the picture kept in place through all of
/// it, and the arrangement read back from what it wrote.
///
///     flutter test test/dock_layout_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final List<DockPanel> _panels = <DockPanel>[
  DockPanel(
    id: 'outliner',
    title: 'Outliner',
    icon: Icons.account_tree,
    side: DockSide.left,
    builder: (_) => const Text('outliner body'),
  ),
  DockPanel(
    id: 'inspector',
    title: 'Inspector',
    icon: Icons.tune,
    side: DockSide.right,
    builder: (_) => const Text('inspector body'),
  ),
  DockPanel(
    id: 'materials',
    title: 'Materials',
    icon: Icons.palette,
    side: DockSide.right,
    builder: (_) => const Text('materials body'),
  ),
  DockPanel(
    id: 'console',
    title: 'Console',
    icon: Icons.terminal,
    side: DockSide.bottom,
    builder: (_) => const Text('console body'),
  ),
];

/// The layout with its arrangement held the way a caller holds it, and the
/// last arrangement it was handed back.
final class _Host extends StatefulWidget {
  const _Host({this.start = const DockArrangement(), this.center});

  final DockArrangement start;
  final Widget? center;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late DockArrangement arrangement = widget.start;

  /// What a caller does when its stored layout changes from elsewhere.
  void arrange(DockArrangement next) => setState(() => arrangement = next);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: DockLayout(
        center: widget.center ?? const Text('the picture'),
        panels: _panels,
        arrangement: arrangement,
        onChanged: (DockArrangement next) => setState(() => arrangement = next),
      ),
    ),
  );
}

DockArrangement _arrangement(WidgetTester tester) =>
    tester.state<_HostState>(find.byType(_Host)).arrangement;

/// A picture that counts how many times it has been made, so a test can say
/// it was not torn down.
final class _Counted extends StatefulWidget {
  const _Counted();

  static int made = 0;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    _Counted.made++;
  }

  @override
  Widget build(BuildContext context) => const Text('the picture');
}

void main() {
  setUp(() => _Counted.made = 0);

  testWidgets('each side shows its first panel, with the rest as tabs', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const _Host());

    expect(find.text('the picture'), findsOneWidget);
    expect(find.text('outliner body'), findsOneWidget);
    expect(find.text('inspector body'), findsOneWidget);
    expect(find.text('console body'), findsOneWidget);
    // A second panel on the right is a tab, not a second body.
    expect(find.text('materials body'), findsNothing);
    expect(find.byKey(const ValueKey<String>('dock.tab.materials')), findsOne);
  });

  testWidgets('a tab shows its panel in place of the other', (
    WidgetTester tester,
  ) async {
    // Mutation: have `_Tab` ignore `onTap`. The inspector stays on screen
    // and the materials body never appears.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const _Host());

    await tester.tap(find.byKey(const ValueKey<String>('dock.tab.materials')));
    await tester.pump();

    expect(find.text('materials body'), findsOneWidget);
    expect(find.text('inspector body'), findsNothing);
    expect(_arrangement(tester).active[DockSide.right], 'materials');
  });

  testWidgets('a side folds to a strip of icons and opens on the one hit', (
    WidgetTester tester,
  ) async {
    // Mutation: make `_Strip`'s buttons call `withCollapsed(side, true)`
    // instead of `shown`. The strip stays a strip and nothing opens.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const _Host());

    await tester.tap(find.byKey(const ValueKey<String>('dock.collapse.right')));
    await tester.pump();
    expect(find.text('inspector body'), findsNothing);
    expect(find.byKey(const ValueKey<String>('dock.grip.right')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('dock.strip.materials')),
    );
    await tester.pump();
    expect(find.text('materials body'), findsOneWidget);
    expect(_arrangement(tester).isCollapsed(DockSide.right), isFalse);
  });

  testWidgets('dragging a grip toward the picture widens the side', (
    WidgetTester tester,
  ) async {
    // Mutation: make `DockSide.right.growsWith` one rather than minus one.
    // Dragging left then narrows the inspector instead.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const _Host());
    final before = tester
        .getSize(find.byKey(const ValueKey<String>('dock.panel.inspector')))
        .width;

    await tester.drag(
      find.byKey(const ValueKey<String>('dock.grip.right')),
      const Offset(-60, 0),
    );
    await tester.pump();

    final after = tester
        .getSize(find.byKey(const ValueKey<String>('dock.panel.inspector')))
        .width;
    expect(before, 280);
    expect(after, greaterThan(before + 30));
    expect(_arrangement(tester).sizeOf(DockSide.right), after);
  });

  testWidgets('no side can be dragged past most of the window', (
    WidgetTester tester,
  ) async {
    // Mutation: return the stored size from `limit` without the `share`
    // cap. The left column is drawn 2000 wide and the picture is pushed off.
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _Host(start: const DockArrangement().withSize(DockSide.left, 2000)),
    );

    final width = tester
        .getSize(find.byKey(const ValueKey<String>('dock.panel.outliner')))
        .width;
    expect(width, 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a panel moved to another side is shown there', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const _Host());

    await tester.tap(find.byKey(const ValueKey<String>('dock.move.right')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('dock.moveTo.left')));
    await tester.pumpAndSettle();

    // On the left, as its showing tab; gone from the right, where the
    // materials panel is now the one shown.
    final moved = _arrangement(tester);
    final inspector = _panels[1];
    expect(moved.sideOf(inspector), DockSide.left);
    expect(moved.isShowing(inspector, _panels), isTrue);
    expect(find.text('inspector body'), findsOneWidget);
    expect(find.text('materials body'), findsOneWidget);
    expect(find.text('outliner body'), findsNothing);
    expect(
      tester.getCenter(find.text('inspector body')).dx,
      lessThan(tester.getCenter(find.text('the picture')).dx),
    );
  });

  testWidgets('the picture is not rebuilt from scratch as panels change', (
    WidgetTester tester,
  ) async {
    // A 3D view holds a renderer; tearing it down because a side folded
    // would be a black frame and a lost GPU state each time.
    //
    // Both sides fold at once: Flutter matches a row's unkeyed children from
    // either end, so one side changing alone would be survived by luck.
    //
    // Mutation: take the key off the row's middle `Expanded`. Folding both
    // sides changes a grip into an empty box at each end, the middle is
    // matched from neither, and the picture is made a second time.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const _Host(center: _Counted()));

    final host = tester.state<_HostState>(find.byType(_Host));
    host.arrange(
      host.arrangement
          .withCollapsed(DockSide.left, folded: true)
          .withCollapsed(DockSide.right, folded: true),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('dock.collapse.bottom')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('dock.strip.outliner')));
    await tester.pump();

    expect(find.text('the picture'), findsOneWidget);
    expect(_Counted.made, 1);
  });

  group('the arrangement as data', () {
    test('reads back what it wrote', () {
      // Mutation: write `collapsed` as an empty list in `toJson`. The left
      // side comes back open.
      final panel = _panels[1];
      final written = const DockArrangement()
          .withSize(DockSide.bottom, 310)
          .withCollapsed(DockSide.left, folded: true)
          .movedTo(panel, DockSide.bottom);

      final read = DockArrangement.fromJson(written.toJson());

      expect(read.sizeOf(DockSide.bottom), 310);
      expect(read.isCollapsed(DockSide.left), isTrue);
      expect(read.sideOf(panel), DockSide.bottom);
      expect(read.active[DockSide.bottom], 'inspector');
    });

    test('and keeps what it can of a file it half understands', () {
      // A layout file is read on every launch and nobody looks after it.
      //
      // Mutation: cast `json['sizes']` to a map without checking. A file
      // with a list there throws instead of opening at the defaults.
      final read = DockArrangement.fromJson(<String, Object?>{
        'sizes': <Object?>[1, 2],
        'collapsed': <Object?>['left', 'sideways', 4],
        'moved': <String, Object?>{'inspector': 'up'},
      });

      expect(read.sizeOf(DockSide.left), 240);
      expect(read.collapsed, <DockSide>{DockSide.left});
      expect(read.moved, isEmpty);
      expect(DockArrangement.fromJson('not a map').collapsed, isEmpty);
    });

    test('a panel moved home again is no longer remembered as moved', () {
      final panel = _panels[0];
      final back = const DockArrangement()
          .movedTo(panel, DockSide.right)
          .movedTo(panel, DockSide.left);

      expect(back.moved, isEmpty);
    });
  });
}
