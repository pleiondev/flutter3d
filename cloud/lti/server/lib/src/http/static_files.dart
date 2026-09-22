/// Files served as they are on disk: the lesson viewer's web build.
///
/// Copied from `cloud/lessons/server/lib/src/http/static_files.dart` (itself
/// copied from `cloud/server`) rather than shared — this package resolves
/// its dependencies outside the workspace, same as both of those, so there
/// is nowhere in common to put a shared file without joining one service's
/// release to another's. In production nginx serves this directory
/// directly; this exists so one `dart run` is enough in development.
library;

import 'dart:io';

import 'package:shelf/shelf.dart';

const _types = {
  'css': 'text/css; charset=utf-8',
  'js': 'text/javascript; charset=utf-8',
  'mjs': 'text/javascript; charset=utf-8',
  'html': 'text/html; charset=utf-8',
  'json': 'application/json',
  'wasm': 'application/wasm',
  'png': 'image/png',
  'svg': 'image/svg+xml',
  'ico': 'image/x-icon',
  'otf': 'font/otf',
  'ttf': 'font/ttf',
  'frag': 'application/octet-stream',
  'bin': 'application/octet-stream',
};

/// Serves files under [root]. A request for a directory gets its `index.html`.
Handler staticDirectory(String root, {required String cacheControl}) {
  final base = Directory(root).absolute.path;
  return (Request request) async {
    final relative = request.url.path;
    if (relative
        .split('/')
        .any((segment) => segment == '..' || segment.startsWith('.'))) {
      return Response.notFound('Not found');
    }
    final path = relative.isEmpty || relative.endsWith('/')
        ? '$base/${relative}index.html'
        : '$base/$relative';
    final file = File(path);
    if (!await file.exists()) return Response.notFound('Not found');

    final extension = path.contains('.')
        ? path.substring(path.lastIndexOf('.') + 1)
        : '';
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': _types[extension] ?? 'application/octet-stream',
        'content-length': '${await file.length()}',
        'cache-control': cacheControl,
      },
    );
  };
}
