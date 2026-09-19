import 'dart:io';

import 'package:release_dashboard/release_dashboard.dart';
import 'package:test/test.dart';

const String _coverage = '''
# What the showcase covers

## Set A: shading (`lib/pages/shading/`)

| id | title | main API | since |
|---|---|---|---|
| lighting-models | The six models | `LightingModel` | 0.1.0 |
| pbr-lighting | PBR | `Material` | 0.1.0 |
| normal-mapping | Normal maps | `Material.normal` | unknown |

## Set B: environment and shadows (`lib/pages/environment/`, `lib/pages/shadows/`)

| id | title | main API | since |
|---|---|---|---|
| procedural-sky | Sky | `SkySettings` | 0.2.0 |
| cascaded-shadows | Cascades | `ShadowSettings` | 0.2.0 |

## The 0.7.0 audit

To be filled in before set work starts.
''';

/// A tree with an app, a coverage list and however many pages each category
/// has, written as the workers write them.
Directory _tree({
  Map<String, int> pages = const <String, int>{},
  Map<String, int> rows = const <String, int>{},
  String coverage = _coverage,
}) {
  final root = Directory.systemTemp.createTempSync('showcase_');
  final app = Directory('${root.path}/apps/flutter3d_showcase')
    ..createSync(recursive: true);
  File('${app.path}/coverage.md').writeAsStringSync(coverage);
  for (final MapEntry(:key, :value) in pages.entries) {
    final dir = Directory('${app.path}/lib/pages/$key')
      ..createSync(recursive: true);
    for (var i = 0; i < value; i++) {
      File('${dir.path}/page_$i.dart').writeAsStringSync('// page');
      File('${dir.path}/page_$i.md').writeAsStringSync('# page');
    }
    File('${dir.path}/registry.dart').writeAsStringSync('// registry');
  }
  Directory('${app.path}/lib/catalog').createSync(recursive: true);
  for (final MapEntry(:key, :value) in rows.entries) {
    File('${app.path}/lib/catalog/$key.dart').writeAsStringSync(
      <String>[
        for (var i = 0; i < value; i++) "  Feature(\n    id: 'p$i',",
      ].join('\n'),
    );
  }
  return root;
}

CheckItem _item(List<Stage> stages, String id) =>
    stages.expand((s) => s.items).firstWhere((i) => i.id == id);

Snapshots _snapshots(ShowcaseSnapshot showcase) => Snapshots(
  git: null,
  packages: null,
  plan: const PlanSnapshot.empty(),
  probes: const <String, ProbeResult>{},
  gates: const <String, GateResult>{},
  pubdev: const PubDevSnapshot.unknown(),
  sites: const SitesSnapshot.unknown(),
  ci: const CiSnapshot.unknown(),
  showcase: showcase,
);

