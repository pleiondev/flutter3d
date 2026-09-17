/// `gal-03`: the grid, the filter, and what an insert leaves behind.
///
///     flutter test test/gallery_screen_test.dart
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart' hide ImportReport;
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/gallery/gallery_insert.dart';
import 'package:flutter3d_modeler/src/gallery/gallery_item.dart';
import 'package:flutter3d_modeler/src/gallery/recipe_source.dart';
import 'package:flutter3d_modeler/src/ui/gallery_screen.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm show Matrix4;

/// A source that answers with what it is given.
final class _Source implements GallerySource {
  const _Source(this.items);

  final List<GalleryItem> items;

  @override
  String get name => 'Test';

  @override
  String get id => 'test';

  @override
  Future<List<GalleryItem>> list() async => items;
}

/// A source that cannot answer at all.
final class _Broken implements GallerySource {
  const _Broken();

  @override
  String get id => 'broken';

  @override
  String get name => 'Somewhere else';

  @override
  Future<List<GalleryItem>> list() async => throw StateError('no');
}

GalleryItem _item({
  required String id,
  required GalleryLicence licence,
  String? author,
  String name = 'A thing',
  RecipeCategory category = RecipeCategory.furniture,
}) => GalleryItem(
  id: 'test/$id',
  name: name,
  about: 'One sentence about what it is.',
  category: category,
  licence: licence,
  sourceId: 'test',
  author: author,
  open: () async => BuiltModel(EditMesh.cuboid()),
);

Future<void> _pump(WidgetTester tester, List<GallerySource> sources) async {
  tester.view
    ..physicalSize = const Size(1100, 800)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: modelerTheme(),
      home: GalleryScreen(sources: sources),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every built-in recipe is on the grid', (
    WidgetTester tester,
  ) async {
    await _pump(tester, <GallerySource>[const RecipeSource()]);

    expect(find.text('Floor lamp'), findsOneWidget);
    expect(find.text('Dining chair'), findsOneWidget);
    expect(find.text('Mug'), findsOneWidget);
  });

  testWidgets('the filter is named for what it does, and turning it off '
      'shows the rest', (WidgetTester tester) async {
    await _pump(tester, <GallerySource>[
      _Source(<GalleryItem>[
        _item(id: 'free', licence: GalleryLicence.cc0, name: 'Free thing'),
        _item(
          id: 'credited',
          licence: GalleryLicence.ccBy4,
          name: 'Credited thing',
          author: 'A. Maker',
        ),
      ]),
    ]);

    // **"CC0 only" asks somebody to know what CC0 is first.** Mutation:
    // label the chip with the licence id — the person who has to decide is
    // the one least likely to know what it means.
    expect(find.text('Free thing'), findsOneWidget);
    expect(find.text('Credited thing'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('galleryFreeOnly')));
    await tester.pumpAndSettle();
    expect(find.text('Credited thing'), findsOneWidget);
    // And the credit is on the card, at the moment of choosing rather than
    // at export time.
    expect(find.text('A. Maker'), findsOneWidget);
  });

  testWidgets('a source that is down leaves the others usable', (
    WidgetTester tester,
  ) async {
    await _pump(tester, <GallerySource>[
      const _Broken(),
      _Source(<GalleryItem>[
        _item(id: 'free', licence: GalleryLicence.cc0, name: 'Free thing'),
      ]),
    ]);

    // Mutation: let the exception out. One catalogue being unreachable
    // then empties the grid, including the built-in models that never
    // needed a network at all.
    expect(find.text('Free thing'), findsOneWidget);
    expect(find.textContaining('Somewhere else'), findsOneWidget);
  });

  testWidgets('a malformed item is not listed', (WidgetTester tester) async {
    await _pump(tester, <GallerySource>[
      _Source(<GalleryItem>[
        // CC-BY with nobody to credit — `gal-01` refuses it, and the grid
        // is where that refusal has to take effect.
        _item(
          id: 'nameless',
          licence: GalleryLicence.ccBy4,
          name: 'Nameless thing',
        ),
      ]),
    ]);

    await tester.tap(find.byKey(const ValueKey<String>('galleryFreeOnly')));
    await tester.pumpAndSettle();
    expect(find.text('Nameless thing'), findsNothing);
  });

  testWidgets('a search narrows to what it names', (WidgetTester tester) async {
    await _pump(tester, <GallerySource>[const RecipeSource()]);

    await tester.enterText(
      find.byKey(const ValueKey<String>('gallerySearch')),
      'lamp',
    );
    await tester.pumpAndSettle();

    expect(find.text('Floor lamp'), findsOneWidget);
    expect(find.text('Dining chair'), findsNothing);
  });

  testWidgets('tapping a card answers with it', (WidgetTester tester) async {
    GalleryItem? picked;
    tester.view
      ..physicalSize = const Size(1100, 800)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: modelerTheme(),
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async {
              picked = await showGallery(
                context,
                sources: <GallerySource>[const RecipeSource()],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mug'));
    await tester.pumpAndSettle();

    expect(picked?.id, 'built-in/mug');
  });

  group('the insert', () {
    ModelProject oneBox() => const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'box',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: vm.Matrix4.identity(),
      ),
    );

    test('lands beside what is open rather than replacing it', () async {
      final ModelProject before = oneBox();
      final GalleryItem item = (await const RecipeSource().list()).firstWhere(
        (GalleryItem it) => it.id == 'built-in/mug',
      );

      final GalleryInsert inserted = insertIntoProject(
        before,
        item,
        await item.open(),
      );

      // **The scene somebody is building stays.** Mutation: replace the
      // project with the model. The gallery then behaves like Open, and
      // the room they were assembling is gone with one click on a mug.
      expect(inserted.project.objects, hasLength(2));
      expect(inserted.project.objects.first.name, 'box');
      expect(inserted.ids, hasLength(1));
      expect(inserted.project[inserted.ids.single]!.name, 'Mug');
    });

    test('a built model keeps its topology rather than going through a '
        'file', () async {
      final GalleryItem item = (await const RecipeSource().list()).first;
      final GalleryInsert inserted = insertIntoProject(
        const ModelProject(),
        item,
        await item.open(),
      );

      // Mutation: write the recipe to glTF and read it back. The mesh
      // arrives as `ImportedGeometry` — no topology to extrude, bevel or
      // loop-cut, which is most of what a modeller is for.
      expect(
        inserted.project[inserted.ids.single]!.geometry,
        isA<EditedGeometry>(),
      );
    });

    test('and says what it took on, where a licence asks for a credit', () {
      final GalleryItem credited = _item(
        id: 'credited',
        licence: GalleryLicence.ccBy4,
        name: 'Chair',
        author: 'A. Maker',
      );
      expect(insertSaid(credited, 1), contains('A. Maker'));
      expect(
        insertSaid(_item(id: 'free', licence: GalleryLicence.cc0), 2),
        isNot(contains('by')),
      );
    });
  });
}
