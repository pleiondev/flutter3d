/// The outliner: every piece of the level as a row, the selection shown
/// from the document and written back to it, more than one row selected,
/// a filter, a heading folded, and a double-click that flies there.
///
///     flutter test test/outliner_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/editor_theme.dart';
import 'package:flutter3d_editor/src/outliner.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_cubit_helpers.dart';

/// The outliner over [editing], selecting the way the editor's screen does:
/// through `Editing` itself, then rebuilding.
final class _Host extends StatefulWidget {
  const _Host(this.editing, {this.adding = false, this.held, this.framed});

  final Editing editing;
  final bool adding;

  /// Whether ⌘ is down, asked at the moment the outliner asks; overrides
  /// [adding] when given.
  final bool Function()? held;
  final List<Picked>? framed;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: editorTheme(),
    home: Scaffold(
      body: Outliner(
        editing: widget.editing,
        adding: widget.held ?? () => widget.adding,
        onSelect: (Picked picked, {required bool add}) => setState(() {
          if (add) {
            widget.editing.toggle(picked.kind, picked.index);
          } else {
            widget.editing.select(picked.kind, picked.index);
          }
        }),
        onFrame: widget.framed?.add,
      ),
    ),
  );
}

Finder _row(Piece kind, int index) =>
    find.byKey(ValueKey<String>('outliner.${kind.name}.$index'));

/// The colour behind a row, which is how it says it is selected.
Color? _shade(WidgetTester tester, Piece kind, int index) => tester
    .widget<Container>(
      find.descendant(of: _row(kind, index), matching: find.byType(Container)),
    )
    .color;

/// Waits out the double-tap window, after which a single tap counts.
Future<void> _tap(WidgetTester tester, Finder row) async {
  await tester.tap(row);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('lists every brush under its heading', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_Host(openTestDocument()));

    expect(find.text('Brushes'), findsOneWidget);
    expect(_row(Piece.brush, 0), findsOneWidget);
    expect(_row(Piece.brush, 1), findsOneWidget);
  });

  testWidgets('a selection made elsewhere shows on its row', (
    WidgetTester tester,
  ) async {
    // The viewport selects by calling `Editing.select`; the outliner must
    // show it with nobody telling it.
    //
    // Mutation: compute `selected:` as `false` in the outliner's rows.
    // Neither row is ever shaded.
    final editing = openTestDocument();
    await tester.pumpWidget(_Host(editing));
    expect(_shade(tester, Piece.brush, 1), isNull);

    editing.select(Piece.brush, 1);
    tester.state<_HostState>(find.byType(_Host)).refresh();
    await tester.pump();

    expect(_shade(tester, Piece.brush, 1), isNotNull);
    expect(_shade(tester, Piece.brush, 0), isNull);
  });

  testWidgets('a row clicked selects it in the document', (
    WidgetTester tester,
  ) async {
    // Mutation: drop the `onTap` on the outliner's row. Nothing is
    // selected.
    final editing = openTestDocument();
    await tester.pumpWidget(_Host(editing));

    await _tap(tester, _row(Piece.brush, 1));

    expect(editing.selection, <Picked>[(kind: Piece.brush, index: 1)]);
    expect(_shade(tester, Piece.brush, 1), isNotNull);
  });

  testWidgets('and a command-click adds to it', (WidgetTester tester) async {
    // Mutation: pass `add: false` from the row whatever `adding` says. The
    // second click replaces the first and only brush 1 is selected.
    final editing = openTestDocument()..select(Piece.brush, 0);
    await tester.pumpWidget(_Host(editing, adding: true));

    await _tap(tester, _row(Piece.brush, 1));

    expect(editing.selection, hasLength(2));
    expect(find.text('2 selected · ⌘-click to add or remove'), findsOneWidget);
    // The primary is drawn heavier than the other.
    expect(
      _shade(tester, Piece.brush, 0),
      isNot(_shade(tester, Piece.brush, 1)),
    );
  });

  testWidgets('⌘ counts when the row is pressed, not when the tap lands', (
    WidgetTester tester,
  ) async {
    // A row that also answers a double-click hears of a single click a
    // third of a second late. Found driving the built editor: ⌘ let go in
    // that time, and the second row replaced the first.
    //
    // Mutation: pass `_adding()` from `onTap` instead of `_addOnTap`. ⌘ is
    // up by then and only brush 1 is selected.
    var down = true;
    final editing = openTestDocument()..select(Piece.brush, 0);
    // With somewhere to fly to, as in the editor: that is what makes a
    // single click wait.
    await tester.pumpWidget(
      _Host(editing, held: () => down, framed: <Picked>[]),
    );

    final press = await tester.startGesture(
      tester.getCenter(_row(Piece.brush, 1)),
    );
    await press.up();
    down = false;
    await tester.pump(const Duration(milliseconds: 400));

    expect(editing.selection, hasLength(2));
  });

  testWidgets('the filter keeps the rows that match', (
    WidgetTester tester,
  ) async {
    // Mutation: build the rows from `outlineOf(editing.level)` without the
    // filter. Both brushes stay.
    await tester.pumpWidget(_Host(openTestDocument()));

    await tester.enterText(
      find.byKey(const ValueKey<String>('outliner.filter')),
      'brush 1',
    );
    await tester.pump();

    expect(_row(Piece.brush, 0), findsNothing);
    expect(_row(Piece.brush, 1), findsOneWidget);
  });

  testWidgets('a heading folds its rows away and back', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_Host(openTestDocument()));

    await tester.tap(
      find.byKey(const ValueKey<String>('outliner.group.Brushes')),
    );
    await tester.pump();
    expect(_row(Piece.brush, 0), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('outliner.group.Brushes')),
    );
    await tester.pump();
    expect(_row(Piece.brush, 0), findsOneWidget);
  });

  testWidgets('a double-click asks to fly there', (WidgetTester tester) async {
    // Mutation: drop `onDoubleTap` from the row. Nothing is asked for.
    final framed = <Picked>[];
    await tester.pumpWidget(_Host(openTestDocument(), framed: framed));

    await tester.tap(_row(Piece.brush, 1));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_row(Piece.brush, 1));
    await tester.pumpAndSettle();

    expect(framed, <Picked>[(kind: Piece.brush, index: 1)]);
  });
}
