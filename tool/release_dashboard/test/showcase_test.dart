import 'dart:io';

import 'package:release_dashboard/release_dashboard.dart';
import 'package:test/test.dart';

const String _coverage = '''
# What the showcase covers

## Set A: shading (`lib/pages/shading/`)

| id | title | main API | since |
|---|---|---|---|
| pbr-lighting | PBR | x | y |
| normal-mapping | Normals | x | y |
| alpha-modes | Alpha | x | y |

## Set B: environment and shadows (`lib/pages/environment/`, `lib/pages/shadows/`)

| id | title | main API | since |
|---|---|---|---|
| procedural-sky | Sky | x | y |
| cascaded-shadows | Cascades | x | y |

## The 0.7.0 audit

To be filled in before set work starts.
''';

void main() {
  late Directory root;

  void write(String path, String text) {
    final file = File('${root.path}/$path')..createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('showcase_');
    write('apps/flutter3d_showcase/coverage.md', _coverage);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('no app is an absent snapshot', () {
    final empty = Directory.systemTemp.createTempSync('nothing_');
    addTearDown(() => empty.deleteSync(recursive: true));
    expect(readShowcase(empty).sets, isEmpty);
  });

  test('what a set is measured against is the rows of its table', () {
    // Mutation: count the header row too. Every set would then expect one
    // page more than it has, and could never turn green.
    final sets = readShowcase(root).sets;
    expect(sets.map((s) => (s.id, s.expected)), <(String, int)>[
      ('a', 3),
      ('b', 2),
    ]);
    expect(sets.last.categories, <String>['environment', 'shadows']);
  });

  test('a page counts only with its file and its guide', () {
    write('apps/flutter3d_showcase/lib/pages/shading/pbr_lighting.dart', '');
    write('apps/flutter3d_showcase/lib/pages/shading/pbr_lighting.md', '');
    write('apps/flutter3d_showcase/lib/pages/shading/normal_mapping.dart', '');
    write('apps/flutter3d_showcase/lib/pages/shading/registry.dart', '');
    expect(readShowcase(root).sets.first.pages, 1);
  });

  test('catalog rows are counted from the category files', () {
    write(
      'apps/flutter3d_showcase/lib/catalog/shading.dart',
      "  Feature(\n    id: 'a',\n  ),\n  Feature(\n    id: 'b',\n  ),\n",
    );
    expect(readShowcase(root).sets.first.catalogRows, 2);
  });

  test('the audit is filled once its placeholder sentence is gone', () {
    expect(readShowcase(root).coverageFilled, isFalse);
    write(
      'apps/flutter3d_showcase/coverage.md',
      _coverage.replaceAll('To be filled in before set work starts.', 'Done.'),
    );
    expect(readShowcase(root).coverageFilled, isTrue);
  });

  group('the rows of stage F', () {
    Snapshots snapshots(ShowcaseSnapshot showcase) => Snapshots(
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

    CheckItem row(ShowcaseSnapshot showcase, String id) => buildChecklist(
      snapshots(showcase),
      const ReleaseConfig(),
    ).last.items.firstWhere((i) => i.id == id);

    ShowcaseSnapshot one(int pages, int rows, {int expected = 4}) =>
        ShowcaseSnapshot(
          sets: <ShowcaseSet>[
            ShowcaseSet(
              id: 'a',
              title: 'shading',
              categories: const <String>['shading'],
              expected: expected,
              pages: pages,
              catalogRows: rows,
            ),
          ],
          live: null,
        );

    test('a set with no page is waiting, not broken', () {
      expect(row(one(0, 0), 'f-set-a').level, Level.pending);
    });

    test('a set part way through is in progress and says how far', () {
      final item = row(one(2, 2), 'f-set-a');
      expect(item.level, Level.running);
      expect(item.detail, '2 of 4 pages');
    });

    test(
      'a set is green when every page is there and every page has a row',
      () {
        expect(row(one(4, 4), 'f-set-a').level, Level.pass);
      },
    );

    test('a page without its catalog row turns a finished set red', () {
      // Mutation: judge by pages only. A page with no catalog row is not in the
      // app, so the set would read green with a page nobody can open.
      final item = row(one(4, 3), 'f-set-a');
      expect(item.level, Level.fail);
      expect(item.detail, contains('3 catalog rows'));
    });

    test('a published host that will not say is not measured, not down', () {
      expect(row(one(4, 4), 'f-deployed').level, Level.unknown);
      expect(row(one(4, 4).withLive(true), 'f-deployed').level, Level.pass);
      expect(row(one(4, 4).withLive(false), 'f-deployed').level, Level.fail);
    });

    test('with no coverage list there is one waiting row for the sets', () {
      expect(
        row(const ShowcaseSnapshot.absent(), 'f-sets').level,
        Level.pending,
      );
    });
  });
}
