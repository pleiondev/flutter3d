/// `gal-04`: a catalogue from somewhere else — parsed, cached, and refused
/// where its licence cannot be read.
///
///     flutter test test/remote_gallery_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart' show RecipeCategory;
import 'package:flutter3d_modeler/src/gallery/gallery_item.dart';
import 'package:flutter3d_modeler/src/gallery/outside_sources.dart';
import 'package:flutter3d_modeler/src/gallery/remote_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// A cache in a map — what a test uses where the application uses a file.
final class _Memory implements GalleryCache {
  final Map<String, String> entries = <String, String>{};

  @override
  Future<String?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, String value) async => entries[key] = value;
}

/// One entry of a `model-index.json`.
Map<String, Object?> _entry({
  required String name,
  String licence = 'CC0',
  String? artist,
  bool binary = true,
}) => <String, Object?>{
  'name': name,
  'variants': <String, Object?>{
    if (binary) 'glTF-Binary': '$name.glb',
    'glTF': '$name.gltf',
  },
  'legal': <Object?>[
    <String, Object?>{
      'license': licence,
      'licenseUrl': 'https://example.invalid/',
      'artist': ?artist,
    },
  ],
};

Fetch _answering(Map<String, Object?> byUrl, {List<String>? asked}) =>
    (String url) async {
      asked?.add(url);
      final Object? body = byUrl[url];
      if (body == null) throw StateError('nothing at $url');
      return Uint8List.fromList(utf8.encode(jsonEncode(body)));
    };

