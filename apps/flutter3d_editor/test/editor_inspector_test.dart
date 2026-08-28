/// The panel that made most of the level format authorable.
///
///     flutter test test/editor_inspector_test.dart
///
/// **The editor could move things and could not change what they were.** It
/// nudged any of the three kinds, resized a brush, brightened a light and
/// turned an entity — and had no way to touch a brush's material, `solid`,
/// `castsShadow`, `layer` or `ramp`, a light's colour, range or type, or an
/// entity's properties. One-way platforms, non-solid decoration and per-brush
/// physics surfaces are what the level format's own documentation calls its
/// point, and none of them could be authored in the editor that exists to
/// author them.
///
/// The panel is built from the document, so what these tests assert is that
/// shape rather than a list of fields: a row per key, an editor chosen by the
/// value that is there, and a field this build has never heard of shown rather
/// than dropped.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/editing.dart';
import 'package:flutter3d_editor/src/editor_inspector.dart';
import 'package:flutter3d_editor/src/editor_state.dart';
import 'package:flutter3d_editor/src/gizmos.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_cubit_helpers.dart';

/// The panel over a document with something selected.
Widget _inspector(Editing editing, {void Function(String)? onChanged}) =>
    MaterialApp(
      home: Scaffold(
        body: EditorInspector(
          state: EditorReady(
            editing: editing,
            assetRoot: null,
            looks: noLooks,
            said: '',
          ),
          onChanged: onChanged ?? (String _) {},
        ),
      ),
    );

/// The control inside the row named [name].
///
/// By its row rather than by type: the panel shows every field a piece has and
/// every one the format would add, so `byType` finds several of anything.
/// Keyed rather than found by layout: every row carries `field:<name>`, so a
/// test names the field it means instead of counting Paddings — which is what
/// the first version of this did, and it matched an ancestor holding every
/// row at once.
Finder _in(String name, Type control) => find.descendant(
  of: find.byKey(ValueKey<String>('field:$name')),
  matching: find.byType(control),
);

