/// Fetching in a browser, with the cookies of the page's own origin.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'picked_file.dart';

/// The bytes at [url], named [name].
///
/// `same-origin` credentials, so that a private model is fetched with the
/// session of whoever is looking at it — the same cookie the page itself was
/// served with, and nothing sent anywhere else.
Future<PickedFile> fetchModel(Uri url, {required String name}) async {
  final response = await web.window
      .fetch(url.toString().toJS, web.RequestInit(credentials: 'same-origin'))
      .toDart;
  if (!response.ok) {
    throw StateError('the server answered ${response.status} for ${url.path}');
  }
  final buffer = await response.arrayBuffer().toDart;
  return PickedFile(name: name, bytes: buffer.toDart.asUint8List());
}
