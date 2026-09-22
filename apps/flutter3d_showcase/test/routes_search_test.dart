import 'package:flutter3d_showcase/src/catalog/feature.dart';
import 'package:flutter3d_showcase/src/catalog/routes.dart';
import 'package:flutter3d_showcase/src/catalog/search.dart';
import 'package:flutter_test/flutter_test.dart';

Feature _f(
  String id,
  String title,
  String since, {
  String summary = '',
  List<String> keywords = const <String>[],
}) => Feature(
  id: id,
  title: title,
  category: Category.post,
  summary: summary,
  since: since,
  evidence: '',
  keywords: keywords,
);

void main() {
  group('addresses', () {
    test('a page address round-trips with its tab and step', () {
      const PageAddress page = PageAddress(
        'bloom',
        tab: PageTab.steps,
        step: 2,
      );
      final ShowcaseAddress parsed = ShowcaseAddress.parse(page.address);
      expect(parsed, isA<PageAddress>());
      expect((parsed as PageAddress).id, 'bloom');
      expect(parsed.tab, PageTab.steps);
      expect(parsed.step, 2);
    });

    test('the demo tab is the default and is not written into the address', () {
      expect(const PageAddress('bloom').address, '/p/bloom');
    });

    test('anything that is not a page address is home, not a blank screen', () {
      // Mutation: throw on an address that does not parse. Somebody following
      // a link that has moved would see an error where they should see home.
      expect(ShowcaseAddress.parse('/nowhere/at/all'), isA<HomeAddress>());
      expect(ShowcaseAddress.parse(null), isA<HomeAddress>());
    });
  });

  group('search', () {
    final List<Feature> all = <Feature>[
      _f('a', 'Bloom', '0.1.0', summary: 'glow'),
      _f('b', 'Blooming shadows', '0.2.0'),
      _f('c', 'Fog', '0.5.1', keywords: <String>['bloom-like haze']),
      _f('d', 'Sky', '0.7.0', summary: 'has a bloom of colour'),
    ];

    test('an empty query is the whole catalog in its own order', () {
      expect(searchFeatures('  ', all), all);
    });

    test('an exact title beats a prefix, a prefix beats a mention', () {
      expect(searchFeatures('bloom', all).map((Feature f) => f.id), <String>[
        'a',
        'b',
        'c',
        'd',
      ]);
    });

    test('a query that looks like a version lists what appeared in it', () {
      expect(searchFeatures('0.5', all).map((Feature f) => f.id), <String>[
        'c',
      ]);
      expect(searchFeatures('0.7.0', all).map((Feature f) => f.id), <String>[
        'd',
      ]);
    });

    test('nothing matches is an empty list, not everything', () {
      expect(searchFeatures('zzz', all), isEmpty);
    });
  });

  group('compareVersions', () {
    test('compares numbers, not text', () {
      expect(compareVersions('0.10.0', '0.9.0'), greaterThan(0));
      expect(compareVersions('0.4.3', '0.4.3'), 0);
      expect(compareVersions('0.4.3+2', '0.4.3'), 0);
    });
  });
}