void main() {
  testWidgets('shows nothing at all when nothing is selected', (
    WidgetTester tester,
  ) async {
    // A panel with nothing in it narrows the picture, which is the one thing
    // an editor's window is for.
    await tester.pumpWidget(_inspector(openTestDocument()));

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('shows a row for every field the document holds', (
    WidgetTester tester,
  ) async {
    // From the row, not from a list of fields this file knows about — which is
    // why `size` appears without anybody naming it here.
    final editing = openTestDocument()..select(Piece.brush, 0);

    await tester.pumpWidget(_inspector(editing));

    expect(find.text('material'), findsOneWidget);
    expect(find.text('at'), findsOneWidget);
    expect(find.text('size'), findsOneWidget);
  });

  testWidgets('and a field this build has never heard of is shown too', (
    WidgetTester tester,
  ) async {
    // `Level` writes through what it does not understand, and an inspector
    // built from a hand-written list of fields would drop exactly that —
    // showing a document as though the key were not there, which is how
    // somebody deletes it by saving.
    //
    // Mutation: build the rows from a fixed list of known fields. The row
    // below disappears and the value silently stops being visible.
    final editing = openTestDocument()..select(Piece.brush, 0);
    editing.setField('somethingNewer', 'rain');

    await tester.pumpWidget(_inspector(editing));

    expect(find.text('somethingNewer'), findsOneWidget);
  });

  testWidgets('typing a material writes it into the document', (
    WidgetTester tester,
  ) async {
    // The gap, closed: a brush's material had no editor at all.
    //
    // Mutation: drop the `onSubmitted` on the text box. Typing changes what is
    // on screen and nothing at all in the document.
    final editing = openTestDocument()..select(Piece.brush, 0);
    var told = 0;

    await tester.pumpWidget(
      _inspector(editing, onChanged: (String _) => told++),
    );
    await tester.enterText(find.widgetWithText(TextField, 'stone'), 'default');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(editing.brush!.material, 'default');
    expect(told, 1, reason: 'the screen was not told to rebuild the scene');
  });

  testWidgets('and a switch writes a flag the format defaults to true', (
    WidgetTester tester,
  ) async {
    // `solid` is absent from the document until somebody turns it off, so the
    // row only exists once the field does — which is the honest behaviour for
    // a panel built from the row, and worth pinning so nobody "fixes" it into
    // showing every field the format could have.
    final editing = openTestDocument()..select(Piece.brush, 0);
    editing.setField('solid', true);

    await tester.pumpWidget(_inspector(editing));
    await tester.tap(_in('solid', Switch));
    await tester.pump();

    expect(editing.brush!.solid, isFalse);
  });

  testWidgets('and a vector is three boxes, each writing its own component', (
    WidgetTester tester,
  ) async {
    // A colour picked by eye is a colour nobody can reproduce from the
    // document, so these are typed rather than dragged.
    final editing = openTestDocument()..select(Piece.brush, 0);

    await tester.pumpWidget(_inspector(editing));
    // `size` is [2, 2, 2]; `at` is [0, 0, 0]. Three boxes each.
    final twos = find.widgetWithText(TextField, '2');
    expect(twos, findsNWidgets(3));

    await tester.enterText(twos.first, '6');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(editing.brush!.size.x, 6.0);
    expect(editing.brush!.size.y, 2.0, reason: 'it wrote the wrong component');
  });

  testWidgets('and a value the format cannot read changes nothing', (
    WidgetTester tester,
  ) async {
    // The tool whose job is producing documents that load must not produce one
    // that does not — and the panel must not report a change that did not
    // happen, or the scene is rebuilt from a document nobody edited.
    final editing = openTestDocument()..select(Piece.brush, 0);
    var told = 0;

    await tester.pumpWidget(
      _inspector(editing, onChanged: (String _) => told++),
    );
    await tester.enterText(find.widgetWithText(TextField, '2').first, 'wide');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(editing.brush!.size.x, 2.0);
    expect(told, 0);
  });

  testWidgets('offers the fields the format defines and the document omits', (
    WidgetTester tester,
  ) async {
    // **The half the panel exists for.** A brush is solid and casts a shadow by
    // omission, so the crypt's every wall carries neither key — and a one-way
    // platform or a piece of non-solid decoration is made by adding one. A
    // panel built purely from the row shows three fields and offers no way to
    // reach the two that matter.
    //
    // Mutation: drop the `offerable` section. The rows below disappear and the
    // editor is back to changing only what somebody else already wrote.
    final editing = openTestDocument()..select(Piece.brush, 0);

    await tester.pumpWidget(_inspector(editing));

    expect(find.text('NOT SET'), findsOneWidget);
    expect(find.text('solid'), findsOneWidget);
    expect(find.text('castsShadow'), findsOneWidget);
    expect(find.text('ramp'), findsOneWidget);
  });

  testWidgets('and setting one puts the key into the document', (
    WidgetTester tester,
  ) async {
    final editing = openTestDocument()..select(Piece.brush, 0);
    expect(editing.fields.containsKey('solid'), isFalse);

    await tester.pumpWidget(_inspector(editing));
    // Two switches: `solid` and `castsShadow`, both offered at true.
    await tester.tap(_in('castsShadow', Switch));
    await tester.pump();

    expect(editing.fields.containsKey('castsShadow'), isTrue);
    expect(editing.brush!.castsShadow, isFalse);
  });

  testWidgets('and a field once set stops being offered', (
    WidgetTester tester,
  ) async {
    // Otherwise it appears twice — once as itself and once as a default that
    // disagrees with it, which is the panel arguing with the document.
    final editing = openTestDocument()..select(Piece.brush, 0);
    editing.setField('solid', false);

    await tester.pumpWidget(_inspector(editing));

    expect(find.text('solid'), findsOneWidget);
  });

  testWidgets('and emptying a text field takes the key out again', (
    WidgetTester tester,
  ) async {
    // `surface`, a light's `name` and an entity's are "not set" by being
    // absent. Writing an empty string instead gives a brush a surface called
    // nothing — a value the format reads happily and no game means — so
    // clearing the box is how a person says "no value".
    //
    // Mutation: write the empty string through. The key stays, the brush gets
    // a surface named '', and the physics looks it up and finds nothing.
    final editing = openTestDocument()..select(Piece.brush, 0);
    editing.setField('surface', 'ice');

    await tester.pumpWidget(_inspector(editing));
    await tester.enterText(_in('surface', TextField), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(editing.fields.containsKey('surface'), isFalse);
    expect(
      editing.brush!.surface,
      'stone',
      reason: 'a brush with no surface uses its material',
    );
  });
}
