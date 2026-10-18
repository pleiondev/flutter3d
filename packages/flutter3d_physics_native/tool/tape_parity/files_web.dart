// What tape_digests_test.dart reads in a browser: a file the script staged,
// fetched from the package root the test runner serves, two up from the
// test's page.
import 'dart:js_interop';

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

extension type _Response(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSString> text();
}

/// The text of `build/tape_parity/<name>`.
Future<String> readStaged(String name) async {
  final url = '../../build/tape_parity/$name';
  final response = await _fetch(url.toJS).toDart;
  if (!response.ok) {
    throw StateError(
      'fetching $url: HTTP ${response.status}; run '
      'tool/digest_platforms.sh tapes',
    );
  }
  return (await response.text().toDart).toDart;
}
