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
///
/// The second half is the row on its own, because the row is now the piece two
/// panels share: a hint chooses the control, the value's type chooses it when
/// nothing hinted the field, and — the case that keeps the level working
/// exactly as it did — the value's type chooses it again when the hint and what
/// is actually there disagree.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart'
    show
        ColorHint,
        EnumHint,
        EnumHintValue,
        MaterialHint,
        RangeHint,
        TextureHint;
import 'package:flutter3d_editor/src/editor_inspector.dart';
import 'package:flutter3d_editor/src/editor_state.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_cubit_helpers.dart';

/// One row on its own, which is how the hinted controls are reached without a
/// document that would have to carry a hint to get at them.
Widget _row({
  required Object? value,
  MaterialHint? hint,
  void Function(Object? value)? onWrite,
  PathOffers offers = _noPaths,
}) => MaterialApp(
  home: Scaffold(
    body: FieldRow(
      name: 'field',
      value: value,
      hint: hint,
      offers: offers,
      onWrite: onWrite ?? (Object? _) {},
    ),
  ),
);

List<String> _noPaths(List<String> suffixes) => const <String>[];

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

  testWidgets('a range hint is a slider where a bare number is a box', (
    WidgetTester tester,
  ) async {
    // **The whole point of the hints reaching a UI.** Roughness is a feel found
    // by dragging, and the panel could only offer a box to type it in because
    // the only thing it knew about the value was that it was a number.
    //
    // Mutation: drop the hint arm of the switch. The slider disappears and the
    // row is the box it was, which is what the second half of this test pins as
    // still correct for a field nothing describes.
    await tester.pumpWidget(
      _row(
        value: 0.4,
        hint: const MaterialHint(RangeHint(0.0, 1.0, step: 0.01)),
      ),
    );
    expect(find.byType(Slider), findsOneWidget);

    await tester.pumpWidget(_row(value: 0.4));
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('and dragging it writes the value the step lands on', (
    WidgetTester tester,
  ) async {
    // Written when the drag ends, not per frame: a slider recorded per pixel
    // fills all sixty-four undo steps in about a second.
    //
    // Mutation: write from `onChanged` instead. This still passes, and
    // `EditorHistory.transaction`'s own reason says why that is worse.
    Object? written;
    await tester.pumpWidget(
      _row(
        value: 0.4,
        hint: const MaterialHint(RangeHint(0.0, 1.0, step: 0.25)),
        onWrite: (Object? it) => written = it,
      ),
    );

    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(0.7);
    await tester.pump();

    expect(written, 0.75, reason: 'a step of a quarter has no 0.7 on it');
  });

  testWidgets('and a value outside the range is shown, not clamped', (
    WidgetTester tester,
  ) async {
    // The engine's own note on a hint: it describes a control and never
    // constrains the reader, so a roughness of 1.5 is what the shader receives.
    // A slider that quietly dragged it back to one would be an editor changing
    // what a picture looks like to tidy up its own control.
    //
    // Mutation: clamp the value into the hint on the way in. The line below
    // disappears and the box starts printing 1, which is a number the document
    // does not contain.
    await tester.pumpWidget(
      _row(value: 1.5, hint: const MaterialHint(RangeHint(0.0, 1.0))),
    );

    expect(find.text('1.5 is outside 0–1'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, '1.5'),
      findsOneWidget,
      reason: 'the box must go on printing what the document says',
    );
  });

  testWidgets('an enum hint is a list of the words it offers', (
    WidgetTester tester,
  ) async {
    // Mutation: keep the text box for a string. The picker disappears and
    // `alphaMode` is a field somebody has to know the spelling of.
    Object? written;
    await tester.pumpWidget(
      _row(
        value: 'opaque',
        hint: MaterialHint(
          EnumHint(<EnumHintValue>[
            const EnumHintValue('opaque', 'Opaque'),
            const EnumHintValue('blend', 'Blended'),
          ]),
        ),
        onWrite: (Object? it) => written = it,
      ),
    );

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blended').last);
    await tester.pumpAndSettle();

    expect(written, 'blend');
  });

  testWidgets('and a word the hint does not offer is shown anyway', (
    WidgetTester tester,
  ) async {
    // A material written by a newer tool names a mode this build has never
    // heard of. A picker that could not display it would show the wrong one —
    // and write the wrong one the moment anybody touched anything else.
    await tester.pumpWidget(
      _row(
        value: 'shimmer',
        hint: MaterialHint(
          EnumHint(<EnumHintValue>[const EnumHintValue('opaque', 'Opaque')]),
        ),
      ),
    );

    expect(find.text('shimmer — not one this build offers'), findsOneWidget);
  });

  testWidgets('a colour hint is a swatch beside the numbers it writes', (
    WidgetTester tester,
  ) async {
    // The numbers stay: a colour picked by eye is a colour nobody can reproduce
    // from the document, which is the argument this panel made before it had a
    // picker at all.
    //
    // Mutation: write only three components from the picker. The alpha the
    // document carried is dropped and every painted surface goes opaque.
    Object? written;
    await tester.pumpWidget(
      _row(
        value: <double>[0.5, 0.5, 0.5, 0.25],
        hint: const MaterialHint(ColorHint()),
        onWrite: (Object? it) => written = it,
      ),
    );
    expect(find.byType(TextField), findsNWidgets(4));

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GestureDetector).last);
    await tester.pumpAndSettle();

    expect(written, isA<List<num>>());
    expect((written! as List<num>).length, 4);
    expect((written! as List<num>).last, 0.25);
  });

  testWidgets('a texture hint offers the files something listed for it', (
    WidgetTester tester,
  ) async {
    // A widget cannot list a disk it was never told about, so the offer comes
    // from the caller — and a caller that offers nothing leaves a box somebody
    // types a path into, which is the only way to name a file not made yet.
    Object? written;
    await tester.pumpWidget(
      _row(
        value: 'stone.png',
        hint: const MaterialHint(TextureHint()),
        offers: (List<String> suffixes) => const <String>['brick.png'],
        onWrite: (Object? it) => written = it,
      ),
    );

    await tester.tap(find.byIcon(Icons.folder_open));
    await tester.pumpAndSettle();
    await tester.tap(find.text('brick.png'));
    await tester.pumpAndSettle();

    expect(written, 'brick.png');
  });

  testWidgets('and says when a path is not one of the suffixes it decodes', (
    WidgetTester tester,
  ) async {
    // Said rather than refused: a material may name a file a build step has yet
    // to produce. What this catches is the `.tga` dragged in from elsewhere.
    await tester.pumpWidget(
      _row(value: 'stone.tga', hint: const MaterialHint(TextureHint())),
    );

    expect(find.text('not one of .png .jpg .jpeg .ktx2'), findsOneWidget);
  });

  testWidgets('and a hint that disagrees with the value falls back to type', (
    WidgetTester tester,
  ) async {
    // **What keeps the level format editable.** A hint may come from a file
    // written by another tool, so a range over a word is a thing that arrives —
    // and the honest control for a field whose description and whose content
    // disagree is the one the content calls for.
    //
    // Mutation: match the hint alone, ignoring the value. The slider asserts on
    // a string and the panel throws instead of showing the field.
    await tester.pumpWidget(
      _row(value: 'stone', hint: const MaterialHint(RangeHint(0.0, 1.0))),
    );

    expect(find.byType(Slider), findsNothing);
    expect(find.widgetWithText(TextField, 'stone'), findsOneWidget);
  });

  testWidgets('and a hint renames the row without renaming the field', (
    WidgetTester tester,
  ) async {
    // The label is for the person; the key is still what goes in the file. A
    // row that showed `Base colour` and wrote `Base colour` would be a document
    // no reader has ever heard of.
    await tester.pumpWidget(
      _row(
        value: 0.4,
        hint: const MaterialHint(RangeHint(0.0, 1.0), label: 'Roughness'),
      ),
    );

    expect(find.text('Roughness'), findsOneWidget);
    expect(find.text('field'), findsNothing);
  });
}
