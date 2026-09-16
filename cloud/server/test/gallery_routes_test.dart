/// `gal-07`: the two endpoints the modeller reads its gallery through.
///
///     dart test test/gallery_routes_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_models/src/http/gallery_catalogue.dart';
import 'package:flutter3d_models/src/http/gallery_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

CatalogueItem _item({
  required String id,
  String name = 'A thing',
  String licenceId = 'cc0',
  bool requiresAttribution = false,
  String? author,
}) => CatalogueItem(
  id: id,
  name: name,
  about: 'One sentence about what it is.',
  category: 'furniture',
  licenceId: licenceId,
  licenceName: requiresAttribution ? 'CC BY 4.0' : 'CC0 — public domain',
  licenceUrl: 'https://creativecommons.org/',
  requiresAttribution: requiresAttribution,
  author: author,
);

/// Through the same mount `app.dart` uses, rather than straight at the
/// router: the prefix is part of what a client sends, and a route that only
/// answers when the mount is spelled away is a route nobody can reach.
Future<Response> _get(GalleryCatalogue catalogue, String path) =>
    (Router()..mount('/gallery/', galleryRoutes(catalogue).call)).call(
      Request('GET', Uri.parse('http://localhost/gallery$path')),
    );

void main() {
  group('the index', () {
    test('answers the items, with the licence spelled out', () async {
      final Response response = await _get(
        FixedCatalogue(
          items: <CatalogueItem>[
            _item(id: 'khronos/Box', name: 'Box'),
            _item(
              id: 'somewhere/Chair',
              name: 'Chair',
              licenceId: 'cc-by-4.0',
              requiresAttribution: true,
              author: 'A. Maker',
            ),
          ],
        ),
        '/index.json',
      );

      expect(response.statusCode, 200);
      final Map<String, Object?> body =
          jsonDecode(await response.readAsString()) as Map<String, Object?>;
      final List<Object?> items = body['items']! as List<Object?>;
      expect(items, hasLength(2));

      // **The client cannot decide what a licence demands if the server
      // does not say.** Mutation: answer only the licence's own id. Every
      // client then needs its own table of what `cc-by-4.0` means, and the
      // day one of them is out of date is the day an export ships without
      // a credit.
      final Map<String, Object?> chair = items.last! as Map<String, Object?>;
      final Map<String, Object?> licence =
          chair['licence']! as Map<String, Object?>;
      expect(licence['requiresAttribution'], isTrue);
      expect(licence['url'], isNotEmpty);
      expect(chair['author'], 'A. Maker');
    });

    test('names what it could not reach rather than counting it', () async {
      final Response response = await _get(
        const FixedCatalogue(unreachable: <String>['Sketchfab']),
        '/index.json',
      );

      final Map<String, Object?> body =
          jsonDecode(await response.readAsString()) as Map<String, Object?>;
      // "3 sources failed" is not something a person can act on, and a
      // client cannot turn it into a sentence either.
      expect(body['unreachable'], <String>['Sketchfab']);
      expect(body['items'], isEmpty);
    });

    test('and lets a client keep it for a few minutes', () async {
      final Response response = await _get(
        const FixedCatalogue(),
        '/index.json',
      );

      // Five minutes where the modeller's own cache is a day: this copy is
      // the shared one, and a newly wired source should reach people the
      // same afternoon it lands.
      expect(response.headers['cache-control'], kIndexCacheControl);
    });

    test('a server with no keys is a working server', () async {
      final Response response = await _get(
        const FixedCatalogue(),
        '/index.json',
      );

      // Mutation: refuse the endpoint when nothing is configured. A deploy
      // with no keys then answers 500 to a modeller that would have been
      // perfectly happy with its own built-in models.
      expect(response.statusCode, 200);
    });
  });

  group('the model proxy', () {
    FixedCatalogue withBytes() => FixedCatalogue(
      items: <CatalogueItem>[_item(id: 'khronos/Box', name: 'Box')],
      bytesFor: (String id) async => (
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        contentType: 'model/gltf-binary',
        fileName: 'Box.glb',
      ),
    );

    test('hands back the bytes, named and typed', () async {
      final Response response = await _get(withBytes(), '/model/khronos/Box');

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'model/gltf-binary');
      expect(response.headers['content-disposition'], contains('Box.glb'));
      expect(await response.read().expand((List<int> it) => it).toList(), <int>[
        1,
        2,
        3,
        4,
      ]);
    });

    test('an id the index does not offer is refused', () async {
      final Response response = await _get(
        withBytes(),
        '/model/khronos/Spaceship',
      );

      // **A proxy that fetched whatever it was asked for would be an open
      // relay with our own key on it.** Mutation: pass the id straight to
      // the source — the server then downloads anything anybody names,
      // signed as us.
      expect(response.statusCode, 404);
      expect(await response.readAsString(), contains('/gallery/index.json'));
    });

    test('and a catalogue with nothing to download refuses too', () async {
      final Response response = await _get(
        FixedCatalogue(items: <CatalogueItem>[_item(id: 'khronos/Box')]),
        '/model/khronos/Box',
      );

      expect(response.statusCode, 404);
    });
  });
}
