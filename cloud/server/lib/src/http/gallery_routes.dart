/// The gallery's own two endpoints — `gal-07`.
///
/// **The keys live here because they cannot live anywhere else.** An
/// application anybody can download cannot hold a secret: a key shipped
/// inside the modeller is a key on every machine that installs it. So the
/// catalogues that want one are read here, and the modeller asks this
/// server instead — which also means a licence is checked once rather than
/// in every client, and a slow catalogue is cached for everybody rather
/// than per machine.
///
/// **Two endpoints, and the second one is a proxy on purpose.**
/// `/gallery/index.json` is the list; `/gallery/model/<source>/<id>` is the
/// bytes. Handing the client a direct URL instead would put the key back in
/// the client for every source that signs its downloads, and would let a
/// catalogue see who is downloading what — neither of which is this
/// server's to give away.
///
/// **An index is answerable even when a source is not.** One catalogue
/// being down costs its own items and leaves the rest of the index
/// standing, the same rule the modeller's own grid follows; the response
/// names what could not be reached so a client can say so rather than
/// showing a list that is quietly short.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'gallery_catalogue.dart';

/// How long a client may keep the index before asking again.
///
/// **Five minutes, where the modeller's own cache is a day.** The server's
/// copy is the slow one to rebuild and it is shared; a client that
/// re-reads this every five minutes costs one cheap request and picks up a
/// newly wired source the same afternoon it lands.
const String kIndexCacheControl = 'public, max-age=300';

/// The gallery routes, mounted under `/gallery/`.
Router galleryRoutes(GalleryCatalogue catalogue) => Router()
  ..get('/index.json', (Request request) async {
    final CatalogueIndex index = await catalogue.index();
    return Response.ok(
      jsonEncode(<String, Object?>{
        'items': <Object?>[
          for (final CatalogueItem item in index.items) item.toJson(),
        ],
        // Named rather than counted: a client that says "Sketchfab could
        // not be reached" is one somebody can act on, and "3 sources
        // failed" is not.
        'unreachable': index.unreachable,
      }),
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
        'cache-control': kIndexCacheControl,
      },
    );
  })
  ..get('/model/<source>/<id|.*>', (
    Request request,
    String source,
    String id,
  ) async {
    final CatalogueDownload? model = await catalogue.download('$source/$id');
    if (model == null) {
      // The same sentence the agent's own tool gives, for the same reason:
      // "no such item" leaves somebody guessing, and naming the index says
      // where the ids come from.
      return Response.notFound(
        jsonEncode(<String, Object?>{
          'error':
              'no gallery item called $source/$id — read '
              '/gallery/index.json for the ids',
        }),
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    }
    return Response.ok(
      model.bytes,
      headers: <String, String>{
        'content-type': model.contentType,
        // A model at a given id is the same bytes tomorrow: the id names a
        // version of a catalogue entry, and a source that republishes one
        // under the same id is a source that has changed the thing rather
        // than this server having cached it wrongly.
        'cache-control': 'public, max-age=86400',
        'content-disposition': 'inline; filename="${model.fileName}"',
      },
    );
  });
