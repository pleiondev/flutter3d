/// The panel that made a level's materials authorable, out of hints.
///
///     flutter test test/material_panel_test.dart
///
/// **A brush could name a material and nothing could say what one looked
/// like.** The inspector edits what is selected, and a selection is a brush, a
/// light or an entity — so the map every brush in the document points at had no
/// panel at all.
///
/// What these tests assert is where each control came from. A slider is there
/// because a hint said the field is a range, a list because a hint said the
/// choices are finite, a file field because a hint said the value is a path —
/// none of it because this file wrote down which field is which. And the gates:
/// the level reader refuses what it cannot read, and the material reader, which
/// refuses almost nothing and warns instead, is given something that does.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart'
    show
        MaterialDocument,
        MaterialHint,
        RangeHint,
        builtInMaterialHints,
        readFmat,
        writeFmat;
import 'package:flutter3d_editor/src/material_panel.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_cubit_helpers.dart';

/// A material file with one of everything the panel can show: a colour, a
/// range, a finite set, a texture slot, and a parameter only the file itself
/// can describe.
const String _fmat = '''
{
  "fmat": 1,
  "name": "brick",
  "baseColor": [0.6, 0.3, 0.2, 1.0],
  "roughness": 0.8,
  "alphaMode": "blend",
  "textures": { "albedo": "brick.png" },
  "parameters": { "windStrength": [0.3] },
  "hints": {
    "windStrength": {
      "kind": "range", "min": 0.0, "max": 2.0, "step": 0.1, "label": "Wind"
    }
  }
}
''';

MaterialDocument _document() =>
    readFmat(Uint8List.fromList(utf8.encode(_fmat)));

Widget _panel(
  Editing editing, {
  Map<String, MaterialDocument> documents = const <String, MaterialDocument>{},
  void Function(String)? onChanged,
  void Function(String, MaterialDocument)? onMaterialWritten,
}) => MaterialApp(
  home: Scaffold(
    body: MaterialPanel(
      editing: editing,
      documents: documents,
      onChanged: onChanged ?? (String _) {},
      onMaterialWritten: onMaterialWritten,
    ),
  ),
);

/// The control inside the row keyed [key] — `field:` for a level material's own
/// fields, `file:` for the `.fmat`'s, `parameter:` for a shader's.
Finder _in(String key, Type control) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(control),
);

