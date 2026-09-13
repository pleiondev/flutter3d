/// Fetching on a desktop, where a link is an ordinary HTTP request.
library;

import 'dart:io';
import 'dart:typed_data';

import 'picked_file.dart';

/// The bytes at [url], named [name].
Future<PickedFile> fetchModel(Uri url, {required String name}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'the server answered ${response.statusCode} for ${url.path}',
      );
    }
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    return PickedFile(name: name, bytes: builder.takeBytes());
  } finally {
    client.close();
  }
}