void main() {
  group('the Khronos index', () {
    test('becomes items, one per model, with the licence it names', () async {
      final asked = <String>[];
      final RemoteSource source = khronosSamples(
        fetch: _answering(<String, Object?>{
          kKhronosIndex: <Object?>[
            _entry(name: 'Box'),
            _entry(
              name: 'DamagedHelmet',
              licence: 'CC BY 4.0',
              artist: 'A. Maker',
            ),
          ],
        }, asked: asked),
      );

      final List<GalleryItem> items = await source.list();

      expect(items, hasLength(2));
      expect(items.first.id, 'khronos/Box');
      expect(items.first.isFree, isTrue);
      expect(items.first.author, isNull);
      final GalleryItem helmet = items.last;
      expect(helmet.licence.requiresAttribution, isTrue);
      expect(helmet.author, 'A. Maker');
      expect(asked, <String>[kKhronosIndex]);
    });

    test('a licence this build does not know is skipped, not guessed', () {
      // **The one case where being wrong costs somebody else.** Mutation:
      // fall back to CC0 for an unknown licence. A restricted model then
      // ships in somebody's export with no credit and no warning.
      expect(licenceNamed('CC0 1.0'), GalleryLicence.cc0);
      expect(licenceNamed('CC BY 4.0'), GalleryLicence.ccBy4);
      expect(licenceNamed('CC BY-NC 4.0'), GalleryLicence.ccByNc4);
      expect(licenceNamed('All rights reserved'), isNull);

      final RemoteSource source = khronosSamples(fetch: _answering(const {}));
      final List<GalleryItem> items = parseKhronosIndex(<Object?>[
        _entry(name: 'Secret', licence: 'All rights reserved'),
        _entry(name: 'Box'),
      ], source);
      expect(items.map((GalleryItem it) => it.name), <String>['Box']);
    });

    test('and a CC-BY entry naming no artist is skipped too', () {
      final RemoteSource source = khronosSamples(fetch: _answering(const {}));
      final List<GalleryItem> items = parseKhronosIndex(<Object?>[
        _entry(name: 'Nameless', licence: 'CC BY 4.0'),
      ], source);

      // `gal-01` refuses an item like this; skipping it here means the
      // grid never has to.
      expect(items, isEmpty);
    });

    test('an entry with no binary variant is skipped', () {
      final RemoteSource source = khronosSamples(fetch: _answering(const {}));
      expect(
        parseKhronosIndex(<Object?>[
          _entry(name: 'AsciiOnly', binary: false),
        ], source),
        isEmpty,
      );
    });

    test('a body that is not the index throws rather than half-parsing', () {
      final RemoteSource source = khronosSamples(fetch: _answering(const {}));
      expect(
        () => parseKhronosIndex(<String, Object?>{'models': 1}, source),
        throwsFormatException,
      );
    });
  });

  group('the cache', () {
    test('a second listing inside a day asks nobody', () async {
      final asked = <String>[];
      final cache = _Memory();
      final Fetch fetch = _answering(<String, Object?>{
        kKhronosIndex: <Object?>[_entry(name: 'Box')],
      }, asked: asked);

      final DateTime at = DateTime(2026, 9, 17, 10);
      await khronosSamples(fetch: fetch, cache: cache).list();
      await RemoteSource(
        id: 'khronos',
        name: 'glTF sample assets',
        url: kKhronosIndex,
        fetch: fetch,
        cache: cache,
        parse: parseKhronosIndex,
        now: () => at,
      ).list();

      // A catalogue is small, changes rarely, and is wanted every time the
      // gallery opens. Mutation: fetch on every open — six openings in an
      // afternoon are six round trips for the same list.
      expect(asked, hasLength(1));
    });

    test('and a day later it asks again', () async {
      final asked = <String>[];
      final cache = _Memory();
      final Fetch fetch = _answering(<String, Object?>{
        kKhronosIndex: <Object?>[_entry(name: 'Box')],
      }, asked: asked);
      RemoteSource at(DateTime when) => RemoteSource(
        id: 'khronos',
        name: 'glTF sample assets',
        url: kKhronosIndex,
        fetch: fetch,
        cache: cache,
        parse: parseKhronosIndex,
        now: () => when,
      );

      await at(DateTime(2026, 9, 17, 10)).list();
      await at(DateTime(2026, 9, 18, 11)).list();

      expect(asked, hasLength(2));
    });

    test(
      'a cache entry nothing can read is fetched past, not failed on',
      () async {
        final cache = _Memory()..entries['khronos'] = 'not json at all';
        final RemoteSource source = khronosSamples(
          fetch: _answering(<String, Object?>{
            kKhronosIndex: <Object?>[_entry(name: 'Box')],
          }),
          cache: cache,
        );

        // Mutation: treat an unreadable entry as an empty catalogue. The
        // gallery then refuses this source for a day, for a reason nobody
        // can see or act on.
        expect(await source.list(), hasLength(1));
      },
    );

    test('nothing is cached from a body that would not parse', () async {
      final cache = _Memory();
      final RemoteSource source = khronosSamples(
        fetch: _answering(<String, Object?>{
          kKhronosIndex: <String, Object?>{'models': 1},
        }),
        cache: cache,
      );

      await expectLater(source.list(), throwsFormatException);
      expect(cache.entries, isEmpty);
    });
  });

  test('a source that cannot be reached throws, and the screen is what '
      'catches it', () async {
    final RemoteSource source = khronosSamples(
      fetch: (String url) async => throw StateError('offline'),
    );

    // `GallerySource.list` is allowed to fail precisely so one catalogue
    // being down is a row saying so rather than an empty grid — the
    // gallery screen is where that is turned into the row.
    await expectLater(source.list(), throwsStateError);
  });

  test('the default sources need no key, so no row lies about being down', () {
    final List<GallerySource> sources = defaultOutsideSources(
      fetch: (String url) async => Uint8List(0),
    );

    // Mutation: include Sketchfab with no token. Every launch then shows
    // "could not be reached", which teaches people to ignore the row that
    // has to mean something the day a catalogue really is down.
    expect(sources.map((GallerySource it) => it.id), <String>['khronos']);
    expect(outsideSourcesNotWiredYet.keys, contains('sketchfab'));
  });

  test('a category comes from the words a catalogue uses', () {
    expect(categoryFor('Ceiling lamp'), RecipeCategory.lighting);
    expect(categoryFor('Coffee mug'), RecipeCategory.tableware);
    expect(categoryFor('Front door'), RecipeCategory.architecture);
    // A chair filed under a word nothing matches is still a chair, not a
    // model dropped for being filed oddly.
    expect(categoryFor('Seating unit'), RecipeCategory.furniture);
  });
}