void main() {
  testWidgets('shows the fields of a level material', (
    WidgetTester tester,
  ) async {
    // From the material's own document, so a key the format grows appears here
    // the day it is written — the inspector's rule, applied to the other half
    // of the file.
    final editing = openTestDocument();

    await tester.pumpWidget(_panel(editing));

    expect(find.text('STONE'), findsOneWidget);
    expect(
      find.text('Base colour'),
      findsOneWidget,
      reason: 'the hint names it',
    );
  });

  testWidgets('and a hinted range is a slider', (WidgetTester tester) async {
    // **The hint reaching a UI, which is the whole task.** `roughness` is a
    // number in the document and nothing but a number, so the panel that typed
    // its controls off the value offered a box for a value that is a feel.
    //
    // Mutation: hand `levelMaterialHints` an empty map. The slider becomes a
    // text box and this fails.
    final editing = openTestDocument();
    setLevelMaterialField(editing, 'stone', 'roughness', 0.4);

    await tester.pumpWidget(_panel(editing));

    expect(_in('field:roughness', Slider), findsOneWidget);
  });

  testWidgets('and dragging it writes through to the level document', (
    WidgetTester tester,
  ) async {
    // Mutation: report the change without writing it. The document keeps 0.4
    // and the scene is rebuilt from a level nobody edited.
    final editing = openTestDocument();
    setLevelMaterialField(editing, 'stone', 'roughness', 0.4);
    var told = 0;

    await tester.pumpWidget(_panel(editing, onChanged: (String _) => told++));
    tester.widget<Slider>(_in('field:roughness', Slider)).onChangeEnd!(0.75);
    await tester.pump();

    expect(editing.level.materials['stone']!.roughness, 0.75);
    expect(told, 1);
    expect(editing.canUndo, isTrue, reason: 'one row written is one step back');
  });

  testWidgets('and an unhinted field looks exactly as it did', (
    WidgetTester tester,
  ) async {
    // The level format has no schema, and most of it never will: a key nothing
    // describes must go on being edited by the type of what is there, or this
    // change would have taken away more than it added.
    final editing = openTestDocument();
    setLevelMaterialField(editing, 'stone', 'somethingNewer', 'rain');

    await tester.pumpWidget(_panel(editing));

    expect(find.text('somethingNewer'), findsOneWidget);
    expect(_in('field:somethingNewer', TextField), findsOneWidget);
  });

  test('a value the level format cannot read is refused', () {
    // The gate the inspector already had, on the other writer. The tool whose
    // job is producing documents that load must not produce one that does not.
    //
    // Mutation: assign the row without reading the document back. The level
    // keeps a roughness of `"very"`, and the next `Level.fromJson` — a save, an
    // undo, the game itself — throws.
    final editing = openTestDocument();
    setLevelMaterialField(editing, 'stone', 'roughness', 0.4);

    expect(
      setLevelMaterialField(editing, 'stone', 'roughness', 'very'),
      isFalse,
    );
    expect(editing.level.materials['stone']!.roughness, 0.4);
    expect(
      editing.level.toJson()['materials'],
      isA<Map<String, Object?>>().having(
        (Map<String, Object?> it) =>
            (it['stone']! as Map<String, Object?>)['roughness'],
        'the row itself',
        0.4,
      ),
      reason: 'a refused write must leave the document it edited untouched',
    );
  });

  testWidgets('a material file is shown under its own heading', (
    WidgetTester tester,
  ) async {
    // The two halves go to two different files, and a panel that hid which one
    // it was about to change is a panel that edits the wrong document.
    await tester.pumpWidget(
      _panel(
        openTestDocument(),
        documents: <String, MaterialDocument>{'stone': _document()},
      ),
    );

    expect(find.text('BRICK'), findsOneWidget);
    expect(_in('file:roughness', Slider), findsOneWidget);
    expect(_in('file:alphaMode', DropdownButton<String>), findsOneWidget);
    expect(_in('file:textures/albedo', TextField), findsOneWidget);
  });

  testWidgets("and a parameter is shown by the file's own hint", (
    WidgetTester tester,
  ) async {
    // **`MaterialDocument.hints` earning its place.** `windStrength` is a
    // number in a uniform block and nothing in this engine can guess what it
    // means — the file is the only thing that can say it runs nought to two,
    // and until now there was nowhere for it to say it to.
    //
    // Mutation: read the hint from `builtInMaterialHints` alone. The slider
    // becomes a text box, because no table here has ever heard of the wind.
    await tester.pumpWidget(
      _panel(
        openTestDocument(),
        documents: <String, MaterialDocument>{'stone': _document()},
      ),
    );

    expect(find.text('Wind'), findsOneWidget);
    expect(_in('parameter:windStrength', Slider), findsOneWidget);
  });

  testWidgets('and writing one hands back a document, never a file', (
    WidgetTester tester,
  ) async {
    // The panel has no disk, the same way `Editing` can change a level it is
    // not allowed to save. What it produces is a document; who writes it is
    // somebody else's decision.
    final document = _document();
    MaterialDocument? written;
    await tester.pumpWidget(
      _panel(
        openTestDocument(),
        documents: <String, MaterialDocument>{'stone': document},
        onMaterialWritten: (String _, MaterialDocument it) => written = it,
      ),
    );

    tester.widget<Slider>(_in('file:roughness', Slider)).onChangeEnd!(0.2);
    await tester.pump();

    expect(written?.surface.roughness, 0.2);
    expect(
      document.surface.roughness,
      0.8,
      reason: 'the document handed in is a value and must not have changed',
    );
  });

  test('a material file takes a value outside the hint it carries', () {
    // **The decision the engine already made, kept.** A hint describes a
    // control and never constrains the reader: 1.5 is what the shader receives,
    // and an editor that refused to write it could not save a file it can draw.
    //
    // Mutation: clamp to the hint's ends in the gate. This fails, and the panel
    // becomes unable to represent a file the engine reads happily.
    final next = materialWith(
      _document(),
      'roughness',
      1.5,
      hint: builtInMaterialHints['roughness'],
    );

    expect(next?.surface.roughness, 1.5);
  });

  test('and refuses a value its reader would only warn about', () {
    // **The gate this task exists for.** `readFmat` almost never refuses
    // anything — an alpha mode it has never heard of becomes opaque with a note
    // — so a panel writing straight into a material document would be the one
    // place in this editor that can produce a file which does not say what it
    // appears to say.
    //
    // Mutation: return the document without comparing the warnings. The write
    // is accepted, the file says `"wobbly"`, and every reader of it silently
    // draws an opaque surface.
    expect(
      materialWith(
        _document(),
        'alphaMode',
        'wobbly',
        hint: builtInMaterialHints['alphaMode'],
      ),
      isNull,
    );
  });

  test('and refuses a value its reader would silently swallow', () {
    // The other half of the same hole: `_number` in the material reader answers
    // the default for a string and says nothing at all, where the level reader
    // throws. The hint is what makes this answerable — a range takes a number.
    //
    // Mutation: drop the shape check. The write is accepted, the roughness the
    // artist set to 0.8 becomes the default, and nothing anywhere says so.
    expect(
      materialWith(
        _document(),
        'roughness',
        'very',
        hint: builtInMaterialHints['roughness'],
      ),
      isNull,
    );
  });

  test('and refuses a document its reader could not open at all', () {
    // A version this build does not read is the one thing `readFmat` does
    // refuse, and the editor must not be the thing that writes one.
    expect(materialWith(_document(), 'fmat', 2), isNull);
  });

  test('and accepts a value that is already the reader default', () {
    // The writer omits a value equal to its default, so the key comes back
    // absent — which is the file being right without it, not the reader having
    // misunderstood. A gate that could not tell those apart would refuse every
    // field somebody set back to its default.
    final next = materialWith(
      _document(),
      'roughness',
      0.5,
      hint: builtInMaterialHints['roughness'],
    );

    expect(next?.surface.roughness, 0.5);
  });

  test('and an accepted write keeps everything the file was carrying', () {
    // The gate goes through the writer and the reader, so anything either of
    // them dropped would be dropped by editing one field. The hints are the
    // part worth pinning: they are what the next person's panel is built from.
    final next = materialWith(
      _document(),
      'roughness',
      0.25,
      hint: builtInMaterialHints['roughness'],
    )!;

    expect(next.hints['windStrength'], isA<MaterialHint>());
    expect((next.hints['windStrength']!.kind as RangeHint).max, 2.0);
    expect(next.parameters['windStrength']!.first, closeTo(0.3, 1e-6));
    expect(writeFmat(next).contains('brick.png'), isTrue);
  });
}