void main() {
  group('readShowcase', () {
    late Directory root;
    tearDown(() => root.deleteSync(recursive: true));

    test('there is nothing to read when the app is not in the tree', () {
      root = Directory.systemTemp.createTempSync('empty_');
      expect(readShowcase(root).sets, isEmpty);
    });

    test('expected pages come from the coverage list, not from the code', () {
      // Mutation: type the numbers into the reader. The row would then agree
      // with itself and stop following the list the workers write against.
      root = _tree();
      final sets = readShowcase(root).sets;
      expect(sets.map((s) => (s.id, s.expected)), <(String, int)>[
        ('a', 3),
        ('b', 2),
      ]);
      expect(sets[1].categories, <String>['environment', 'shadows']);
    });

    test('a page counts only when it has both its file and its guide', () {
      root = _tree(pages: <String, int>{'shading': 2});
      File(
        '${root.path}/apps/flutter3d_showcase/lib/pages/shading/lonely.dart',
      ).writeAsStringSync('// no guide');
      expect(readShowcase(root).sets.first.pages, 2);
    });

    test('catalog rows are counted apart from pages', () {
      root = _tree(
        pages: <String, int>{'shading': 2},
        rows: <String, int>{'shading': 3},
      );
      final set = readShowcase(root).sets.first;
      expect((set.pages, set.catalogRows), (2, 3));
    });

    test('a set of two categories adds them up', () {
      root = _tree(pages: <String, int>{'environment': 1, 'shadows': 1});
      expect(readShowcase(root).sets[1].pages, 2);
    });

    test('the audit is filled in once its placeholder sentence is gone', () {
      root = _tree();
      expect(readShowcase(root).coverageFilled, isFalse);
      final filled = _tree(
        coverage: _coverage.replaceAll(
          'To be filled in before set work starts.',
          'Every entry is covered.',
        ),
      );
      addTearDown(() => filled.deleteSync(recursive: true));
      expect(readShowcase(filled).coverageFilled, isTrue);
    });
  });

  group('stage F', () {
    ShowcaseSet set({
      required int expected,
      required int pages,
      required int rows,
    }) => ShowcaseSet(
      id: 'a',
      title: 'shading',
      categories: const <String>['shading'],
      expected: expected,
      pages: pages,
      catalogRows: rows,
    );

    List<Stage> stagesWith(ShowcaseSet s) => buildChecklist(
      _snapshots(ShowcaseSnapshot(sets: <ShowcaseSet>[s], live: null)),
      const ReleaseConfig(),
    );

    test('a set with no pages yet is waiting, with the count in words', () {
      final item = _item(
        stagesWith(set(expected: 18, pages: 0, rows: 0)),
        'f-set-a',
      );
      expect(item.level, Level.pending);
      expect(item.detail, contains('0 of 18'));
    });

    test('a set part of the way is in progress', () {
      expect(
        _item(
          stagesWith(set(expected: 18, pages: 7, rows: 7)),
          'f-set-a',
        ).level,
        Level.running,
      );
    });

    test('a finished set is green', () {
      expect(
        _item(stagesWith(set(expected: 3, pages: 3, rows: 3)), 'f-set-a').level,
        Level.pass,
      );
    });

    test('a finished set with a page missing from the catalog is red', () {
      // Mutation: count only the pages. A page nobody listed would be green
      // here and absent from the app.
      final item = _item(
        stagesWith(set(expected: 3, pages: 3, rows: 2)),
        'f-set-a',
      );
      expect(item.level, Level.fail);
      expect(item.detail, contains('2 catalog rows'));
    });

    test('the site is not asked about a showcase that is behind a login', () {
      final stages = stagesWith(set(expected: 1, pages: 1, rows: 1));
      expect(_item(stages, 'f-deployed').level, Level.unknown);
    });

    test('a showcase that answers is published', () {
      final stages = buildChecklist(
        _snapshots(const ShowcaseSnapshot(sets: <ShowcaseSet>[], live: true)),
        const ReleaseConfig(),
      );
      expect(_item(stages, 'f-deployed').level, Level.pass);
    });

    test('with no coverage list there is one waiting row, not nine', () {
      final stages = buildChecklist(
        _snapshots(const ShowcaseSnapshot.absent()),
        const ReleaseConfig(),
      );
      final ids = stages.last.items.map((i) => i.id);
      expect(ids, contains('f-sets'));
      expect(ids.where((id) => id.startsWith('f-set-')), isEmpty);
    });
  });

  group('readShowcaseLive', () {
    test('a page that says so is live', () async {
      expect(
        await readShowcaseLive(
          (_) async => '<title>flutter3d Showcase</title>',
          origin: 'https://x',
        ),
        isTrue,
      );
    });

    test('a host that would not answer is not asked, never down', () async {
      expect(
        await readShowcaseLive((_) async => null, origin: 'https://x'),
        isNull,
      );
    });

    test('some other page is a no', () async {
      expect(
        await readShowcaseLive((_) async => 'hello', origin: 'https://x'),
        isFalse,
      );
    });
  });
}
