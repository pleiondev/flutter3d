/// Files served as they are on disk: the stylesheet, the scripts, the viewer.
///
/// In production nginx serves both directories and this code never sees those
/// requests; it exists so that one `dart run` is enough in development. Small
/// on purpose — a content type table and a path check, not a web server.
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
