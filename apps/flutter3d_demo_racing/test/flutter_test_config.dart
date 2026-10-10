/// Holds every `testWidgets` here to the minute `dart_test.yaml` gives a test.
///
/// **`testWidgets` brings a timeout of its own.** It hands `test()` the
/// binding's `defaultTestTimeout`, ten minutes, as the test's own timeout, and
/// a test's own timeout wins over the package's — so without this file a
/// widget test could run for ten minutes in a package that says one. A factor
/// of one rather than a duration, so that what the package or the file says
/// is what applies: a reasoned `@Timeout` on a file still counts.
///
/// **And no HTTP client that answers every request with 400.** The binding
/// `flutter_test` makes for itself installs one; made here, before any test is
/// declared, it would be installed for every test in the package, and the
/// plain tests that talk to a server they started — a relay, a share server,
/// an MCP socket — would stop reaching it. A file of plain tests never had
/// that client, and a widget test here that wants a network starts its own
/// server on loopback.
///
/// The same file in every package with a widget test; the structure rule "a
/// test runs in a minute unless its reason is listed" checks that it is here
/// and that it says this.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  _MinuteBinding();
  await testMain();
}

final class _MinuteBinding extends AutomatedTestWidgetsFlutterBinding {
  _MinuteBinding() {
    defaultTestTimeout = const Timeout.factor(1);
  }

  @override
  bool get overrideHttpClient => false;
}
